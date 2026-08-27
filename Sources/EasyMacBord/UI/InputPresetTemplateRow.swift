import SwiftUI

struct InputPresetTemplateRow: View {
    let template: InputPresetTemplate
    let isRegistered: Bool
    let register: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                Text(template.chord)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isRegistered ? "已添加" : "添加") {
                register()
            }
            .buttonStyle(.bordered)
            .disabled(isRegistered)
        }
        .padding(.vertical, 3)
    }
}

struct WaterReminderForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30
    let save: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("喝水提醒")
                .font(.headline)
            Stepper("每 \(minutes) 分钟提醒一次", value: $minutes, in: 1...1_440, step: 5)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("登记动作") {
                    save(minutes)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
