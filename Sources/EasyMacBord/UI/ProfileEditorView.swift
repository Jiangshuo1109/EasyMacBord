import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var model: AppModel
    @State private var selectedControl: ControlID = .key1

    private let accent = Color(red: 0.07, green: 0.42, blue: 0.38)
    private let keyColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("配置档")
                            .font(.title2.weight(.semibold))
                        Picker("当前配置档", selection: $model.selectedProfileID) {
                            ForEach(model.profiles) { profile in
                                Text(profile.name)
                                    .tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .help(model.selectedProfile.name)
                        Button(action: model.addProfile) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .help("新建配置档")
                        .accessibilityLabel("新建配置档")
                        Spacer()
                        Button("同步当前配置", systemImage: "arrow.triangle.2.circlepath") {
                            model.beginSync()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .disabled(!canSync)
                    }

                    Text("本地保存不等于设备已确认保存")
                        .foregroundStyle(.secondary)

                    Text("按键映射")
                        .font(.headline)

                    LazyVGrid(columns: keyColumns, spacing: 10) {
                        ForEach(ControlID.keys) { control in
                            MappingTile(
                                control: control,
                                binding: model.selectedProfile.binding(for: control),
                                isSelected: control == selectedControl
                            ) {
                                selectedControl = control
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    Text("单旋钮操作")
                        .font(.headline)
                    HStack(spacing: 10) {
                        ForEach([ControlID.encoderLeft, .encoderPress, .encoderRight]) { control in
                            MappingTile(
                                control: control,
                                binding: model.selectedProfile.binding(for: control),
                                isSelected: control == selectedControl
                            ) {
                                selectedControl = control
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: saveSymbol)
                            .foregroundStyle(saveColor)
                        Text(model.profileSaveState.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)

            Divider()

            BindingInspector(model: model, control: selectedControl)
                .frame(width: 344)
        }
        .navigationTitle("配置档")
        .disabled(!model.isLocalStateReady)
    }

    private var canSync: Bool {
        guard model.isLocalStateReady else { return false }
        if case .connected = model.connection.state { return model.syncState != .sending }
        return false
    }

    private var saveSymbol: String {
        switch model.profileSaveState {
        case .saving: "arrow.triangle.2.circlepath"
        case .saved: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var saveColor: Color {
        switch model.profileSaveState {
        case .saving: .secondary
        case .saved: .green
        case .failed: .red
        }
    }
}

private struct MappingTile: View {
    let control: ControlID
    let binding: ActionBinding
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Text(control.title)
                    .font(.subheadline.weight(.semibold))
                Text(binding.title)
                    .lineLimit(1)
                    .foregroundStyle(binding.kind == .disabled ? .secondary : .primary)
                    .help(binding.title)
                Text(binding.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(control.title)，\(binding.title)，\(binding.kind.title)")
    }
}

private struct BindingInspector: View {
    @ObservedObject var model: AppModel
    let control: ControlID

    @State private var showingActionManager = false
    @State private var showingLockWarning = false

    private var binding: ActionBinding {
        model.selectedProfile.binding(for: control)
    }

    private var selectedTarget: HostActionTarget? {
        guard let id = UUID(uuidString: binding.value) else { return nil }
        return model.hostActions.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(control.title) 设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("动作类型")
                    .font(.subheadline.weight(.medium))
                Picker("动作类型", selection: kindBinding) {
                    ForEach(BindingKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if binding.kind == .hostAction {
                hostActionSettings
            } else {
                standardBindingSettings
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(.thinMaterial)
        .sheet(isPresented: $showingActionManager) {
            NavigationStack {
                HostActionLibraryView(model: model)
            }
            .frame(minWidth: 520, minHeight: 460)
        }
        .confirmationDialog("确认测试锁定屏幕", isPresented: $showingLockWarning, titleVisibility: .visible) {
            Button("锁定屏幕") {
                if let id = selectedTarget?.id {
                    model.testHostAction(id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会立即锁定当前 Mac。")
        }
    }

    @ViewBuilder
    private var hostActionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本机动作")
                .font(.subheadline.weight(.medium))
            Picker("本机动作", selection: valueBinding) {
                Text("请选择").tag("")
                ForEach(model.hostActions) { target in
                    Text(target.title).tag(target.id.uuidString.lowercased())
                }
            }

            Button("管理本机动作", systemImage: "slider.horizontal.3") {
                showingActionManager = true
            }
            .buttonStyle(.bordered)

            if let selectedTarget {
                Button("测试动作", systemImage: "play.circle") {
                    if selectedTarget.kind == .system, selectedTarget.payload == "lockScreen" {
                        showingLockWarning = true
                    } else {
                        model.testHostAction(selectedTarget.id)
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Text("登记并选择本机动作后可测试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var standardBindingSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(valueLabel, text: valueBinding)
                .disabled(binding.kind == .disabled)
            TextField("显示名称", text: titleBinding)
                .disabled(binding.kind == .disabled)
            Text(testHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var valueLabel: String {
        switch binding.kind {
        case .hostAction: "本机动作"
        case .fixedText: "文本内容"
        case .keyChord: "组合键，例如 Meta+Space"
        case .disabled: "无内容"
        }
    }

    private var testHint: String {
        switch binding.kind {
        case .fixedText, .keyChord: "该动作由设备发送，请通过实体控制件验证。"
        case .disabled: "此控制件不会发送动作。"
        case .hostAction: ""
        }
    }

    private var kindBinding: Binding<BindingKind> {
        Binding(
            get: { binding.kind },
            set: { kind in
                var next = binding
                guard next.kind != kind else { return }
                next.kind = kind
                next.value = ""
                next.title = kind == .disabled ? "未设置" : "未命名动作"
                model.setBinding(next, for: control)
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
                   let target = model.hostActions.first(where: { $0.id.uuidString.lowercased() == value }) {
                    next.title = target.title
                }
                model.setBinding(next, for: control)
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { binding.title },
            set: { value in
                var next = binding
                next.title = value
                model.setBinding(next, for: control)
            }
        )
    }
}
