import SwiftUI

struct DeviceSyncView: View {
    @ObservedObject var model: AppModel

    private let accent = Color(red: 0.07, green: 0.42, blue: 0.38)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设备与同步")
                            .font(.title2.weight(.semibold))
                        Text("仅展示应用已确认的设备信息")
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

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "keyboard")
                            .font(.title2)
                            .frame(width: 54, height: 54)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.connection.name)
                                .font(.title3.weight(.semibold))
                            Label(connectionTitle, systemImage: connectionSymbol)
                                .foregroundStyle(connectionColor)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 10) {
                        ConnectionChannelRow(
                            title: "USB HID",
                            detail: usbDetail,
                            color: isUSBActive ? .green : .secondary
                        )
                        ConnectionChannelRow(
                            title: "蓝牙配置通道",
                            detail: bluetoothDetail,
                            color: isBluetoothActive ? .green : .secondary
                        )
                    }

                    Divider()

                    HStack(spacing: 0) {
                        DeviceDetailItem(title: "固件版本", value: model.deviceDetails.firmwareVersion.title)
                        DeviceDetailItem(title: "备用通道", value: model.deviceDetails.backupTransport.title)
                        DeviceDetailItem(title: "设备能力", value: model.deviceDetails.capabilities.title)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("同步确认")
                                .font(.headline)
                            Spacer()
                            SyncStatusLabel(state: model.syncState)
                        }

                        LabeledContent("当前配置档", value: model.selectedProfile.name)
                        LabeledContent("上次确认", value: lastConfirmedTitle)

                        if let receipt = model.syncHistory.lastReceipt {
                            Divider()
                            LabeledContent("确认阶段", value: "phase \(receipt.phase)")
                            LabeledContent("保存结果", value: receipt.saved ? "已保存" : "未保存")
                            LabeledContent("配置长度", value: "\(receipt.bytes) 字节")
                            LabeledContent("CRC16", value: String(format: "%04X", receipt.crc16))
                        } else {
                            Text("尚未收到可用于确认保存的设备回执。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("本次状态")
                            .font(.headline)
                        if case .failed(let reason) = model.syncState {
                            Label(reason, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("上次确认的配置不因本次失败而改变。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if model.syncState == .sending {
                            Label("正在等待设备保存确认", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(accent)
                        } else if let failure = model.syncHistory.latestFailure {
                            Label(failure, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else {
                            Label("没有同步错误", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(18)
                    .frame(width: 300, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(28)
        }
        .navigationTitle("设备与同步")
    }

    private var canSync: Bool {
        guard model.isLocalStateReady else { return false }
        if case .connected = model.connection.state { return model.syncState != .sending }
        return false
    }

    private var connectionTitle: String {
        switch model.connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找设备"
        case .disconnected: "未连接"
        case .unavailable(let reason): reason
        }
    }

    private var connectionSymbol: String {
        if case .connected = model.connection.state { return "circle.fill" }
        return "circle.dashed"
    }

    private var connectionColor: Color {
        if case .connected = model.connection.state { return .green }
        return .secondary
    }

    private var isUSBActive: Bool {
        model.connection.state == .connected(.usb)
    }

    private var isBluetoothActive: Bool {
        model.connection.state == .connected(.bluetooth)
    }

    private var usbDetail: String {
        isUSBActive ? "当前活动通道" : "未读取"
    }

    private var bluetoothDetail: String {
        isBluetoothActive ? "当前活动通道" : "未读取"
    }

    private var lastConfirmedTitle: String {
        guard let date = model.syncHistory.lastConfirmedAt else { return "无" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ConnectionChannelRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: title == "USB HID" ? "cable.connector" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(color)
        }
        .padding(13)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct DeviceDetailItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

private struct SyncStatusLabel: View {
    let state: SyncState

    var body: some View {
        Label(state.title, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch state {
        case .idle: "clock"
        case .sending: "arrow.triangle.2.circlepath"
        case .confirmed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .idle: .secondary
        case .sending: .teal
        case .confirmed: .green
        case .failed: .red
        }
    }
}
