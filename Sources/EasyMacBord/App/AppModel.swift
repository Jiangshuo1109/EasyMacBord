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
    @Published var statusMessage = "等待设备连接"
    @Published var hostActions: [HostActionTarget] = []

    let permissions = PermissionCenter()
    private var expectedAcknowledgement: (bytes: UInt16, crc16: UInt16)?
    private var syncTimeoutTask: Task<Void, Never>?
    private var profileSaveTask: Task<Void, Never>?
    private var hostActionSaveTask: Task<Void, Never>?
    private let deviceSession: DeviceSession
    private let profileStore = ProfileStore()
    private let hostActionStore = HostActionStore()
    private let hostActionRegistry = HostActionRegistry()
    private let actionExecutor = ActionExecutor()

    init() {
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
        deviceSession.start()
        Task { [weak self] in
            await self?.restoreLocalState()
        }
    }

    var selectedProfile: Profile {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles[0]
    }

    func select(_ profile: Profile) {
        selectedProfileID = profile.id
        statusMessage = "已切换到\(profile.name)"
    }

    func setBinding(_ binding: ActionBinding, for control: ControlID) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        profiles[index].bindings[control] = binding
        profiles[index].updatedAt = .now
        persistProfiles()
    }

    func chooseApplicationAction() {
        let panel = NSOpenPanel()
        panel.title = "选择要打开的应用"
        panel.prompt = "登记动作"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        guard let urlValue = URL(string: url),
              ["http", "https"].contains(urlValue.scheme?.lowercased() ?? "") else {
            statusMessage = "网址格式无效"
            return
        }
        registerHostAction(HostActionTarget(kind: .url, title: title, payload: url))
    }

    func addShortcutAction(title: String, shortcutName: String) {
        guard !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "请输入快捷指令名称"
            return
        }
        registerHostAction(HostActionTarget(kind: .shortcut, title: title, payload: shortcutName))
    }

    func addSystemAction(title: String, identifier: String) {
        registerHostAction(HostActionTarget(kind: .system, title: title, payload: identifier))
    }

    func removeHostAction(_ id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            await hostActionRegistry.remove(id)
            await updateHostActions()
        }
    }

    func beginSync() {
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
                    syncState = .failed("配置帧写入失败")
                    statusMessage = "配置未发送"
                    expectedAcknowledgement = nil
                    syncTimeoutTask?.cancel()
                    syncTimeoutTask = nil
                }
            }
        } catch {
            syncState = .failed("设备未建立可写入通道")
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
                statusMessage = "已收到设备状态"
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
            syncState = .failed("设备确认与本次配置不一致")
            statusMessage = "设备未确认保存"
            expectedAcknowledgement = nil
            syncTimeoutTask?.cancel()
            syncTimeoutTask = nil
            return
        }
        syncState = .confirmed(.now)
        statusMessage = "设备已确认保存"
        expectedAcknowledgement = nil
        syncTimeoutTask?.cancel()
        syncTimeoutTask = nil
    }

    private func restoreLocalState() async {
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
    }

    private func persistProfiles() {
        let currentProfiles = profiles
        let store = profileStore
        profileSaveTask?.cancel()
        profileSaveTask = Task {
            guard !Task.isCancelled else { return }
            do {
                try await store.save(currentProfiles)
            } catch {
                if !Task.isCancelled {
                    statusMessage = "配置档保存失败"
                }
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

    private func updateHostActions() async {
        let targets = await hostActionRegistry.allTargets()
        hostActions = targets
        hostActionSaveTask?.cancel()
        let store = hostActionStore
        hostActionSaveTask = Task {
            guard !Task.isCancelled else { return }
            do {
                try await store.save(targets)
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
                recentRecords.insert(ExecutionRecord(timestamp: .now, actionTitle: id.uuidString.lowercased(), result: .failed), at: 0)
                statusMessage = "本机动作未登记"
                return
            }
            let result = await actionExecutor.execute(target)
            switch result {
            case .succeeded:
                recentRecords.insert(ExecutionRecord(timestamp: .now, actionTitle: target.title, result: .success), at: 0)
                statusMessage = "已执行：\(target.title)"
            case .failed(let reason):
                recentRecords.insert(ExecutionRecord(timestamp: .now, actionTitle: target.title, result: .failed), at: 0)
                statusMessage = "未执行：\(reason)"
            }
        }
    }

    private func startSyncTimeout() {
        syncTimeoutTask?.cancel()
        syncTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  let self,
                  self.syncState == .sending else { return }
            self.syncState = .failed("等待设备保存确认超时")
            self.statusMessage = "设备未确认保存"
            self.expectedAcknowledgement = nil
        }
    }
}
