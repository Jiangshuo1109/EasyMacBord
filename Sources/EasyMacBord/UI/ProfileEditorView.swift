import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var model: AppModel
    @State private var selectedControl: ControlID = .key1

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 10) {
                        Picker("当前配置档", selection: $model.selectedProfileID) {
                            ForEach(model.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .help(model.selectedProfile.name)

                        Button {
                            model.addProfile()
                        } label: {
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
                        .disabled(!canSync)
                    }

                    Text("本地保存不等于设备已确认保存")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    MacroPadSurface(
                        profile: model.selectedProfile,
                        hostActions: model.hostActions,
                        selectedControl: selectedControl,
                        select: { selectedControl = $0 }
                    )
                    .frame(maxWidth: 760)

                    HStack(spacing: 6) {
                        Image(systemName: saveSymbol)
                            .foregroundStyle(saveColor)
                        Text(model.profileSaveState.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

private struct MacroPadSurface: View {
    let profile: Profile
    let hostActions: [HostActionTarget]
    let selectedControl: ControlID
    let select: (ControlID) -> Void

    private let keyColumns = Array(repeating: GridItem(.flexible(minimum: 86, maximum: 132), spacing: 10), count: 4)

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("8 键宏键盘")
                    .font(.headline)

                LazyVGrid(columns: keyColumns, spacing: 10) {
                    ForEach(ControlID.keys) { control in
                        MacroKeyCap(
                            control: control,
                            binding: profile.binding(for: control),
                            target: hostAction(for: profile.binding(for: control)),
                            isSelected: control == selectedControl,
                            select: { select(control) }
                        )
                    }
                }
            }

            Divider()

            RotaryControl(
                profile: profile,
                hostActions: hostActions,
                selectedControl: selectedControl,
                select: select
            )
            .frame(width: 178)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func hostAction(for binding: ActionBinding) -> HostActionTarget? {
        guard binding.kind == .hostAction,
              let id = UUID(uuidString: binding.value) else { return nil }
        return hostActions.first { $0.id == id }
    }
}

private struct MacroKeyCap: View {
    let control: ControlID
    let binding: ActionBinding
    let target: HostActionTarget?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(control.rawValue.replacingOccurrences(of: "KEY", with: "K"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    actionIcon
                }

                Spacer(minLength: 0)

                Text(binding.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(binding.kind == .disabled ? .secondary : .primary)
                    .help(binding.title)

                Text(binding.kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
            .background(keyBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(control.title)，\(binding.title)，\(binding.kind.title)")
    }

    @ViewBuilder
    private var actionIcon: some View {
        if let target, let icon = HostActionPresentation.applicationIcon(for: target) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            Image(systemName: target.map(HostActionPresentation.symbol(for:)) ?? bindingSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }

    private var keyBackground: Color {
        isSelected ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    private var bindingSymbol: String {
        switch binding.kind {
        case .hostAction: "bolt"
        case .fixedText: "text.cursor"
        case .keyChord: "command"
        case .disabled: "minus"
        }
    }
}

private struct RotaryControl: View {
    let profile: Profile
    let hostActions: [HostActionTarget]
    let selectedControl: ControlID
    let select: (ControlID) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("旋钮")
                .font(.headline)

            Button {
                select(.encoderPress)
            } label: {
                ZStack {
                    Circle()
                        .fill(selectedControl == .encoderPress ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.09))
                    Circle()
                        .stroke(selectedControl == .encoderPress ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: selectedControl == .encoderPress ? 2 : 1)
                    Image(systemName: "dial.medium")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 76, height: 76)
            }
            .buttonStyle(.plain)
            .help("旋钮按下")

            VStack(spacing: 6) {
                ForEach([ControlID.encoderLeft, .encoderPress, .encoderRight]) { control in
                    RotaryActionRow(
                        control: control,
                        binding: profile.binding(for: control),
                        target: hostAction(for: profile.binding(for: control)),
                        isSelected: control == selectedControl,
                        select: { select(control) }
                    )
                }
            }
        }
    }

    private func hostAction(for binding: ActionBinding) -> HostActionTarget? {
        guard binding.kind == .hostAction,
              let id = UUID(uuidString: binding.value) else { return nil }
        return hostActions.first { $0.id == id }
    }
}

private struct RotaryActionRow: View {
    let control: ControlID
    let binding: ActionBinding
    let target: HostActionTarget?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                Image(systemName: controlSymbol)
                    .font(.caption)
                    .frame(width: 14)
                Text(binding.title)
                    .font(.caption)
                    .lineLimit(1)
                    .help(binding.title)
                Spacer(minLength: 0)
                if let target, let icon = HostActionPresentation.applicationIcon(for: target) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(control.title)，\(binding.title)")
    }

    private var controlSymbol: String {
        switch control {
        case .encoderLeft: "arrow.counterclockwise"
        case .encoderPress: "circle.fill"
        case .encoderRight: "arrow.clockwise"
        default: "circle"
        }
    }
}

private struct BindingInspector: View {
    @ObservedObject var model: AppModel
    let control: ControlID

    @State private var isRecordingChord = false
    @State private var recordingMessage: String?
    @State private var pendingLockTestID: UUID?

    private var binding: ActionBinding {
        model.selectedProfile.binding(for: control)
    }

    private var selectedTarget: HostActionTarget? {
        guard let id = UUID(uuidString: binding.value) else { return nil }
        return model.hostActions.first { $0.id == id }
    }

    private var matchingPresets: [InputPreset] {
        let kind: InputPreset.Kind = binding.kind == .fixedText ? .fixedText : .keyChord
        return model.inputPresets.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(control.title) 设置")
                .font(.headline)

            Picker("动作类型", selection: kindBinding) {
                ForEach(BindingKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch binding.kind {
            case .hostAction:
                hostActionSettings
            case .fixedText, .keyChord:
                presetSettings
            case .disabled:
                Text("此控制件不会发送动作。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(.thinMaterial)
        .confirmationDialog(
            "确认测试锁定屏幕",
            isPresented: Binding(
                get: { pendingLockTestID != nil },
                set: { if !$0 { pendingLockTestID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("锁定屏幕", role: .destructive) {
                if let pendingLockTestID {
                    model.testHostAction(pendingLockTestID)
                }
                pendingLockTestID = nil
            }
            Button("取消", role: .cancel) {
                pendingLockTestID = nil
            }
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

            Text("在左侧“动作库”登记、测试和维护本机动作。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selectedTarget {
                Button("测试动作", systemImage: "play.circle") {
                    test(selectedTarget)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func test(_ target: HostActionTarget) {
        if target.kind == .system, target.payload == SystemTool.lockScreen.rawValue {
            pendingLockTestID = target.id
        } else {
            model.testHostAction(target.id)
        }
    }

    @ViewBuilder
    private var presetSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(binding.kind == .fixedText ? "固定文本预设" : "组合键预设")
                .font(.subheadline.weight(.medium))

            if matchingPresets.isEmpty {
                Text("请先在“动作库”创建可复用预设。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matchingPresets) { preset in
                    Button {
                        model.applyInputPreset(preset, to: control)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.kind == .fixedText ? "text.cursor" : "command")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title).lineLimit(1)
                                Text(preset.value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if preset.value == binding.value {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
                }
            }

            if binding.kind == .keyChord {
                Button(isRecordingChord ? "正在录制…" : "录制并保存为预设", systemImage: "record.circle") {
                    recordingMessage = nil
                    isRecordingChord = true
                }
                .buttonStyle(.bordered)
                .disabled(isRecordingChord)

                KeyChordRecorder(isRecording: $isRecordingChord) { result in
                    switch result {
                    case .success(let chord):
                        if let preset = model.saveInputPreset(kind: .keyChord, title: chord, value: chord) {
                            model.applyInputPreset(preset, to: control)
                        }
                    case .failure(let error):
                        recordingMessage = error.message
                    }
                }
                .frame(width: 1, height: 1)

                if let recordingMessage {
                    Text(recordingMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
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
                if let target = model.hostActions.first(where: { $0.id.uuidString.lowercased() == value }) {
                    next.title = target.title
                }
                model.setBinding(next, for: control)
            }
        )
    }
}
