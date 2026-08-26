import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var model: AppModel
    @State private var selectedControl: ControlID = .key1

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $model.selectedProfileID) {
                ForEach(model.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .frame(width: 184)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.selectedProfile.name).font(.title2.weight(.semibold))
                            Text("设备配置仅在收到保存确认后生效").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("同步", systemImage: "arrow.triangle.2.circlepath") { model.beginSync() }
                    }

                    Text("按键映射").font(.headline)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ControlID.keys) { control in
                            KeyTile(
                                control: control,
                                binding: model.selectedProfile.binding(for: control),
                                isSelected: control == selectedControl
                            ) {
                                selectedControl = control
                            }
                        }
                    }

                    Text("旋钮").font(.headline).padding(.top, 4)
                    HStack(spacing: 10) {
                        ForEach([ControlID.encoderLeft, .encoderRight, .encoderPress]) { control in
                            KeyTile(
                                control: control,
                                binding: model.selectedProfile.binding(for: control),
                                isSelected: control == selectedControl
                            ) {
                                selectedControl = control
                            }
                        }
                    }

                    BindingInspector(
                        control: selectedControl,
                        binding: model.selectedProfile.binding(for: selectedControl),
                        hostActions: model.hostActions,
                        update: { model.setBinding($0, for: selectedControl) }
                    )
                }
                .padding(24)
            }
        }
        .navigationTitle("配置档")
    }
}

struct KeyTile: View {
    let control: ControlID
    let binding: ActionBinding
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Text(control.title).font(.headline)
                Text(binding.title)
                    .lineLimit(1)
                    .foregroundStyle(binding.kind == .disabled ? .secondary : .primary)
                Text(binding.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(control.title)，\(binding.title)")
    }
}

struct BindingInspector: View {
    let control: ControlID
    let binding: ActionBinding
    let hostActions: [HostActionTarget]
    let update: (ActionBinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(control.title) 设置").font(.headline)
            Picker("动作类型", selection: kindBinding) {
                ForEach(BindingKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            if binding.kind == .hostAction {
                Picker("本机动作", selection: valueBinding) {
                    Text("请选择").tag("")
                    ForEach(hostActions) { target in
                        Text(target.title).tag(target.id.uuidString.lowercased())
                    }
                }
            } else {
                TextField(valueLabel, text: valueBinding)
                    .disabled(binding.kind == .disabled)
            }
            TextField("显示名称", text: titleBinding)
                .disabled(binding.kind == .disabled)
            if binding.kind == .hostAction {
                Text(hostActions.isEmpty ? "请先在“本机动作”中登记动作。应用路径不会写入设备。" : "设备仅保存所选动作的小写 UUID，不保存应用路径。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    }

    private var valueLabel: String {
        switch binding.kind {
        case .hostAction: "动作 UUID"
        case .fixedText: "文本内容"
        case .keyChord: "组合键，例如 Meta+Space"
        case .disabled: "无内容"
        }
    }

    private var kindBinding: Binding<BindingKind> {
        Binding(
            get: { binding.kind },
            set: { kind in
                var next = binding
                next.kind = kind
                if kind == .disabled {
                    next.value = ""
                    next.title = "未设置"
                }
                update(next)
            }
        )
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { binding.value },
            set: { value in
                var next = binding
                next.value = value
                if binding.kind == .hostAction,
                   let target = hostActions.first(where: { $0.id.uuidString.lowercased() == value }) {
                    next.title = target.title
                }
                update(next)
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { binding.title },
            set: { value in
                var next = binding
                next.title = value
                update(next)
            }
        )
    }
}
