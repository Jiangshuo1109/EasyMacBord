import AppKit
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case profiles
    case actions
    case device
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "状态总览"
        case .profiles: "配置档"
        case .actions: "本机动作"
        case .device: "设备与同步"
        case .permissions: "权限"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .profiles: "rectangle.3.group"
        case .actions: "bolt.circle"
        case .device: "keyboard"
        case .permissions: "checklist"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("EasyMacBord")
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                DashboardView(model: model)
            case .profiles:
                ProfileEditorView(model: model)
            case .actions:
                HostActionLibraryView(model: model)
            case .device:
                DeviceSyncView(model: model)
            case .permissions:
                PermissionsView(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("同步", systemImage: "arrow.triangle.2.circlepath") {
                    model.beginSync()
                }
                .disabled({
                    if case .connected = model.connection.state { return false }
                    return true
                }())
            }
        }
    }
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: connectionSymbol)
                    .foregroundStyle(connectionColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.connection.name).font(.headline)
                    Text(connectionTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Text("当前配置档")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("当前配置档", selection: $model.selectedProfileID) {
                ForEach(model.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()

            Button("打开设置", systemImage: "gearshape") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("退出 EasyMacBord", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
    }

    private var connectionTitle: String {
        switch model.connection.state {
        case .connected(let channel): "已通过 \(channel.title) 连接"
        case .connecting: "正在查找设备"
        case .disconnected: "未连接"
        case .unavailable(let reason): reason
        }
    }

    private var connectionSymbol: String {
        if case .connected = model.connection.state { return "checkmark.circle.fill" }
        return "circle.dashed"
    }

    private var connectionColor: Color {
        if case .connected = model.connection.state { return .green }
        return .secondary
    }
}
