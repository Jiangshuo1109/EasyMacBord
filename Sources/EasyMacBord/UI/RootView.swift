import AppKit
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case profiles
    case device
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "状态总览"
        case .profiles: "配置档"
        case .device: "设备与同步"
        case .permissions: "权限"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .profiles: "rectangle.3.group"
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
            List(selection: $selection) {
                Section {
                    SidebarDeviceSummary(connection: model.connection)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8))
                        .listRowBackground(Color.clear)
                        .accessibilityElement(children: .combine)
                }

                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                }
            }
            .navigationTitle("EasyMacBord")
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .overview {
            case .overview:
                DashboardView(model: model)
            case .profiles:
                ProfileEditorView(model: model)
            case .device:
                DeviceSyncView(model: model)
            case .permissions:
                PermissionsView(model: model)
            }
        }
    }
}

private struct SidebarDeviceSummary: View {
    let connection: DeviceConnection

    var body: some View {
        HStack(spacing: 10) {
            BrandMark.image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusTitle: String {
        switch connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找设备"
        case .disconnected: "未连接"
        case .unavailable(let reason): reason
        }
    }

    private var statusSymbol: String {
        if case .connected = connection.state { return "circle.fill" }
        return "circle.dashed"
    }

    private var statusColor: Color {
        if case .connected = connection.state { return .green }
        return .secondary
    }
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

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
            .disabled(!model.isLocalStateReady)

            Button("打开设置", systemImage: "gearshape") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: AppWindowID.main)
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
