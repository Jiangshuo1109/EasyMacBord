import SwiftUI

struct DeviceSyncView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("设备") {
                LabeledContent("设备名称", value: model.connection.name)
                LabeledContent("连接状态", value: connectionTitle)
                LabeledContent("活动事件通道", value: eventChannel)
            }
            Section("同步") {
                LabeledContent("当前配置档", value: model.selectedProfile.name)
                LabeledContent("状态", value: model.syncState.title)
                Button("同步当前配置", systemImage: "arrow.triangle.2.circlepath") { model.beginSync() }
            }
            Section("确认条件") {
                Text("只有设备回传 phase=1、ok=true、saved=true，且长度和 CRC 与本次配置一致时，界面才显示“已确认”。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle("设备与同步")
    }

    private var connectionTitle: String {
        switch model.connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找"
        case .disconnected: "未连接"
        case .unavailable(let reason): reason
        }
    }

    private var eventChannel: String {
        if case .connected(let channel) = model.connection.state { return channel.title }
        return "无"
    }
}
