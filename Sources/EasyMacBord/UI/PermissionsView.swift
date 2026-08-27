import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("按实际使用结果更新授权状态")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新检查", systemImage: "arrow.clockwise") {
                        model.permissions.refresh()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(spacing: 0) {
                    ForEach(PermissionKind.allCases) { permission in
                        PermissionRow(
                            kind: permission,
                            state: model.permissions.state(for: permission),
                            canOpenSettings: model.permissions.canOpenSettings(for: permission),
                            requestAccessibility: { model.permissions.requestAccessibility() },
                            openSettings: { model.permissions.openSettings(for: permission) }
                        )
                        if permission != PermissionKind.allCases.last {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text("执行边界")
                        .font(.headline)
                    Text("固定文本和键盘组合键由设备执行。本机动作只在本机登记项存在时执行；界面不会将未检查的自动化权限显示为已授权。")
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(28)
        }
        .navigationTitle("权限")
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    let canOpenSettings: Bool
    let requestAccessibility: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(state.title, systemImage: stateSymbol)
                .font(.subheadline)
                .foregroundStyle(stateColor)
            if kind == .accessibility, state != .granted {
                Button("请求权限") {
                    requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
            }
            if canOpenSettings, state != .granted {
                Button("系统设置") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
    }

    private var symbol: String {
        switch kind {
        case .accessibility: "accessibility"
        case .automation: "gearshape"
        case .notifications: "bell"
        }
    }

    private var description: String {
        switch kind {
        case .accessibility: "用于需要系统辅助功能支持的操作。"
        case .automation: "由快捷指令或应用控制操作在实际执行后更新。"
        case .notifications: "喝水提醒在实际执行后请求并更新。"
        }
    }

    private var stateSymbol: String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .required: "exclamationmark.circle.fill"
        case .notChecked: "minus.circle"
        case .actionFailed: "xmark.circle.fill"
        }
    }

    private var stateColor: Color {
        switch state {
        case .granted: .green
        case .required: .orange
        case .notChecked: .secondary
        case .actionFailed: .red
        }
    }
}
