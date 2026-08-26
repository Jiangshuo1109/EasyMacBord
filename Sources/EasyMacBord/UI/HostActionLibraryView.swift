import AppKit
import SwiftUI

struct HostActionLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var showingApplicationPicker = false
    @State private var showingURLForm = false
    @State private var showingShortcutForm = false
    @State private var shortcutTemplate: SystemShortcutTemplate?

    var body: some View {
        List {
            Section("添加动作") {
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

            Section("已登记的动作") {
                if model.hostActions.isEmpty {
                    ContentUnavailableView("没有本机动作", systemImage: "bolt.slash")
                } else {
                    ForEach(model.hostActions) { target in
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: target))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(target.title)
                                    .lineLimit(1)
                                Text(kindTitle(target.kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                model.testHostAction(target.id)
                            } label: {
                                Image(systemName: "play")
                            }
                            .buttonStyle(.borderless)
                            .help("测试动作")
                        }
                        .contextMenu {
                            Button("移除", role: .destructive) {
                                model.removeHostAction(target.id)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.removeHostAction(model.hostActions[index].id)
                        }
                    }
                }
            }
        }
        .navigationTitle("管理本机动作")
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
    }

    private func symbol(for target: HostActionTarget) -> String {
        if target.kind == .system, let tool = SystemTool(rawValue: target.payload) {
            return tool.symbol
        }
        return switch target.kind {
        case .application: "app"
        case .url: "link"
        case .shortcut: "command"
        case .system: "gearshape"
        }
    }

    private func kindTitle(_ kind: HostActionTarget.Kind) -> String {
        return switch kind {
        case .application: "应用"
        case .url: "网址"
        case .shortcut: "快捷指令"
        case .system: "系统"
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
