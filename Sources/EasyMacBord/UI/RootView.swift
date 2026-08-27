import AppKit
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case profiles
    case actions
    case device
    case permissions
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "状态总览"
        case .profiles: "配置档"
        case .actions: "动作库"
        case .device: "设备与同步"
        case .permissions: "权限"
        case .settings: "设置"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .profiles: "rectangle.3.group"
        case .actions: "bolt"
        case .device: "keyboard"
        case .permissions: "checklist"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        SidebarBrandHeader(connection: model.connection)
                            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 10))
                            .listRowBackground(Color.clear)
                            .accessibilityElement(children: .combine)
                    }

                    Section {
                        ForEach([AppSection.overview, .profiles, .actions, .device, .permissions]) { section in
                            Label(section.title, systemImage: section.symbol)
                                .tag(section)
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                List(selection: $selection) {
                    ForEach([AppSection.settings, .about]) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .frame(height: 88)
            }
            .navigationTitle("EasyMacBord")
            .navigationSplitViewColumnWidth(min: 216, ideal: 232, max: 280)
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
            case .settings:
                PreferencesView(preferences: preferences, model: model)
            case .about:
                AboutView()
            }
        }
        .overlay {
            if model.isScreenCleanerPresented {
                ScreenCleanerOverlay(close: model.closeScreenCleaner)
            }
        }
        .confirmationDialog(
            "确认清空废纸篓",
            isPresented: Binding(
                get: { model.pendingDestructiveAction != nil },
                set: { if !$0 { model.cancelPendingDestructiveAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button("清空废纸篓", role: .destructive) {
                model.confirmPendingDestructiveAction()
            }
            Button("取消", role: .cancel) {
                model.cancelPendingDestructiveAction()
            }
        } message: {
            Text("此操作会删除废纸篓中的项目，无法撤销。")
        }
    }
}

private struct ScreenCleanerOverlay: View {
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()
            Button("关闭", action: close)
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: close)
        .accessibilityLabel("清洁屏幕遮罩")
    }
}

private struct SidebarBrandHeader: View {
    let connection: DeviceConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BrandMark.image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EasyMacBord")
                        .font(.headline)
                    Text("日常效率工具")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                Text(connection.name)
                    .font(.caption)
                    .lineLimit(1)
                    .help(connection.name)
                Spacer(minLength: 0)
                Text(statusTitle)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        switch connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找"
        case .disconnected: "未连接"
        case .unavailable: "不可用"
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
                MainWindowCoordinator.shared.showMainWindow()
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
