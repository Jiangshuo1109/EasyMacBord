import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("按需授权") {
                ForEach(PermissionKind.allCases) { permission in
                    LabeledContent(permission.title) {
                        Text(model.permissions.state(for: permission).title)
                            .foregroundStyle(color(for: model.permissions.state(for: permission)))
                    }
                }
            }
            Section {
                Button("重新检查") { model.permissions.refresh() }
            }
            Section("使用边界") {
                Text("固定文本和键盘组合键由设备执行。本机动作只在 UUID 映射存在且相关权限满足时执行。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("权限")
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted: .green
        case .required: .orange
        case .notChecked: .secondary
        }
    }
}
