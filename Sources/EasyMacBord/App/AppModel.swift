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
    @Published private(set) var inputPresets: [InputPreset] = []
    @Published private(set) var installedApplications: [InstalledApplication] = []
    @Published private(set) var isApplicationCatalogLoading = false
    @Published private(set) var isLocalStateReady = false
    @Published private(set) var syncHistory = SyncHistory()
    @Published private(set) var deviceDetails = DeviceDetails()
    @Published private(set) var profileSaveState: LocalSaveState = .saved
    @Published private(set) var profileActivationRules: [ProfileActivationRule] = []
    @Published private(set) var isAutomaticProfileSwitching = true
    @Published var pendingDestructiveAction: HostActionTarget?
    @Published var isScreenCleanerPresented = false
#if DEBUG
    @Published var debugActionLibrarySearchText: String?
#endif

    let permissions = PermissionCenter()
    private var expectedAcknowledgement: (bytes: UInt16, crc16: UInt16)?
    private var syncTimeoutTask: Task<Void, Never>?
    private var profileSaveTask: Task<Void, Never>?
    private var hostActionSaveTask: Task<Void, Never>?
    private var inputPresetSaveTask: Task<Void, Never>?
    private var activationRuleSaveTask: Task<Void, Never>?
    private var automaticSyncTask: Task<Void, Never>?
    private var deviceStatusTimeoutTask: Task<Void, Never>?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var profileSaveRevision: UInt64 = 0
    private var hostActionSaveRevision: UInt64 = 0
    private var inputPresetSaveRevision: UInt64 = 0
    private var activationRuleSaveRevision: UInt64 = 0
    private var syncHistorySaveRevision: UInt64 = 0
    private var syncingProfileID: UUID?
    private var deviceStatusReadState = DeviceStatusReadState()
    private let deviceSession: DeviceSession
    private let profileStore = ProfileStore()
    private let hostActionStore = HostActionStore()
    private let inputPresetStore = InputPresetStore()
    private let activationRuleStore = ProfileActivationStore()
    private let syncHistoryStore = SyncHistoryStore()
    private let hostActionRegistry = HostActionRegistry()
    private let actionExecutor = ActionExecutor()
    private let defaults: UserDefaults
    private var pendingAutomaticSyncProfileID: UUID?

    private static let automaticProfileSwitchingDefaultsKey = "preferences.automaticProfileSwitching"

    init(startServices: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.automaticProfileSwitchingDefaultsKey) == nil {
            isAutomaticProfileSwitching = true
        } else {
            isAutomaticProfileSwitching = defaults.bool(forKey: Self.automaticProfileSwitchingDefaultsKey)
        }
        deviceSession = DeviceSession()
        deviceSession.appCommandHandler = { [weak self] payload in
            self?.receiveAppCommand(payload)
        }
        deviceSession.confirmationHandler = { [weak self] acknowledgement in
            self?.verify(acknowledgement)
        }
        deviceSession.statusHandler = { [weak self] status in
            self?.receiveDeviceStatus(status)
        }
        deviceSession.statusErrorHandler = { [weak self] _ in
            self?.deviceStatusReadState.finish()
            self?.statusMessage = "设备状态响应无效"
        }
        deviceSession.connectionHandler = { [weak self] connection in
            self?.didChangeConnection(connection)
        }
        guard startServices else {
            isLocalStateReady = true
            return
        }

        observeFrontmostApplications()

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

    func setAutomaticProfileSwitching(_ isEnabled: Bool) {
        guard isAutomaticProfileSwitching != isEnabled else { return }
        isAutomaticProfileSwitching = isEnabled
        defaults.set(isEnabled, forKey: Self.automaticProfileSwitchingDefaultsKey)
        if !isEnabled {
            pendingAutomaticSyncProfileID = nil
            automaticSyncTask?.cancel()
            automaticSyncTask = nil
        }
    }

    func addProfileActivationRule(profileID: UUID, application: InstalledApplication) {
        guard requireLocalStateReady() else { return }
        guard let bundleIdentifier = application.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            statusMessage = "所选应用没有可用于匹配的 Bundle ID"
            return
        }
        let rule = ProfileActivationRule(
            profileID: profileID,
            applicationBundleID: bundleIdentifier,
            applicationName: application.name
        )
        if let issue = ProfileActivationRules.validate(rule, profiles: profiles, existingRules: profileActivationRules) {
            statusMessage = activationRuleIssueMessage(issue)
            return
        }
        profileActivationRules.append(rule)
        persistActivationRules()
        statusMessage = "已为 " + application.name + " 设置自动切换"
    }

    func setProfileActivationRuleEnabled(_ id: UUID, isEnabled: Bool) {
        guard requireLocalStateReady(), let index = profileActivationRules.firstIndex(where: { $0.id == id }) else { return }
        var rule = profileActivationRules[index]
        rule.isEnabled = isEnabled
        if let issue = ProfileActivationRules.validate(rule, profiles: profiles, existingRules: profileActivationRules) {
            statusMessage = activationRuleIssueMessage(issue)
            return
        }
        profileActivationRules[index] = rule
        persistActivationRules()
    }

    func removeProfileActivationRule(_ id: UUID) {
        guard requireLocalStateReady() else { return }
        profileActivationRules.removeAll { $0.id == id }
        persistActivationRules()
    }

    func setBinding(_ binding: ActionBinding, for control: ControlID) {
        guard requireLocalStateReady() else { return }
        guard let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        profiles[index].bindings[control] = binding
        profiles[index].updatedAt = .now
        persistProfiles()
    }

    func applyInputPreset(_ preset: InputPreset, to control: ControlID) {
        guard requireLocalStateReady() else { return }
        setBinding(preset.makeBinding(), for: control)
        statusMessage = "已应用预设：\(preset.title)"
    }

    @discardableResult
    func saveInputPreset(id: UUID? = nil, kind: InputPreset.Kind, title: String, value: String) -> InputPreset? {
        guard requireLocalStateReady() else { return nil }
        guard !value.isEmpty else {
            statusMessage = kind == .fixedText ? "请输入固定文本" : "请录制组合键"
            return nil
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? defaultPresetTitle(kind: kind, value: value) : trimmedTitle
        let preset = InputPreset(id: id ?? UUID(), kind: kind, title: resolvedTitle, value: value)
        if let index = inputPresets.firstIndex(where: { $0.id == preset.id }) {
            inputPresets[index] = preset
        } else {
            inputPresets.append(preset)
        }
        inputPresets.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        persistInputPresets()
        statusMessage = "已保存预设：\(preset.title)"
        return preset
    }

    func removeInputPreset(_ id: UUID) {
        guard requireLocalStateReady() else { return }
        inputPresets.removeAll { $0.id == id }
        persistInputPresets()
        statusMessage = "已移除预设"
    }

    func addInputPresetTemplate(_ template: InputPresetTemplate) {
        guard requireLocalStateReady() else { return }
        guard !inputPresets.contains(where: {
            $0.kind == .keyChord && $0.value == template.chord
        }) else {
            statusMessage = "该组合键预设已存在"
            return
        }
        _ = saveInputPreset(kind: .keyChord, title: template.title, value: template.chord)
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

    func chooseScriptAction() {
        guard requireLocalStateReady() else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要授权运行的脚本"
        panel.prompt = "授权脚本"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        let scriptTypes: [UTType] = ["scpt", "applescript", "command", "sh"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowedContentTypes = scriptTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        registerScript(at: url)
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
        if tool == .waterReminder {
            addWaterReminderAction(minutes: 30)
            return
        }
        registerSystemAction(title: tool.title, identifier: tool.rawValue)
    }

    func addWaterReminderAction(minutes: Int) {
        guard requireLocalStateReady() else { return }
        guard (1...1_440).contains(minutes) else {
            statusMessage = "提醒间隔需在 1 到 1440 分钟之间"
            return
        }
        registerSystemAction(
            title: "喝水提醒（每 " + String(minutes) + " 分钟）",
            identifier: "waterReminder:\(minutes)"
        )
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

    private func registerScript(at url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let target = try await hostActionRegistry.makeScriptTarget(url: url)
                await updateHostActions()
                statusMessage = "已登记授权脚本：\(target.title)"
            } catch HostActionRegistry.RegistryError.unsupportedScriptFile {
                statusMessage = "脚本类型不受支持"
            } catch {
                statusMessage = "无法保存脚本访问授权"
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
        beginSync(isAutomatic: false)
    }

    private func beginSync(isAutomatic: Bool) {
        guard requireLocalStateReady() else { return }
        guard syncState != .sending else { return }
        if !isAutomatic {
            // A manual sync supersedes a pending foreground-app debounce.
            automaticSyncTask?.cancel()
            automaticSyncTask = nil
            pendingAutomaticSyncProfileID = nil
        }
        if let action = selectedProfile.firstUnsupportedSemanticAction(for: deviceDetails) {
            syncState = .failed("设备未确认语义动作")
            statusMessage = "设备未确认语义动作：\(action.title)"
            return
        }
        do {
            let config = try FirmwareProfileSerializer.makeConfiguration(from: selectedProfile)
            let frames = try DeviceProtocol.makeConfigurationFrames(json: config)
            expectedAcknowledgement = (UInt16(config.count), DeviceProtocol.crc16CCITT(config))
            syncingProfileID = selectedProfileID
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

    func requestDeviceStatus() {
        guard requireLocalStateReady() else { return }
        guard connection.state == .connected(.usb) else {
            statusMessage = "设备状态仅在 USB 已连接时读取"
            return
        }
        do {
            _ = try deviceSession.requestStatus(fresh: true)
            let generation = deviceStatusReadState.begin()
            statusMessage = "正在读取设备状态"
            deviceStatusTimeoutTask?.cancel()
            deviceStatusTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled,
                      self.deviceStatusReadState.isActive(generation) else { return }
                self.deviceStatusReadState.finish()
                self.statusMessage = "未收到有效设备状态"
            }
        } catch {
            statusMessage = "设备未提供可读取的状态通道"
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
        let completedProfileID = syncingProfileID
        syncState = .confirmed(confirmedAt)
        syncHistory.recordConfirmation(acknowledgement, at: confirmedAt)
        persistSyncHistory()
        statusMessage = "设备已确认保存"
        expectedAcknowledgement = nil
        syncingProfileID = nil
        syncTimeoutTask?.cancel()
        syncTimeoutTask = nil
        if pendingAutomaticSyncProfileID == completedProfileID {
            pendingAutomaticSyncProfileID = nil
        }
        schedulePendingAutomaticSyncIfPossible()
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
            let loadedRules = try await activationRuleStore.load()
            let validProfileIDs = Set(profiles.map(\.id))
            profileActivationRules = loadedRules.filter { validProfileIDs.contains($0.profileID) }
        } catch {
            statusMessage = "自动切换规则无法读取，请重新设置"
        }

        do {
            let targets = try await hostActionStore.load()
            await hostActionRegistry.replace(with: targets)
            hostActions = await hostActionRegistry.allTargets()
        } catch {
            statusMessage = "本机动作无法读取，请重新登记"
        }

        do {
            inputPresets = try await inputPresetStore.load()
        } catch {
            statusMessage = "动作预设无法读取，请重新登记"
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
                schedulePendingAutomaticSyncIfPossible()
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

    private func persistInputPresets() {
        let presets = inputPresets
        let store = inputPresetStore
        inputPresetSaveTask?.cancel()
        inputPresetSaveRevision &+= 1
        let revision = inputPresetSaveRevision
        inputPresetSaveTask = Task {
            guard !Task.isCancelled else { return }
            do {
                try await store.save(presets, revision: revision)
            } catch {
                if !Task.isCancelled {
                    statusMessage = "动作预设保存失败"
                }
            }
        }
    }

    private func persistActivationRules() {
        let rules = profileActivationRules
        let store = activationRuleStore
        activationRuleSaveTask?.cancel()
        activationRuleSaveRevision &+= 1
        let revision = activationRuleSaveRevision
        activationRuleSaveTask = Task {
            guard !Task.isCancelled else { return }
            do {
                try await store.save(rules, revision: revision)
            } catch {
                if !Task.isCancelled {
                    statusMessage = "自动切换规则保存失败"
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
        if target.kind == .system, target.payload == SystemTool.screenCleaner.rawValue {
            isScreenCleanerPresented = true
            appendRecord(title: target.title, result: .success, source: source)
            statusMessage = "已打开清洁屏幕遮罩"
            return
        }
        if target.kind == .system, target.payload == SystemTool.emptyTrash.rawValue {
            pendingDestructiveAction = target
            statusMessage = "清空废纸篓需要在本机确认"
            return
        }
        let result = await actionExecutor.execute(target)
        let isWaterReminder = SystemTool.waterReminderMinutes(from: target.payload) != nil
        if target.requiresAutomationPermission {
            switch result {
            case .succeeded:
                permissions.recordAutomationSuccess()
            case .failed:
                permissions.recordAutomationFailure()
            }
        }
        if isWaterReminder {
            switch result {
            case .succeeded:
                permissions.recordNotificationSuccess()
            case .failed:
                permissions.recordNotificationFailure()
            }
        }
        switch result {
        case .succeeded:
            appendRecord(title: target.title, result: .success, source: source)
            statusMessage = "已执行：\(target.title)"
        case .failed(let reason):
            appendRecord(title: target.title, result: .failed, source: source)
            statusMessage = "未执行：\(reason)"
        }
    }

    func confirmPendingDestructiveAction() {
        guard let target = pendingDestructiveAction else { return }
        pendingDestructiveAction = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await actionExecutor.execute(target)
            switch result {
            case .succeeded:
                permissions.recordAutomationSuccess()
                appendRecord(title: target.title, result: .success, source: .manualTest)
                statusMessage = "已执行：\(target.title)"
            case .failed(let reason):
                permissions.recordAutomationFailure()
                appendRecord(title: target.title, result: .failed, source: .manualTest)
                statusMessage = "未执行：\(reason)"
            }
        }
    }

    func cancelPendingDestructiveAction() {
        pendingDestructiveAction = nil
        statusMessage = "已取消清空废纸篓"
    }

    func closeScreenCleaner() {
        isScreenCleanerPresented = false
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
        syncingProfileID = nil
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

    private func receiveDeviceStatus(_ status: DeviceProtocol.DeviceStatus) {
        deviceStatusReadState.finish()
        deviceStatusTimeoutTask?.cancel()
        deviceStatusTimeoutTask = nil
        let capabilitySummary = status.capabilities
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\(capabilityDescription($0.value))" }
            .joined(separator: "，")
        let semanticActionsAvailable: Bool?
        if case .boolean(let value) = status.capabilities["semantic_actions"] {
            semanticActionsAvailable = value
        } else {
            semanticActionsAvailable = nil
        }
        deviceDetails = DeviceDetails(
            firmwareVersion: .value(status.firmware),
            backupTransport: .unknown,
            capabilities: capabilitySummary.isEmpty ? .value("未声明") : .value(capabilitySummary),
            pttHotkey: .value(status.pttHotkey),
            editPTTHotkey: .value(status.editPTTHotkey),
            semanticActionsAvailable: semanticActionsAvailable
        )
        statusMessage = "已读取设备状态"
    }

    private func didChangeConnection(_ connection: DeviceConnection) {
        self.connection = connection
        statusMessage = connection.state == .disconnected ? "等待设备连接" : "设备已连接"
        guard case .connected = connection.state,
              let pendingProfileID = pendingAutomaticSyncProfileID,
              profileSaveState == .saved,
              syncState != .sending else { return }
        scheduleAutomaticSync(for: pendingProfileID)
    }

    private func observeFrontmostApplications() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                self?.handleFrontmostApplication(bundleIdentifier: application.bundleIdentifier)
            }
        }
    }

    private func handleFrontmostApplication(bundleIdentifier: String?) {
        guard isLocalStateReady else { return }
        let plan = ProfileAutoSyncPlan.make(
            bundleIdentifier: bundleIdentifier,
            rules: profileActivationRules,
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            isEnabled: isAutomaticProfileSwitching,
            isDeviceConnected: isDeviceConnected,
            isSyncing: syncState == .sending,
            isLocalSaveComplete: profileSaveState == .saved
        )
        switch plan {
        case .ignore:
            if ProfileAutoSyncPlan.shouldRetryPendingSync(
                bundleIdentifier: bundleIdentifier,
                pendingProfileID: pendingAutomaticSyncProfileID,
                rules: profileActivationRules,
                profiles: profiles,
                isEnabled: isAutomaticProfileSwitching
            ) {
                schedulePendingAutomaticSyncIfPossible()
            }
            return
        case .selectOnly(let profileID):
            selectedProfileID = profileID
            pendingAutomaticSyncProfileID = profileID
            statusMessage = "已按前台应用切换配置档，等待设备同步"
        case .selectAndSchedule(let profileID):
            selectedProfileID = profileID
            pendingAutomaticSyncProfileID = profileID
            statusMessage = "已按前台应用切换配置档"
            scheduleAutomaticSync(for: profileID)
        }
    }

    private func scheduleAutomaticSync(for profileID: UUID) {
        guard isAutomaticProfileSwitching,
              pendingAutomaticSyncProfileID == profileID,
              selectedProfileID == profileID,
              isDeviceConnected,
              syncState != .sending,
              profileSaveState == .saved else { return }
        automaticSyncTask?.cancel()
        automaticSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, !Task.isCancelled,
                  self.pendingAutomaticSyncProfileID == profileID,
                  self.selectedProfileID == profileID,
                  self.isDeviceConnected,
                  self.syncState != .sending,
                  self.profileSaveState == .saved else { return }
            self.beginSync(isAutomatic: true)
        }
    }

    private func schedulePendingAutomaticSyncIfPossible() {
        guard let profileID = pendingAutomaticSyncProfileID else { return }
        scheduleAutomaticSync(for: profileID)
    }

    private var isDeviceConnected: Bool {
        if case .connected = connection.state { return true }
        return false
    }

    private func capabilityDescription(_ value: DeviceProtocol.CapabilityValue) -> String {
        switch value {
        case .boolean(let enabled): enabled ? "true" : "false"
        case .integer(let number): String(number)
        case .string(let string): string
        }
    }

    private func activationRuleIssueMessage(_ issue: ProfileActivationRuleIssue) -> String {
        switch issue {
        case .missingApplication: "请选择可识别的本机应用"
        case .missingProfile: "目标配置档不存在"
        case .duplicateApplication: "该应用已有自动切换规则"
        }
    }

    private func defaultPresetTitle(kind: InputPreset.Kind, value: String) -> String {
        switch kind {
        case .fixedText:
            let preview = String(value.prefix(20))
            return preview.isEmpty ? "固定文本" : preview
        case .keyChord:
            return value
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
        inputPresets = []
        recentRecords = []
        syncHistory = SyncHistory()
        deviceDetails = DeviceDetails()
        permissions.applyDebugStates([
            .accessibility: .required,
            .automation: .notChecked,
            .notifications: .notChecked
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
            permissions.applyDebugStates([
                .accessibility: .required,
                .automation: .actionFailed,
                .notifications: .actionFailed
            ])
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
        case .oldFirmware:
            connection = .preview
            deviceDetails = DeviceDetails(
                firmwareVersion: .value("0.1.25"),
                capabilities: .value("semantic_actions=false"),
                pttHotkey: .unknown,
                editPTTHotkey: .unknown,
                semanticActionsAvailable: false
            )
            syncState = .idle
            statusMessage = "固件状态已读取，但未声明语义动作能力"
        case .semanticActionsUnavailable:
            connection = .preview
            deviceDetails = DeviceDetails(
                firmwareVersion: .value("0.1.26"),
                capabilities: .value("semantic_actions=false"),
                pttHotkey: .unknown,
                editPTTHotkey: .unknown,
                semanticActionsAvailable: false
            )
            statusMessage = "当前设备不支持语义动作映射"
        case .scriptMissing:
            connection = .preview
            hostActions = [
                HostActionTarget(
                    kind: .script,
                    title: "未找到的授权脚本",
                    payload: "script"
                )
            ]
            statusMessage = "脚本文件需要重新选择并授权"
        case .automaticSyncing:
            connection = .preview
            let matchedProfile = Profile(name: "Codex 文本处理")
            profiles = [Profile.preview, matchedProfile]
            selectedProfileID = matchedProfile.id
            profileActivationRules = [
                ProfileActivationRule(
                    profileID: matchedProfile.id,
                    applicationBundleID: "com.openai.codex",
                    applicationName: "Codex"
                )
            ]
            syncState = .sending
            statusMessage = "已按前台应用切换配置档，等待设备确认"
        case .ruleConflict:
            connection = .preview
            statusMessage = "同一应用只能启用一条配置档切换规则"
        case .noResults:
            connection = .preview
            debugActionLibrarySearchText = "没有匹配项"
            statusMessage = "没有匹配的动作"
        }
    }
}
#endif
