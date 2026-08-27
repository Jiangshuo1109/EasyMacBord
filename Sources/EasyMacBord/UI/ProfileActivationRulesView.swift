import AppKit
import SwiftUI

struct ProfileActivationRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let profile: Profile
    @State private var isChoosingApplication = false

    private var rules: [ProfileActivationRule] {
        model.profileActivationRules.filter { $0.profileID == profile.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        "按前台应用自动切换配置档",
                        isOn: Binding(
                            get: { model.isAutomaticProfileSwitching },
                            set: { model.setAutomaticProfileSwitching($0) }
                        )
                    )
                } footer: {
                    Text("应用切换后会先保存本地选择；设备已连接且空闲时，0.75 秒后同步当前配置。")
                }

                Section("当前配置档的匹配应用") {
                    if rules.isEmpty {
                        ContentUnavailableView(
                            "没有匹配规则",
                            systemImage: "rectangle.on.rectangle",
                            description: Text("添加应用后，前台切换到该应用会选中“\(profile.name)”配置档。")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(rules) { rule in
                            HStack(spacing: 12) {
                                Image(systemName: "app")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.applicationName)
                                    Text(rule.applicationBundleID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Toggle(
                                    "启用 \(rule.applicationName)",
                                    isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { model.setProfileActivationRuleEnabled(rule.id, isEnabled: $0) }
                                    )
                                )
                                .labelsHidden()
                            }
                            .contextMenu {
                                Button("移除规则", systemImage: "trash", role: .destructive) {
                                    model.removeProfileActivationRule(rule.id)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                model.removeProfileActivationRule(rules[index].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("自动切换")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("添加应用", systemImage: "plus") {
                        isChoosingApplication = true
                    }
                }
            }
            .sheet(isPresented: $isChoosingApplication) {
                ProfileRuleApplicationPicker(model: model, profile: profile) {
                    isChoosingApplication = false
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
    }
}

private struct ProfileRuleApplicationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let profile: Profile
    let didChoose: () -> Void
    @State private var searchText = ""

    private var applications: [InstalledApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.installedApplications.filter { application in
            guard application.bundleIdentifier != nil else { return false }
            return query.isEmpty
                || application.name.localizedCaseInsensitiveContains(query)
                || application.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        NavigationStack {
            List(applications) { application in
                Button {
                    model.addProfileActivationRule(profileID: profile.id, application: application)
                    didChoose()
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(application.name).lineLimit(1)
                            Text(application.bundleIdentifier ?? "")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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
                        searchText.isEmpty ? "没有可匹配的应用" : "没有匹配的应用",
                        systemImage: searchText.isEmpty ? "app.dashed" : "magnifyingglass"
                    )
                }
            }
            .searchable(text: $searchText, prompt: "搜索应用或 Bundle ID")
            .navigationTitle("选择匹配应用")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        model.refreshInstalledApplications()
                    }
                    .disabled(model.isApplicationCatalogLoading)
                }
            }
            .task {
                if model.installedApplications.isEmpty {
                    model.refreshInstalledApplications()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 500)
    }
}
