import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    PreferenceToggleRow(
                        title: "在菜单栏显示",
                        detail: "关闭后仍可通过 Dock 打开 EasyMacBord。",
                        isOn: preferences.menuBarVisibility
                    )
                    Divider()
                    PreferenceToggleRow(
                        title: "登录时启动",
                        detail: preferences.loginItemStatus.detail,
                        isOn: Binding(
                            get: { preferences.isLaunchAtLoginRequested },
                            set: { preferences.setLaunchAtLogin($0) }
                        )
                    )
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                if let message = preferences.loginItemMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(28)
        }
        .navigationTitle("设置")
        .onAppear { preferences.refreshLoginItemStatus() }
    }
}

struct AboutView: View {
    let buildInfo: AppBuildInfo

    init(buildInfo: AppBuildInfo = AppBuildInfo()) {
        self.buildInfo = buildInfo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                BrandMark.image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("EasyMacBord")
                        .font(.title2.weight(.semibold))
                    Text("日常效率工具")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                AboutDetailRow(title: "版本", value: buildInfo.version)
                Divider()
                AboutDetailRow(title: "构建", value: buildInfo.build)
                Divider()
                AboutDetailRow(title: "架构", value: buildInfo.architecture)
                Divider()
                AboutDetailRow(title: "签名", value: buildInfo.signingSummary)
                Divider()
                AboutDetailRow(title: "最低系统", value: "macOS 26")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("关于")
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .padding(18)
    }
}

private struct AboutDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .padding(18)
    }
}
