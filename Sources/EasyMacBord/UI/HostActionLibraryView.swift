import SwiftUI

struct HostActionLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var showingURLForm = false
    @State private var showingShortcutForm = false

    var body: some View {
        List {
            Section {
                Button("登记应用", systemImage: "app.badge") {
                    model.chooseApplicationAction()
                }
                Button("登记网址", systemImage: "link") {
                    showingURLForm = true
                }
                Button("登记快捷指令", systemImage: "command") {
                    showingShortcutForm = true
                }
                Button("登记截屏工具", systemImage: "camera") {
                    model.addSystemAction(title: "打开截屏工具", identifier: "screenshot")
                }
                Button("登记锁定屏幕", systemImage: "lock") {
                    model.addSystemAction(title: "锁定屏幕", identifier: "lockScreen")
                }
            }

            Section("已登记的动作") {
                if model.hostActions.isEmpty {
                    ContentUnavailableView("没有本机动作", systemImage: "bolt.slash", description: Text("登记后可在配置档中选择。"))
                } else {
                    ForEach(model.hostActions) { target in
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: target.kind))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(target.title)
                                Text(kindTitle(target.kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
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
        .sheet(isPresented: $showingURLForm) {
            URLActionForm { title, url in
                model.addURLAction(title: title, url: url)
            }
        }
        .sheet(isPresented: $showingShortcutForm) {
            ShortcutActionForm { title, shortcutName in
                model.addShortcutAction(title: title, shortcutName: shortcutName)
            }
        }
    }

    private func symbol(for kind: HostActionTarget.Kind) -> String {
        switch kind {
        case .application: "app"
        case .url: "link"
        case .shortcut: "command"
        case .system: "gearshape"
        }
    }

    private func kindTitle(_ kind: HostActionTarget.Kind) -> String {
        switch kind {
        case .application: "应用"
        case .url: "网址"
        case .shortcut: "快捷指令"
        case .system: "系统"
        }
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
    @State private var title = ""
    @State private var shortcutName = ""
    let save: (String, String) -> Void

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
