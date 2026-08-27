import AppKit
import SwiftUI

enum KeyChordRecordingError: Error, Equatable {
    case unsupportedKey
    case functionKey
    case modifierOnly
    case mediaKey

    var message: String {
        switch self {
        case .unsupportedKey: "此按键暂不支持，请使用字母、数字、功能键或导航键。"
        case .functionKey: "Fn 不能作为设备组合键的一部分。"
        case .modifierOnly: "请同时按下一个受支持的按键；单独的修饰键不能保存。"
        case .mediaKey: "媒体键不能作为设备组合键的一部分。"
        }
    }
}

struct KeyChordRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let capture: (Result<String, KeyChordRecordingError>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, capture: capture)
    }

    func makeNSView(context: Context) -> RecordingView {
        RecordingView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: RecordingView, context: Context) {
        context.coordinator.capture = capture
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    @MainActor
    final class Coordinator {
        private var isRecording: Binding<Bool>
        var capture: (Result<String, KeyChordRecordingError>) -> Void
        private var modifierOnlyWorkItem: DispatchWorkItem?

        init(
            isRecording: Binding<Bool>,
            capture: @escaping (Result<String, KeyChordRecordingError>) -> Void
        ) {
            self.isRecording = isRecording
            self.capture = capture
        }

        func record(_ event: NSEvent) -> Bool {
            guard isRecording.wrappedValue else { return false }
            modifierOnlyWorkItem?.cancel()
            let modifiers = keyChordModifiers(from: event.modifierFlags)
            let result: Result<String, KeyChordRecordingError>
            if modifiers.contains(.function) {
                result = .failure(.functionKey)
            } else if let key = KeyChord.key(forKeyCode: event.keyCode),
                      let chord = KeyChord.make(modifiers: modifiers, key: key) {
                result = .success(chord)
            } else {
                result = .failure(.unsupportedKey)
            }
            finish(result)
            return true
        }

        func recordModifierChange(_ event: NSEvent) -> Bool {
            guard isRecording.wrappedValue else { return false }
            let modifiers = keyChordModifiers(from: event.modifierFlags)
            guard !modifiers.contains(.function) else {
                finish(.failure(.functionKey))
                return true
            }
            guard !modifiers.isEmpty else { return true }

            modifierOnlyWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isRecording.wrappedValue else { return }
                self.finish(.failure(.modifierOnly))
            }
            modifierOnlyWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
            return true
        }

        func recordMediaKey() -> Bool {
            guard isRecording.wrappedValue else { return false }
            finish(.failure(.mediaKey))
            return true
        }

        private func finish(_ result: Result<String, KeyChordRecordingError>) {
            modifierOnlyWorkItem?.cancel()
            modifierOnlyWorkItem = nil
            isRecording.wrappedValue = false
            capture(result)
        }

        private func keyChordModifiers(from flags: NSEvent.ModifierFlags) -> KeyChord.Modifiers {
            let flags = flags.intersection(.deviceIndependentFlagsMask)
            var result: KeyChord.Modifiers = []
            if flags.contains(.command) { result.insert(.meta) }
            if flags.contains(.control) { result.insert(.control) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.function) { result.insert(.function) }
            return result
        }
    }

    final class RecordingView: NSView {
        private let recorder: Coordinator
        private var mediaKeyMonitor: Any?

        init(coordinator: Coordinator) {
            recorder = coordinator
            super.init(frame: .zero)
            mediaKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                guard let self else { return event }
                return self.recorder.recordMediaKey() ? nil : event
            }
        }

        required init?(coder: NSCoder) {
            nil
        }

        isolated deinit {
            if let mediaKeyMonitor {
                NSEvent.removeMonitor(mediaKeyMonitor)
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if !recorder.record(event) {
                super.keyDown(with: event)
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            recorder.record(event)
        }

        override func flagsChanged(with event: NSEvent) {
            if !recorder.recordModifierChange(event) {
                super.flagsChanged(with: event)
            }
        }

    }
}
