import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel

    private let accent = Color(red: 0.07, green: 0.42, blue: 0.38)
    private let metricColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    private let bindingColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("状态总览")
                            .font(.title2.weight(.semibold))
                        Text(model.statusMessage)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("同步当前配置", systemImage: "arrow.triangle.2.circlepath") {
                        model.beginSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(!canSync)
                }

                LazyVGrid(columns: metricColumns, spacing: 10) {
                    OverviewMetric(
                        title: "设备",
                        value: model.connection.name,
                        detail: connectionTitle,
                        symbol: "keyboard",
                        color: connectionColor
                    )
                    OverviewMetric(
                        title: "当前配置档",
                        value: model.selectedProfile.name,
                        detail: "\(configuredBindingCount) 项映射",
                        symbol: "doc.text",
                        color: accent
                    )
                    OverviewMetric(
                        title: "同步",
                        value: model.syncState.title,
                        detail: syncDetail,
                        symbol: "arrow.triangle.2.circlepath",
                        color: syncColor
                    )
                    OverviewMetric(
                        title: "权限",
                        value: permissionTitle,
                        detail: "辅助功能：\(model.permissions.state(for: .accessibility).title)",
                        symbol: "lock",
                        color: permissionColor
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("控制映射")
                                .font(.headline)
                            Spacer()
                            Text(model.selectedProfile.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: bindingColumns, spacing: 8) {
                            ForEach(ControlID.keys) { control in
                                BindingPreview(
                                    control: control,
                                    binding: model.selectedProfile.binding(for: control)
                                )
                            }
                        }

                        Divider().padding(.vertical, 2)

                        HStack(spacing: 8) {
                            ForEach([ControlID.encoderLeft, .encoderPress, .encoderRight]) { control in
                                BindingPreview(
                                    control: control,
                                    binding: model.selectedProfile.binding(for: control),
                                    compact: true
                                )
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("本机动作记录")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                        }

                        if model.recentRecords.isEmpty {
                            ContentUnavailableView(
                                "暂无记录",
                                systemImage: "clock",
                                description: Text("本机动作触发或手动测试后显示结果。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            ForEach(model.recentRecords) { record in
                                HStack(spacing: 10) {
                                    Image(systemName: resultSymbol(record.result))
                                        .foregroundStyle(resultColor(record.result))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.actionTitle)
                                            .lineLimit(1)
                                        Text(record.source.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(record.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                                if record.id != model.recentRecords.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(18)
                    .frame(width: 316, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(28)
        }
        .navigationTitle("状态总览")
    }

    private var canSync: Bool {
        guard model.isLocalStateReady else { return false }
        if case .connected = model.connection.state { return model.syncState != .sending }
        return false
    }

    private var configuredBindingCount: Int {
        model.selectedProfile.bindings.values.filter { $0.kind != .disabled }.count
    }

    private var connectionTitle: String {
        switch model.connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找设备"
        case .disconnected: "未连接"
        case .unavailable(let reason): reason
        }
    }

    private var connectionColor: Color {
        if case .connected = model.connection.state { return .green }
        return .secondary
    }

    private var syncDetail: String {
        if case .failed(let reason) = model.syncState { return reason }
        if case .confirmed(let date) = model.syncState {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let lastConfirmed = model.syncHistory.lastConfirmedAt {
            return "上次确认 \(lastConfirmed.formatted(date: .omitted, time: .shortened))"
        }
        return model.syncState == .sending ? "等待设备保存确认" : "尚未确认保存"
    }

    private var syncColor: Color {
        switch model.syncState {
        case .confirmed: .green
        case .failed: .red
        case .sending: accent
        case .idle: .secondary
        }
    }

    private var permissionTitle: String {
        let states = PermissionKind.allCases.map { model.permissions.state(for: $0) }
        return states.contains(.required) ? "有待授权项目" : "状态已检查"
    }

    private var permissionColor: Color {
        model.permissions.state(for: .accessibility) == .granted ? .green : .orange
    }

    private func resultSymbol(_ result: ExecutionRecord.ResultState) -> String {
        switch result {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
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

private struct OverviewMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BindingPreview: View {
    let control: ControlID
    let binding: ActionBinding
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            Text(control.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(binding.title)
                .font(compact ? .caption : .subheadline)
                .lineLimit(1)
                .help(binding.title)
            Text(binding.kind.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 60 : 82, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }
}
