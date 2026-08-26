import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("状态总览").font(.title2.weight(.semibold))
                        Text(model.statusMessage).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SyncBadge(state: model.syncState)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    GlassCard(title: "设备") {
                        StatusLine(label: "名称", value: model.connection.name)
                        StatusLine(label: "连接", value: connectionValue)
                    }
                    GlassCard(title: "当前配置档") {
                        StatusLine(label: "名称", value: model.selectedProfile.name)
                        StatusLine(label: "映射", value: "\(configuredBindingCount) 项")
                    }
                    GlassCard(title: "同步") {
                        StatusLine(label: "状态", value: model.syncState.title)
                        Button("同步当前配置", systemImage: "arrow.triangle.2.circlepath") { model.beginSync() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    GlassCard(title: "权限") {
                        StatusLine(label: "辅助功能", value: model.permissions.state(for: .accessibility).title)
                        StatusLine(label: "屏幕录制", value: model.permissions.state(for: .screenRecording).title)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("最近执行").font(.headline)
                    if model.recentRecords.isEmpty {
                        ContentUnavailableView("暂无记录", systemImage: "clock", description: Text("连接设备后会显示本机动作结果。"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        ForEach(model.recentRecords) { record in
                            HStack {
                                Image(systemName: resultSymbol(record.result))
                                    .foregroundStyle(resultColor(record.result))
                                Text(record.actionTitle)
                                Spacer()
                                Text(record.timestamp, style: .time)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("状态总览")
    }

    private var connectionValue: String {
        switch model.connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找"
        case .disconnected: "未连接"
        case .unavailable(let reason): reason
        }
    }

    private var configuredBindingCount: Int {
        model.selectedProfile.bindings.values.filter { $0.kind != .disabled }.count
    }

    private func resultSymbol(_ result: ExecutionRecord.ResultState) -> String {
        switch result {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func resultColor(_ result: ExecutionRecord.ResultState) -> Color {
        switch result {
        case .success: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

struct GlassCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }
}

struct StatusLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct SyncBadge: View {
    let state: SyncState

    var body: some View {
        Label(state.title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var symbol: String {
        switch state {
        case .idle: "minus.circle"
        case .sending: "arrow.triangle.2.circlepath"
        case .confirmed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch state {
        case .confirmed: .green
        case .failed: .red
        case .sending: .orange
        case .idle: .secondary
        }
    }
}
