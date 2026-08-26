import Combine
import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var connection = DeviceConnection(state: .disconnected, name: "EasyInput AI")
    @Published var profiles: [Profile] = [.preview]
    @Published var selectedProfileID: UUID = Profile.preview.id
    @Published var syncState: SyncState = .idle
    @Published var recentRecords: [ExecutionRecord] = []
    @Published var statusMessage = "正在加载本地配置"
    @Published var hostActions: [HostActionTarget] = []
    @Published private(set) var installedApplications: [InstalledApplication] = []
    @Published private(set) var isApplicationCatalogLoading = false
    @Published private(set) var isLocalStateReady = false
    @Published private(set) var syncHistory = SyncHistory()
    @Published private(set) var deviceDetails = DeviceDetails()
    @Published private(set) var profileSaveState: LocalSaveState = .saved

    let permissions = PermissionCenter()
    private var expectedAcknowledgement: (bytes: UInt16, crc16: UInt16)?
    private var syncTimeoutTask: Task<Void, Never>?
    private var profileSaveTask: Task<Void, Never>?
    private var hostActionSaveTask: Task<Void, Never>?
    private var profileSaveRevision: UInt64 = 0
    private var hostActionSaveRevision: UInt64 = 0
    private var syncHistorySaveRevision: UInt64 = 0
    private let deviceSession: DeviceSession
    private let profileStore = ProfileStore()
    private let hostActionStore = HostActionStore()
    private let syncHistoryStore = SyncHistoryStore()
    private let hostActionRegistry = HostActionRegistry()
    private let actionExecutor = ActionExecutor()

    init(startServices: Bool = true) {
        deviceSession = DeviceSession()
        deviceSession.appCommandHandler = { [weak self] payload in
            self?.receiveAppCommand(payload)
        }
        deviceSession.confirmationHandler = { [weak self] acknowledgement in
            self?.verify(acknowledgement)
        }
        deviceSession.connectionHandler = { [weak self] connection in
            self?.connection = connection
            self?.statusMessage = connection.state == .disconnected ? "等待设备连接" : "设备已连接"
        }
        guard startServices else {
            isLocalStateReady = true
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.restoreLocalState()
            self.deviceSession.start()
        }
    }

    var selectedProfile: Profile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    func select(_ profile: Profile) {
        guard requireLocalStateReady() else { return }
        selectedProfileID = profile.id
        statusMessage = "已切换到\(profile.name)"
    }

    func setBinding(_ binding: ActionBinding, for control: ControlID) {
        guard requireLocalStateReady() else { return }
        guard let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        profiles[index].bindings[control] = binding
        profiles[index].updatedAt = .now
        persistProfiles()
    }

    func addProfile() {
        guard requireLocalStateReady() else { return }
        let profile = Profile(name: Profile.nextName(existingNames: profiles.map(\.name)))
        profiles.append(profile)
        selectedProfileID = profile.id
        statusMessage = "已新建\(profile.name)"
        persistProfiles()
    }

    func chooseApplicationAction() {
        guard requireLocalStateReady() else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要打开的应用"
        panel.prompt = "登记动作"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        registerApplication(at: url)
    }

    func registerInstalledApplication(_ application: InstalledApplication) {
        guard requireLocalStateReady() else { return }
        registerApplication(at: application.url)
    }

    func refreshInstalledApplications() {
        guard !isApplicationCatalogLoading else { return }
        isApplicationCatalogLoading = true
        Task { [weak self] in
            let applications = await Task.detached(priority: .userInitiated) {
                InstalledApplicationCatalog.discover()
            }.value
            guard let self, !Task.isCancelled else { return }
            self.installedApplications = applications
            self.isApplicationCatalogLoading = false
        }
    }

    func addSystemTool(_ tool: SystemTool) {
        guard requireLocalStateReady() else { return }
        guard tool != .wallpaper else {
            chooseWallpaperAction()
            return
        }
        registerSystemAction(title: tool.title, identifier: tool.rawValue)
    }

    func chooseWallpaperAction() {
        guard requireLocalStateReady() else { return }
        let panel = NSOpenPanel()
        panel.title = "选择壁纸图片"
        panel.prompt = "登记动作"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        registerSystemAction(title: SystemTool.wallpaper.title, identifier: SystemTool.wallpaper.rawValue, fileURL: url)
    }

    private func registerApplication(at url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let target = try await hostActionRegistry.makeApplicationTarget(url: url)
                await updateHostActions()
                statusMessage = "已登记本机动作：\(target.title)"
            } catch {
                statusMessage = "无法保存应用访问授权"
            }
        }
    }

    func addURLAction(title: String, url: String) {
        guard requireLocalStateReady() else { return }
        guard let urlValue = URL(string: url),
              ["http", "https"].contains(urlValue.scheme?.lowercased() ?? "") else {
            statusMessage = "网址格式无效"
            return
        }
        registerHostAction(HostActionTarget(kind: .url, title: title, payload: url))
    }

    func addShortcutAction(title: String, shortcutName: String) {
        guard requireLocalStateReady() else { return }
        guard !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请输入快捷指令名称"
            return
        }
        registerHostAction(HostActionTarget(kind: .shortcut, title: title, payload: shortcutName))
    }

    func addSystemAction(title: String, identifier: String) {
        guard requireLocalStateReady() else { return }
        registerSystemAction(title: title, identifier: identifier)
    }

    func removeHostAction(_ id: UUID) {
        guard requireLocalStateReady() else { return }
        Task { [weak self] in
            guard let self else { return }
            await hostActionRegistry.remove(id)
            await updateHostActions()
        }
    }

    func testHostAction(_ id: UUID) {
        guard requireLocalStateReady() else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let target = await hostActionRegistry.target(for: id) else {
                appendRecord(title: "未登记本机动作", result: .failed, source: .manualTest)
                statusMessage = "本机动作未登记"
                return
            }
            await execute(target, source: .manualTest)
        }
    }

    func beginSync() {
        guard requireLocalStateReady() else { return }
        guard syncState != .sending else { return }
        do {
            let config = try FirmwareProfileSerializer.makeConfiguration(from: selectedProfile)
            let frames = try DeviceProtocol.makeConfigurationFrames(json: config)
            expectedAcknowledgement = (UInt16(config.count), DeviceProtocol.crc16CCITT(config))
            syncState = .sending
            statusMessage = "正在等待设备确认"
            startSyncTimeout()
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await deviceSession.sendConfiguration(frames)
                } catch {
                    guard self.syncState == .sending else { return }
                    recordSyncFailure("配置帧写入失败")
                    statusMessage = "配置未发送"
                }
            }
        } catch {
            recordSyncFailure("设备未建立可写入通道")
            statusMessage = "配置未发送"
            expectedAcknowledgement = nil
        }
    }

    func receiveAppCommand(_ payload: Data) {
        do {
            switch try DeviceProtocol.decodeAppCommand(payload: payload) {
            case .configurationAcknowledgement(let acknowledgement):
                verify(acknowledgement)
            case .hostAction(let id):
                executeHostAction(id)
            case .statusResponse:
                statusMessage = "已收到设备状态响应；详情尚未定义"
            case .unknown:
                statusMessage = "收到未识别的设备消息"
            }
        } catch {
            statusMessage = "设备消息格式无效"
        }
    }

    private func verify(_ acknowledgement: DeviceProtocol.ConfigurationAcknowledgement) {
        guard let expected = expectedAcknowledgement,
              acknowledgement.phase == 1,
              acknowledgement.ok,
              acknowledgement.saved,
              acknowledgement.bytes == expected.bytes,
              acknowledgement.crc16 == expected.crc16 else {
            recordSyncFailure("设备确认与本次配置不一致")
            statusMessage = "设备未确认保存"
            expectedAcknowledgement = nil
            syncTimeoutTask?.cancel()
            syncTimeoutTask = nil
            return
        }
        let confirmedAt = Date.now
        syncState = .confirmed(confirmedAt)
        syncHistory.recordConfirmation(acknowledgement, at: confirmedAt)
        persistSyncHistory()
        statusMessage = "设备已确认保存"
        expectedAcknowledgement = nil
        syncTimeoutTask?.cancel()
        syncTimeoutTask = nil
    }

    private func restoreLocalState() async {
        defer { isLocalStateReady = true }
        do {
            let storedProfiles = try await profileStore.load()
            if !storedProfiles.isEmpty {
                profiles = storedProfiles
                selectedProfileID = storedProfiles[0].id
            }
        } catch {
            statusMessage = "配置档无法读取，已使用默认配置"
        }

        do {
            let targets = try await hostActionStore.load()
            await hostActionRegistry.replace(with: targets)
            hostActions = await hostActionRegistry.allTargets()
        } catch {
            statusMessage = "本机动作无法读取，请重新登记"
        }

        do {
            syncHistory = try await syncHistoryStore.load()
        } catch {
            statusMessage = "同步记录无法读取"
        }
    }

    private func persistProfiles() {
        let currentProfiles = profiles
        let store = profileStore
        profileSaveTask?.cancel()
        profileSaveState = .saving
        profileSaveRevision &+= 1
        let revision = profileSaveRevision
        profileSaveTask = Task {
            guard !Task.isCancelled else { return }
            do {
                try await store.save(currentProfiles, revision: revision)
                guard !Task.isCancelled else { return }
                profileSaveState = .saved
            } catch {
                if !Task.isCancelled {
                    statusMessage = "配置档保存失败"
                    profileSaveState = .failed
                }
            }
        }
    }

    private func persistSyncHistory() {
        let currentHistory = syncHistory
        let store = syncHistoryStore
        syncHistorySaveRevision &+= 1
        let revision = syncHistorySaveRevision
        Task {
            do {
                try await store.save(currentHistory, revision: revision)
            } catch {
                statusMessage = "同步记录保存失败"
            }
        }
    }

    private func registerHostAction(_ target: HostActionTarget) {
        Task { [weak self] in
            guard let self else { return }
            await hostActionRegistry.register(target)
            await updateHostActions()
            statusMessage = "已登记本机动作：\(target.title)"
        }
    }

    private func registerSystemAction(title: String, identifier: String, fileURL: URL? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let target = try await hostActionRegistry.makeSystemTarget(
                    title: title,
                    identifier: identifier,
                    fileURL: fileURL
                )
                await updateHostActions()
                statusMessage = "已登记本机动作：\(target.title)"
            } catch {
                statusMessage = "无法保存所选文件的访问授权"
            }
        }
    }

    private func updateHostActions() async {
        let targets = await hostActionRegistry.allTargets()
        hostActions = targets
        hostActionSaveTask?.cancel()
        let store = hostActionStore
        hostActionSaveRevision &+= 1
        let revision = hostActionSaveRevision
        hostActionSaveTask = Task {
            guard !Task.isCancelled else { return }
            do {
                try await store.save(targets, revision: revision)
            } catch {
                if !Task.isCancelled {
                    statusMessage = "动作库保存失败"
                }
            }
        }
    }

    private func executeHostAction(_ id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            guard let target = await hostActionRegistry.target(for: id) else {
                appendRecord(title: "未登记本机动作", result: .failed, source: .device)
                statusMessage = "本机动作未登记"
                return
            }
            await execute(target, source: .device)
        }
    }

    private func execute(_ target: HostActionTarget, source: ExecutionRecord.Source) async {
        let result = await actionExecutor.execute(target)
        switch result {
        case .succeeded:
            appendRecord(title: target.title, result: .success, source: source)
            statusMessage = "已执行：\(target.title)"
        case .failed(let reason):
            appendRecord(title: target.title, result: .failed, source: source)
            statusMessage = "未执行：\(reason)"
        }
    }

    private func appendRecord(title: String, result: ExecutionRecord.ResultState, source: ExecutionRecord.Source) {
        recentRecords.insert(ExecutionRecord(timestamp: .now, actionTitle: title, result: result, source: source), at: 0)
        recentRecords = Array(recentRecords.prefix(20))
    }

    private func requireLocalStateReady() -> Bool {
        guard isLocalStateReady else {
            statusMessage = "正在加载本地配置"
            return false
        }
        return true
    }

    private func recordSyncFailure(_ reason: String) {
        syncState = .failed(reason)
        expectedAcknowledgement = nil
        syncTimeoutTask?.cancel()
        syncTimeoutTask = nil
        syncHistory.recordFailure(reason)
        persistSyncHistory()
    }

    private func startSyncTimeout() {
        syncTimeoutTask?.cancel()
        syncTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  let self,
                  self.syncState == .sending else { return }
            self.recordSyncFailure("等待设备保存确认超时")
            self.statusMessage = "设备未确认保存"
        }
    }
}

#if DEBUG
extension AppModel {
    func applyDebugUIState(_ state: DebugUIState) {
        let confirmedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let acknowledgement = DeviceProtocol.ConfigurationAcknowledgement(
            phase: 1,
            ok: true,
            bytes: 256,
            crc16: 0x12AB,
            saved: true
        )

        profileSaveState = .saved
        hostActions = []
        recentRecords = []
        syncHistory = SyncHistory()
        deviceDetails = DeviceDetails()
        permissions.applyDebugStates([
            .accessibility: .required,
            .screenRecording: .required,
            .automation: .notChecked
        ])

        switch state {
        case .disconnected:
            connection = DeviceConnection(state: .disconnected, name: "EasyInput AI")
            syncState = .idle
            statusMessage = "等待设备连接"
        case .connecting:
            connection = DeviceConnection(state: .connecting, name: "EasyInput AI")
            syncState = .idle
            statusMessage = "正在查找设备"
        case .syncSending:
            connection = .preview
            syncState = .sending
            statusMessage = "正在等待设备确认"
        case .syncConfirmed:
            connection = .preview
            syncState = .confirmed(confirmedAt)
            syncHistory.recordConfirmation(acknowledgement, at: confirmedAt)
            statusMessage = "设备已确认保存"
        case .syncFailed:
            connection = DeviceConnection(state: .connected(.bluetooth), name: "EasyInput AI")
            syncState = .failed("等待设备保存确认超时")
            syncHistory.recordConfirmation(acknowledgement, at: confirmedAt)
            syncHistory.recordFailure("等待设备保存确认超时")
            statusMessage = "设备未确认保存"
        case .emptyActions:
            connection = .preview
            syncState = .idle
            statusMessage = "等待设备同步"
        case .permissionDenied:
            connection = .preview
            syncState = .idle
            statusMessage = "部分操作需要系统授权"
        case .longNames:
            connection = DeviceConnection(
                state: .connected(.usb),
                name: "EasyInput 日常效率控制台 - 长名称验收设备"
            )
            profiles = [Profile(name: "工作日高频操作与专注模式配置档名称验收")]
            selectedProfileID = profiles[0].id
            syncState = .idle
            statusMessage = "用于检查标题、列表和卡片的长文本截断"
        }
    }
}
#endif
