import SwiftUI

enum AppWindowID {
    static let main = "main-window"
}

enum AppLaunchConfiguration {
    static func deviceAccessMode(
        arguments: [String],
        allowsTestingOverrides: Bool
    ) -> DeviceSession.AccessMode {
        guard allowsTestingOverrides else { return .standard }
        return DeviceSession.AccessMode(arguments: arguments)
    }
}

@main
struct EasyMacBordApp: App {
    @StateObject private var model: AppModel
    @StateObject private var preferences: AppPreferences
    @NSApplicationDelegateAdaptor(EasyMacBordApplicationDelegate.self) private var applicationDelegate

    init() {
#if DEBUG
        let deviceAccessMode = AppLaunchConfiguration.deviceAccessMode(
            arguments: ProcessInfo.processInfo.arguments,
            allowsTestingOverrides: true
        )
        let debugUIState = DebugUIState(arguments: ProcessInfo.processInfo.arguments)
        if let debugUIState {
            let defaults = Self.debugDefaults()
            let model = AppModel(startServices: false, defaults: defaults)
            model.applyDebugUIState(debugUIState)
            _preferences = StateObject(wrappedValue: AppPreferences(defaults: defaults))
            _model = StateObject(wrappedValue: model)
        } else {
            _model = StateObject(wrappedValue: AppModel(deviceAccessMode: deviceAccessMode))
            _preferences = StateObject(wrappedValue: AppPreferences())
        }
#else
        let deviceAccessMode = AppLaunchConfiguration.deviceAccessMode(
            arguments: ProcessInfo.processInfo.arguments,
            allowsTestingOverrides: false
        )
        _model = StateObject(wrappedValue: AppModel(deviceAccessMode: deviceAccessMode))
        _preferences = StateObject(wrappedValue: AppPreferences())
#endif
    }

#if DEBUG
    private static func debugDefaults() -> UserDefaults {
        let suiteName = "com.easymacbord.debug-ui"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
#endif

    var body: some Scene {
        Window("EasyMacBord", id: AppWindowID.main) {
            MainWindowHost {
                RootView(model: model, preferences: preferences)
            }
                .frame(minWidth: 1120, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 800)

        MenuBarExtra(isInserted: preferences.menuBarVisibility) {
            MenuPanel(model: model)
                .frame(width: 300)
        } label: {
            BrandMark.menuBarImage
                .accessibilityLabel("EasyMacBord")
        }
        .menuBarExtraStyle(.window)
    }

}
