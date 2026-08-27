import AppKit
import SwiftUI

private enum ActionLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case hostActions
    case inputPresets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .hostActions: "本机动作"
        case .inputPresets: "输入预设"
        }
    }
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
    @State private var shortcutTemplate: SystemShortcutTemplate?
    @State private var pendingLockTestID: UUID?
    @State private var editingPreset: InputPreset?

    private var filteredHostActions: [HostActionTarget] {
        guard filter != .inputPresets else { return [] }
        return model.hostActions.filter(matches)
    }

    private var filteredInputPresets: [InputPreset] {
        guard filter != .hostActions else { return [] }
        return model.inputPresets.filter(matches)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if filter != .inputPresets {
                Section("本机动作") {
                    if filteredHostActions.isEmpty {
                        emptyRow(
                            title: isSearching ? "没有匹配的本机动作" : "还没有本机动作",
                            symbol: isSearching ? "magnifyingglass" : "bolt.slash"
                        )
                    } else {
                        ForEach(filteredHostActions) { target in
                            HostActionRow(
                                target: target,
                                test: { test(target) },
                                remove: { model.removeHostAction(target.id) }
                            )
                        }
                    }
                }
            }

            if filter != .hostActions {
                Section("输入预设") {
                    if filteredInputPresets.isEmpty {
                        emptyRow(
                            title: isSearching ? "没有匹配的输入预设" : "还没有输入预设",
                            symbol: isSearching ? "magnifyingglass" : "text.cursor"
                        )
                    } else {
                        ForEach(filteredInputPresets) { preset in
                            InputPresetRow(
                                preset: preset,
                                edit: { editingPreset = preset },
                                remove: { model.removeInputPreset(preset.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("动作库")
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
                                model.addSystemTool(tool)
                            }
                        }
                    }

                    Section("快捷指令模板") {
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

    private func test(_ target: HostActionTarget) {
        if target.kind == .system, target.payload == SystemTool.lockScreen.rawValue {
            pendingLockTestID = target.id
        } else {
            model.testHostAction(target.id)
        }
    }
}

private struct HostActionRow: View {
    let target: HostActionTarget
    let test: () -> Void
    let remove: () -> Void
    @State private var applicationIcon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            HostActionIcon(target: target, applicationIcon: applicationIcon)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
                    .lineLimit(1)
                Text(HostActionPresentation.kindTitle(target.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: test) {
                Image(systemName: "play")
            }
            .buttonStyle(.borderless)
            .help("测试动作")
            .accessibilityLabel("测试 \(target.title)")

            Menu {
                Button("测试动作", systemImage: "play", action: test)
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
                Text(preset.kind.title)
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
