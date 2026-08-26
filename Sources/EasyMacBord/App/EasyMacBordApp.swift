import SwiftUI

enum AppWindowID {
    static let main = "main-window"
}

@main
struct EasyMacBordApp: App {
    @StateObject private var model: AppModel

    init() {
#if DEBUG
        let debugUIState = DebugUIState(arguments: ProcessInfo.processInfo.arguments)
        let model = AppModel(startServices: debugUIState == nil)
        if let debugUIState {
            model.applyDebugUIState(debugUIState)
        }
        _model = StateObject(wrappedValue: model)
#else
        _model = StateObject(wrappedValue: AppModel())
#endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
                .frame(width: 300)
        } label: {
            BrandMark.menuBarImage
                .accessibilityLabel("EasyMacBord")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("EasyMacBord", id: AppWindowID.main) {
            RootView(model: model)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 800)
    }

}
