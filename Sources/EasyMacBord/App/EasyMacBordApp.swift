import SwiftUI

enum AppWindowID {
    static let main = "main-window"
}

@main
struct EasyMacBordApp: App {
    @StateObject private var model: AppModel
    @StateObject private var preferences: AppPreferences
    @NSApplicationDelegateAdaptor(EasyMacBordApplicationDelegate.self) private var applicationDelegate

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
        _preferences = StateObject(wrappedValue: AppPreferences())
    }

    var body: some Scene {
        MenuBarExtra(isInserted: preferences.menuBarVisibility) {
            MenuPanel(model: model)
                .frame(width: 300)
        } label: {
            BrandMark.menuBarImage
                .accessibilityLabel("EasyMacBord")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("EasyMacBord", id: AppWindowID.main) {
            MainWindowHost {
                RootView(model: model, preferences: preferences)
            }
                .frame(minWidth: 1120, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 800)
    }

}
