import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var model: AppModel

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
                    Divider()
                    PreferenceToggleRow(
                        title: "按前台应用自动切换配置档",
                        detail: "应用切换后会在设备空闲时等待 0.75 秒再同步。",
                        isOn: Binding(
                            get: { model.isAutomaticProfileSwitching },
                            set: { model.setAutomaticProfileSwitching($0) }
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
    @StateObject private var updatePreferences: AppPreferences

    init(buildInfo: AppBuildInfo = AppBuildInfo(), updatePreferences: AppPreferences? = nil) {
        self.buildInfo = buildInfo
        _updatePreferences = StateObject(
            wrappedValue: updatePreferences ?? AppPreferences(buildInfo: buildInfo)
        )
    }

    var body: some View {
        ScrollView {
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

                UpdateCheckCard(
                    state: updatePreferences.updateCheckState,
                    check: { updatePreferences.checkForUpdates() }
                )
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("关于")
    }
}

private struct UpdateCheckCard: View {
    let state: AppUpdateCheckState
    let check: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("更新")
                        .font(.headline)
                    Text("仅检查 GitHub Releases 的公开安装包。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    check()
                } label: {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("检查更新", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isChecking)
            }

            statusContent
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .idle:
            Text("尚未检查更新。")
                .foregroundStyle(.secondary)
        case .checking:
            Text("正在检查 GitHub Releases…")
                .foregroundStyle(.secondary)
        case .completed(.upToDate, let checkedAt):
            updateMessage("当前已是最新可用版本。", checkedAt: checkedAt, symbol: "checkmark.circle.fill", color: .green)
        case .completed(.noUsableRelease, let checkedAt):
            updateMessage("仓库暂未发布适用于当前构建的 arm64 安装包。", checkedAt: checkedAt, symbol: "minus.circle", color: .secondary)
        case .completed(.updateAvailable(let update), let checkedAt):
            availableUpdate(update, checkedAt: checkedAt)
        case .failed(let message, let checkedAt):
            updateMessage(message, checkedAt: checkedAt, symbol: "exclamationmark.circle.fill", color: .orange)
        }
    }

    private func updateMessage(_ message: String, checkedAt: Date, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: symbol)
                .foregroundStyle(color)
            checkedTime(checkedAt)
        }
    }

    private func availableUpdate(_ update: AvailableUpdate, checkedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("发现可用版本 \(update.versionLabel)", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.green)

            if !update.releaseNotes.isEmpty {
                Text(update.releaseNotes)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("此版本未提供发布说明。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Link("下载 arm64 DMG", destination: update.dmgURL)
                    .buttonStyle(.borderedProminent)
                Link("校验文件", destination: update.checksumURL)
                    .buttonStyle(.bordered)
                Link("发布说明", destination: update.releasePageURL)
                    .buttonStyle(.bordered)
            }

            Text("链接会在浏览器中打开；EasyMacBord 不会自动下载或安装更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
            checkedTime(checkedAt)
        }
    }

    private func checkedTime(_ date: Date) -> some View {
        Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var isChecking: Bool {
        if case .checking = state { return true }
        return false
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
