import AppKit
import SwiftUI

private enum ActionLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case mappable
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .mappable: "可映射"
        case .unavailable: "未接入"
        }
    }
}

private enum ActionLibraryCategory: String, CaseIterable, Identifiable {
    case macTools
    case appsAndURLs
    case integrations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macTools: "Mac 工具"
        case .appsAndURLs: "应用与网址"
        case .integrations: "集成"
        }
    }

    func includes(_ target: HostActionTarget) -> Bool {
        switch self {
        case .macTools:
            target.kind == .system && !target.isAppleMusicAction
        case .appsAndURLs:
            target.kind == .application || target.kind == .url
        case .integrations:
            target.kind == .shortcut || target.kind == .script || target.isAppleMusicAction
        }
    }
}

private struct DeviceCapability: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    static let unavailable: [Self] = [
        .init(
            id: "board-lighting",
            title: "板端灯效",
            detail: "当前设备合同未提供灯效控制。",
            symbol: "lightbulb"
        ),
        .init(
            id: "audio-reactive-lighting",
            title: "音乐律动灯效",
            detail: "当前版本未接入板端音频或灯效能力。",
            symbol: "waveform"
        )
    ]
}

private enum DeviceActionEligibility {
    static func isMappable(_ target: HostActionTarget) -> Bool {
        switch target.kind {
        case .application, .url, .shortcut:
            true
        case .script:
            target.bookmark != nil
        case .system:
            SystemTool.tool(forActionIdentifier: target.payload) != nil
        }
    }

    static func chips(for target: HostActionTarget) -> [ActionStatusChip] {
        var chips: [ActionStatusChip] = [
            .init(title: isMappable(target) ? "可映射" : "不可映射", tone: isMappable(target) ? .ready : .unavailable),
            .init(title: "Mac 执行", tone: .neutral)
        ]
        if target.requiresAutomationPermission && target.kind != .script {
            chips.append(.init(title: "需自动化授权", tone: .attention))
        } else if target.kind == .script {
            chips.append(
                .init(
                    title: target.bookmark == nil ? "需要文件授权" : "已授权文件",
                    tone: target.bookmark == nil ? .attention : .neutral
                )
            )
        } else {
            chips.append(.init(title: "已登记", tone: .neutral))
        }
        return chips
    }

    static func controlHint(for target: HostActionTarget) -> String {
        guard let tool = target.kind == .system
            ? SystemTool.tool(forActionIdentifier: target.payload)
            : nil else {
            return "适用：按键或旋钮按下"
        }
        switch tool {
        case .volumeUp, .musicNext:
            return "适用：旋钮右转"
        case .volumeDown, .musicPrevious:
            return "适用：旋钮左转"
        case .volumeMute, .musicPlayPause:
            return "适用：旋钮按下"
        default:
            return "适用：按键或旋钮按下"
        }
    }
}

private struct ActionStatusChip: Identifiable {
    enum Tone {
        case ready
        case neutral
        case attention
        case unavailable
    }

    let title: String
    let tone: Tone

    var id: String { "\(title)-\(String(describing: tone))" }
}

struct HostActionLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var filter: ActionLibraryFilter = .all
    @State private var showingApplicationPicker = false
    @State private var showingURLForm = false
    @State private var showingShortcutForm = false
    @State private var showingFixedTextPresetForm = false
    @State private var showingKeyChordPresetForm = false
    @State private var showingWaterReminderForm = false
    @State private var shortcutTemplate: SystemShortcutTemplate?
    @State private var pendingLockTestID: UUID?
    @State private var editingPreset: InputPreset?

    private var registeredTargets: [HostActionTarget] {
        model.hostActions.filter(matches)
    }

    private var mappableTargets: [HostActionTarget] {
        guard filter != .unavailable else { return [] }
        return registeredTargets.filter(DeviceActionEligibility.isMappable)
    }

    private var unavailableTargets: [HostActionTarget] {
        guard filter != .mappable else { return [] }
        return registeredTargets.filter { !DeviceActionEligibility.isMappable($0) }
    }

    private var fixedTextPresets: [InputPreset] {
        guard filter != .unavailable else { return [] }
        return model.inputPresets.filter { $0.kind == .fixedText && matches($0) }
    }

    private var keyChordPresets: [InputPreset] {
        guard filter != .unavailable else { return [] }
        return model.inputPresets.filter { $0.kind == .keyChord && matches($0) }
    }

    private var unavailableCapabilities: [DeviceCapability] {
        guard filter != .mappable else { return [] }
        return DeviceCapability.unavailable.filter(matches)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if filter != .unavailable {
                Section("设备映射") {
                    DeviceInputSummaryRow()
                }

                Section("设备语义动作") {
                    ForEach(SemanticAction.allCases.filter(matches)) { action in
                        SemanticActionRow(
                            action: action,
                            isAvailable: model.deviceDetails.supports(action)
                        )
                    }
                }
            }

            if filter != .unavailable {
                Section("文本处理") {
                    ForEach(InputPresetTemplate.allCases) { template in
                        InputPresetTemplateRow(
                            template: template,
                            isRegistered: model.inputPresets.contains {
                                $0.kind == .keyChord && $0.value == template.chord
                            },
                            register: { model.addInputPresetTemplate(template) }
                        )
                    }
                    presetRows(
                        fixedTextPresets,
                        emptyTitle: isSearching ? "没有匹配的文本预设" : "还没有固定文本预设"
                    )
                }

                Section("输入预设") {
                    presetRows(
                        keyChordPresets,
                        emptyTitle: isSearching ? "没有匹配的组合键预设" : "还没有组合键预设"
                    )
                }

                ForEach(ActionLibraryCategory.allCases) { category in
                    let targets = mappableTargets.filter(category.includes)
                    Section(category.title) {
                        hostActionRows(
                            targets,
                            emptyTitle: isSearching ? "没有匹配的\(category.title)" : "还没有已登记的\(category.title)"
                        )
                    }
                }
            }

            if filter != .mappable {
                Section("设备灯效与音频联动") {
                    if unavailableCapabilities.isEmpty && unavailableTargets.isEmpty {
                        emptyRow(title: "没有匹配的未接入能力", symbol: "magnifyingglass")
                    } else {
                        ForEach(unavailableCapabilities) { capability in
                            UnavailableCapabilityRow(capability: capability)
                        }
                        ForEach(unavailableTargets) { target in
                            HostActionRow(
                                target: target,
                                test: {},
                                remove: { model.removeHostAction(target.id) },
                                statusChips: DeviceActionEligibility.chips(for: target),
                                allowsTesting: false
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("动作库")
        .onAppear {
#if DEBUG
            if let debugSearchText = model.debugActionLibrarySearchText {
                searchText = debugSearchText
            }
#endif
        }
        .searchable(text: $searchText, prompt: "搜索动作或预设")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("显示", selection: $filter) {
                    ForEach(ActionLibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("本机动作") {
                        Button("从本机应用登记", systemImage: "square.grid.2x2") {
                            showingApplicationPicker = true
                        }
                        Button("手动选择应用", systemImage: "folder") {
                            model.chooseApplicationAction()
                        }
                        Button("登记网址", systemImage: "link") {
                            showingURLForm = true
                        }
                        Button("登记快捷指令", systemImage: "command") {
                            shortcutTemplate = nil
                            showingShortcutForm = true
                        }
                    }

                    Section("系统工具") {
                        ForEach(SystemTool.builtIn) { tool in
                            Button(tool.title, systemImage: tool.symbol) {
                                if tool == .waterReminder {
                                    showingWaterReminderForm = true
                                } else {
                                    model.addSystemTool(tool)
                                }
                            }
                        }
                    }

                    Section("快捷指令或脚本集成") {
                        Button("选择授权脚本", systemImage: "doc.badge.gearshape") {
                            model.chooseScriptAction()
                        }
                        ForEach(SystemShortcutTemplate.all) { template in
                            Button(template.title, systemImage: template.symbol) {
                                shortcutTemplate = template
                                showingShortcutForm = true
                            }
                        }
                    }

                    Section("输入预设") {
                        Button("新建固定文本", systemImage: "text.cursor") {
                            showingFixedTextPresetForm = true
                        }
                        Button("录制键盘组合键", systemImage: "keyboard") {
                            showingKeyChordPresetForm = true
                        }
                    }
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .disabled(!model.isLocalStateReady)
            }
        }
        .sheet(isPresented: $showingApplicationPicker) {
            InstalledApplicationPicker(model: model)
        }
        .sheet(isPresented: $showingURLForm) {
            URLActionForm { title, url in
                model.addURLAction(title: title, url: url)
            }
        }
        .sheet(isPresented: $showingShortcutForm, onDismiss: { shortcutTemplate = nil }) {
            ShortcutActionForm(initialTitle: shortcutTemplate?.title ?? "") { title, shortcutName in
                model.addShortcutAction(title: title, shortcutName: shortcutName)
            }
        }
        .sheet(isPresented: $showingFixedTextPresetForm) {
            FixedTextPresetForm { title, value in
                model.saveInputPreset(kind: .fixedText, title: title, value: value)
            }
        }
        .sheet(isPresented: $showingKeyChordPresetForm) {
            KeyChordPresetForm { title, value in
                model.saveInputPreset(kind: .keyChord, title: title, value: value)
            }
        }
        .sheet(isPresented: $showingWaterReminderForm) {
            WaterReminderForm { minutes in
                model.addWaterReminderAction(minutes: minutes)
            }
        }
        .sheet(item: $editingPreset) { preset in
            switch preset.kind {
            case .fixedText:
                FixedTextPresetForm(preset: preset) { title, value in
                    model.saveInputPreset(id: preset.id, kind: .fixedText, title: title, value: value)
                }
            case .keyChord:
                KeyChordPresetForm(preset: preset) { title, value in
                    model.saveInputPreset(id: preset.id, kind: .keyChord, title: title, value: value)
                }
            }
        }
        .confirmationDialog(
            "确认测试锁定屏幕",
            isPresented: Binding(
                get: { pendingLockTestID != nil },
                set: { if !$0 { pendingLockTestID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("锁定屏幕", role: .destructive) {
                if let pendingLockTestID {
                    model.testHostAction(pendingLockTestID)
                }
                pendingLockTestID = nil
            }
            Button("取消", role: .cancel) {
                pendingLockTestID = nil
            }
        } message: {
            Text("此操作会立即锁定当前 Mac。")
        }
        .disabled(!model.isLocalStateReady)
    }

    @ViewBuilder
    private func emptyRow(title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func hostActionRows(_ targets: [HostActionTarget], emptyTitle: String) -> some View {
        if targets.isEmpty {
            emptyRow(title: emptyTitle, symbol: isSearching ? "magnifyingglass" : "plus.circle")
        } else {
            ForEach(targets) { target in
                HostActionRow(
                    target: target,
                    test: { test(target) },
                    remove: { model.removeHostAction(target.id) },
                    statusChips: DeviceActionEligibility.chips(for: target)
                )
            }
        }
    }

    @ViewBuilder
    private func presetRows(_ presets: [InputPreset], emptyTitle: String) -> some View {
        if presets.isEmpty {
            emptyRow(title: emptyTitle, symbol: isSearching ? "magnifyingglass" : "plus.circle")
        } else {
            ForEach(presets) { preset in
                InputPresetRow(
                    preset: preset,
                    edit: { editingPreset = preset },
                    remove: { model.removeInputPreset(preset.id) }
                )
            }
        }
    }

    private func matches(_ target: HostActionTarget) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return target.title.localizedCaseInsensitiveContains(query)
            || HostActionPresentation.kindTitle(target.kind).localizedCaseInsensitiveContains(query)
    }

    private func matches(_ preset: InputPreset) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return preset.title.localizedCaseInsensitiveContains(query)
            || preset.kind.title.localizedCaseInsensitiveContains(query)
    }

    private func matches(_ capability: DeviceCapability) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return capability.title.localizedCaseInsensitiveContains(query)
            || capability.detail.localizedCaseInsensitiveContains(query)
    }

    private func matches(_ action: SemanticAction) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return action.title.localizedCaseInsensitiveContains(query)
            || action.rawValue.localizedCaseInsensitiveContains(query)
    }

    private func test(_ target: HostActionTarget) {
        if target.kind == .system, target.payload == SystemTool.lockScreen.rawValue {
            pendingLockTestID = target.id
        } else {
            model.testHostAction(target.id)
        }
    }
}

private struct DeviceInputSummaryRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("8 键与旋钮")
                Text("键位、旋钮左转、按下和右转可绑定 Mac 动作或输入预设。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            ActionStatusChips(chips: [
                .init(title: "可映射", tone: .ready),
                .init(title: "设备输入", tone: .neutral)
            ])
        }
        .padding(.vertical, 3)
    }
}

private struct SemanticActionRow: View {
    let action: SemanticAction
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                Text("由设备协议定义，可直接映射到按键或旋钮。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("适用：\(controlHint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            ActionStatusChips(chips: [
                .init(title: isAvailable ? "可映射" : "设备未确认", tone: isAvailable ? .ready : .attention),
                .init(title: "设备执行", tone: .neutral),
                .init(title: isAvailable ? "可用" : "待读取", tone: isAvailable ? .neutral : .attention)
            ])
        }
        .padding(.vertical, 3)
    }

    private var controlHint: String {
        if action.recommendedControls == Set(ControlID.keys) {
            return "按键"
        }
        return "按键或旋钮按下"
    }
}

private struct UnavailableCapabilityRow: View {
    let capability: DeviceCapability

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: capability.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title)
                Text(capability.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            ActionStatusChips(chips: [
                .init(title: "不可映射", tone: .unavailable),
                .init(title: "未接入", tone: .unavailable)
            ])
        }
        .padding(.vertical, 3)
    }
}

private struct HostActionRow: View {
    let target: HostActionTarget
    let test: () -> Void
    let remove: () -> Void
    let statusChips: [ActionStatusChip]
    var allowsTesting = true
    @State private var applicationIcon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            HostActionIcon(target: target, applicationIcon: applicationIcon)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(HostActionPresentation.kindTitle(target.kind))
                    ActionStatusChips(chips: statusChips)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(DeviceActionEligibility.controlHint(for: target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if allowsTesting {
                Button(action: test) {
                    Image(systemName: "play")
                }
                .buttonStyle(.borderless)
                .help("测试动作")
                .accessibilityLabel("测试 \(target.title)")
            }

            Menu {
                if allowsTesting {
                    Button("测试动作", systemImage: "play", action: test)
                    Divider()
                }
                Button("移除", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("更多操作")
        }
        .padding(.vertical, 3)
        .onAppear {
            applicationIcon = HostActionPresentation.applicationIcon(for: target)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HostActionIcon: View {
    let target: HostActionTarget
    let applicationIcon: NSImage?

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: HostActionPresentation.symbol(for: target))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct InputPresetRow: View {
    let preset: InputPreset
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.kind == .fixedText ? "text.cursor" : "keyboard")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(preset.kind.title)
                    ActionStatusChips(chips: [
                        .init(title: "可映射", tone: .ready),
                        .init(title: "已保存", tone: .neutral)
                    ])
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(preset.value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(preset.value)

            Menu {
                Button("编辑", systemImage: "pencil", action: edit)
                Divider()
                Button("移除", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("更多操作")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}

private struct ActionStatusChips: View {
    let chips: [ActionStatusChip]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(chips) { chip in
                Text(chip.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(backgroundColor(for: chip.tone), in: Capsule())
                    .foregroundStyle(foregroundColor(for: chip.tone))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func foregroundColor(for tone: ActionStatusChip.Tone) -> Color {
        switch tone {
        case .ready: .green
        case .neutral: .secondary
        case .attention: .orange
        case .unavailable: .secondary
        }
    }

    private func backgroundColor(for tone: ActionStatusChip.Tone) -> Color {
        switch tone {
        case .ready: .green.opacity(0.12)
        case .neutral: .secondary.opacity(0.12)
        case .attention: .orange.opacity(0.12)
        case .unavailable: .secondary.opacity(0.08)
        }
    }
}

private struct InstalledApplicationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    private var applications: [InstalledApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.installedApplications }
        return model.installedApplications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(applications) { application in
                Button {
                    model.registerInstalledApplication(application)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(application.name)
                                .lineLimit(1)
                            Text(application.source.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if model.isApplicationCatalogLoading {
                    ProgressView()
                } else if applications.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "没有找到应用" : "没有匹配的应用",
                        systemImage: "app.dashed"
                    )
                }
            }
            .navigationTitle("选择本机应用")
            .searchable(text: $searchText, prompt: "搜索应用")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem {
                    Button {
                        model.refreshInstalledApplications()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重新读取应用")
                    .disabled(model.isApplicationCatalogLoading)
                }
            }
            .task {
                if model.installedApplications.isEmpty {
                    model.refreshInstalledApplications()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct URLActionForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = "https://"
    let save: (String, String) -> Void

    var body: some View {
        Form {
            TextField("名称", text: $title)
            TextField("网址", text: $url)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("登记") {
                    save(title.isEmpty ? url : title, url)
                    dismiss()
                }
                .disabled(url == "https://")
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct ShortcutActionForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var shortcutName = ""
    let save: (String, String) -> Void

    init(initialTitle: String, save: @escaping (String, String) -> Void) {
        _title = State(initialValue: initialTitle)
        self.save = save
    }

    var body: some View {
        Form {
            TextField("显示名称", text: $title)
            TextField("快捷指令名称", text: $shortcutName)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("登记") {
                    save(title.isEmpty ? shortcutName : title, shortcutName)
                    dismiss()
                }
                .disabled(shortcutName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct FixedTextPresetForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    let save: (String, String) -> Void

    init(preset: InputPreset? = nil, save: @escaping (String, String) -> Void) {
        _title = State(initialValue: preset?.title ?? "")
        _value = State(initialValue: preset?.value ?? "")
        self.save = save
    }

    var body: some View {
        Form {
            TextField("显示名称", text: $title)
            TextEditor(text: $value)
                .font(.body)
                .frame(minHeight: 100)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    save(title, value)
                    dismiss()
                }
                .disabled(value.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct KeyChordPresetForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    @State private var isRecording = false
    @State private var recordingError: String?
    let save: (String, String) -> Void

    init(preset: InputPreset? = nil, save: @escaping (String, String) -> Void) {
        _title = State(initialValue: preset?.title ?? "")
        _value = State(initialValue: preset?.value ?? "")
        self.save = save
    }

    var body: some View {
        Form {
            TextField("显示名称", text: $title)

            LabeledContent("组合键") {
                Text(value.isEmpty ? "未录制" : value)
                    .font(.body.monospaced())
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
            }

            HStack {
                Button(isRecording ? "请按组合键…" : "开始录制", systemImage: "keyboard") {
                    recordingError = nil
                    isRecording = true
                }
                .disabled(isRecording)

                if let recordingError {
                    Text(recordingError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("录制后自动采用设备兼容格式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    save(title, value)
                    dismiss()
                }
                .disabled(value.isEmpty || isRecording)
            }
        }
        .background(
            KeyChordRecorder(isRecording: $isRecording) { result in
                switch result {
                case .success(let chord):
                    value = chord
                    recordingError = nil
                case .failure(let error):
                    recordingError = error.message
                }
            }
            .frame(width: 1, height: 1)
        )
        .padding(24)
        .frame(width: 440)
    }
}
