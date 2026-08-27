import AppKit
import SwiftUI
import XCTest
@testable import EasyMacBord

final class KeyChordRecorderTests: XCTestCase {
    @MainActor
    func testRecorderCapturesSupportedKeyInCanonicalFormat() {
        let state = RecordingState()
        var result: Result<String, KeyChordRecordingError>?
        let recorder = makeRecorder(state: state) { result = $0 }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "P",
            charactersIgnoringModifiers: "p",
            isARepeat: false,
            keyCode: 35
        )!

        XCTAssertTrue(recorder.record(event))
        XCTAssertEqual(result, .success("Meta+Shift+P"))
        XCTAssertFalse(state.isRecording)
    }

    @MainActor
    func testRecorderRejectsFunctionAndMediaKeys() {
        let state = RecordingState()
        var result: Result<String, KeyChordRecordingError>?
        let recorder = makeRecorder(state: state) { result = $0 }
        let functionEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.function],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "f",
            charactersIgnoringModifiers: "f",
            isARepeat: false,
            keyCode: 3
        )!

        XCTAssertTrue(recorder.record(functionEvent))
        XCTAssertEqual(result, .failure(.functionKey))
        XCTAssertFalse(state.isRecording)

        state.isRecording = true
        XCTAssertTrue(recorder.recordMediaKey())
        XCTAssertEqual(result, .failure(.mediaKey))
        XCTAssertFalse(state.isRecording)
    }

    @MainActor
    private func makeRecorder(
        state: RecordingState,
        capture: @escaping (Result<String, KeyChordRecordingError>) -> Void
    ) -> KeyChordRecorder.Coordinator {
        KeyChordRecorder.Coordinator(
            isRecording: Binding(
                get: { state.isRecording },
                set: { state.isRecording = $0 }
            ),
            capture: capture
        )
    }
}

@MainActor
private final class RecordingState {
    var isRecording = true
}
