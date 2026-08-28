import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var model: AppModel
    @State private var selectedControl: ControlID = .key1
    @State private var showingActivationRules = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProfileCommandBar(
                        model: model,
                        canSync: canSync,
                        beginSync: model.beginSync,
                        editActivationRules: { showingActivationRules = true }
                    )

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
        .sheet(isPresented: $showingActivationRules) {
            ProfileActivationRulesView(model: model, profile: model.selectedProfile)
        }
    }

    private var canSync: Bool {
        model.isLocalStateReady
            && model.isConfigurationSyncAvailable
            && model.syncState != .sending
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

private struct ProfileCommandBar: View {
    @ObservedObject var model: AppModel
    let canSync: Bool
    let beginSync: () -> Void
    let editActivationRules: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                Button("自动切换", systemImage: "rectangle.on.rectangle") {
                    editActivationRules()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("同步当前配置", systemImage: "arrow.triangle.2.circlepath", action: beginSync)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSync)
            }

            HStack(spacing: 6) {
                ProfileStateChip(title: "当前配置：\(model.selectedProfile.name)", symbol: "rectangle.3.group")
                ProfileStateChip(title: connectionTitle, symbol: connectionSymbol, isReady: isConnected)
                ProfileStateChip(title: "\(model.hostActions.count) 个 Mac 动作", symbol: "macwindow")
                ProfileStateChip(
                    title: model.isAutomaticProfileSwitching ? "自动切换已开启" : "自动切换已关闭",
                    symbol: "rectangle.on.rectangle",
                    isReady: model.isAutomaticProfileSwitching
                )
            }
        }
    }

    private var connectionTitle: String {
        switch model.connection.state {
        case .connected(let channel): "\(channel.title) 已连接"
        case .connecting: "正在查找设备"
        case .disconnected: "设备未连接"
        case .unavailable: "设备不可用"
        }
    }

    private var connectionSymbol: String {
        isConnected ? "circle.fill" : "circle.dashed"
    }

    private var isConnected: Bool {
        if case .connected = model.connection.state { return true }
        return false
    }
}

private struct ProfileStateChip: View {
    let title: String
    let symbol: String
    var isReady = false

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(isReady ? .green : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct MacroPadSurface: View {
    let profile: Profile
    let hostActions: [HostActionTarget]
    let selectedControl: ControlID
    let select: (ControlID) -> Void

    private let keyColumns = Array(repeating: GridItem(.flexible(minimum: 86, maximum: 132), spacing: 10), count: 4)

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EasyInput 控制面板")
                        .font(.headline)
                    Text("8 个按键、1 个旋钮、5 个状态灯位")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BoardIndicatorLights()
            }

            HStack(spacing: 22) {
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

                Divider()

                RotaryControl(
                    profile: profile,
                    hostActions: hostActions,
                    selectedControl: selectedControl,
                    select: select
                )
                .frame(width: 178)
            }
        }
        .padding(18)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.84), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
    }

    private func hostAction(for binding: ActionBinding) -> HostActionTarget? {
        guard binding.kind == .hostAction,
              let id = UUID(uuidString: binding.value) else { return nil }
        return hostActions.first { $0.id == id }
    }
}

private struct BoardIndicatorLights: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.24))
                        .overlay {
                            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                        .frame(width: 9, height: 9)
                        .accessibilityLabel("第 \(index + 1) 个状态灯位未接入")
                }
            }
            Text("LED 未接入")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help("当前设备合同未提供灯效状态或控制。")
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
            .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.04), radius: 2, y: 1)
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
        case .semanticAction: SemanticAction(rawValue: binding.value)?.symbolName ?? "cpu"
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

    private var eligibleHostActions: [HostActionTarget] {
        model.hostActions.filter {
            BoardMappingEligibility.isMappable($0) && BoardMappingEligibility.supports($0, on: control)
        }
    }

    private var eligibleSemanticActions: [SemanticAction] {
        SemanticAction.allCases.filter {
            $0.recommendedControls.contains(control) && model.deviceDetails.supports($0)
        }
    }

    private var matchingPresets: [InputPreset] {
        let kind: InputPreset.Kind = binding.kind == .fixedText ? .fixedText : .keyChord
        return model.inputPresets.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(control.title) 设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("映射类型")
                    .font(.subheadline.weight(.medium))
                Picker("映射类型", selection: kindBinding) {
                    ForEach(BindingKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }

            switch binding.kind {
            case .hostAction:
                hostActionSettings
            case .semanticAction:
                semanticActionSettings
            case .fixedText, .keyChord:
                presetSettings
            case .disabled:
                Text("此控制件不会发送动作。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            UnavailableBoardFeaturesNotice()

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
                ForEach(eligibleHostActions) { target in
                    Text(target.title).tag(target.id.uuidString.lowercased())
                }
            }

            Text("仅显示当前设备可映射的动作；在“动作库”登记、测试和维护。")
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

    @ViewBuilder
    private var semanticActionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设备语义动作")
                .font(.subheadline.weight(.medium))
            Picker("设备语义动作", selection: valueBinding) {
                Text("请选择").tag("")
                ForEach(eligibleSemanticActions) { action in
                    Label(action.title, systemImage: action.symbolName)
                        .tag(action.rawValue)
                }
            }

            Text(
                eligibleSemanticActions.isEmpty
                    ? "尚未从设备状态确认语义动作能力。"
                    : "此类动作按设备合同下发，不会调用 Mac 本机动作。"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                switch kind {
                case .semanticAction:
                    let action = eligibleSemanticActions.first
                    next.value = action?.rawValue ?? ""
                    next.title = action?.title ?? "未选择设备动作"
                case .disabled:
                    next.value = ""
                    next.title = "未设置"
                case .hostAction, .fixedText, .keyChord:
                    next.value = ""
                    next.title = "未命名动作"
                }
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
                if let action = SemanticAction(rawValue: value) {
                    next.title = action.title
                }
                model.setBinding(next, for: control)
            }
        )
    }
}

private enum BoardMappingEligibility {
    static func isMappable(_ target: HostActionTarget) -> Bool {
        switch target.kind {
        case .application, .url, .shortcut:
            true
        case .script:
            target.bookmark != nil
        case .system:
            SystemTool.tool(forActionIdentifier: target.payload) != nil
        }
    }

    static func supports(_ target: HostActionTarget, on control: ControlID) -> Bool {
        guard let tool = target.kind == .system
            ? SystemTool.tool(forActionIdentifier: target.payload)
            : nil else {
            return ControlID.keys.contains(control) || control == .encoderPress
        }

        switch tool {
        case .volumeUp:
            return control == .encoderRight
        case .volumeDown:
            return control == .encoderLeft
        case .volumeMute, .musicPlayPause:
            return control == .encoderPress
        case .musicPrevious:
            return control == .encoderLeft
        case .musicNext:
            return control == .encoderRight
        default:
            return ControlID.keys.contains(control) || control == .encoderPress
        }
    }
}

private struct UnavailableBoardFeaturesNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("未接入设备能力", systemImage: "lightbulb")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("板端灯效和音乐律动灯效暂不可映射，不会写入当前配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
