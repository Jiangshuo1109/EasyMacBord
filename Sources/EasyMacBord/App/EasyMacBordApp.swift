import SwiftUI

enum AppWindowID {
    static let main = "main-window"
}

@main
struct EasyMacBordApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("EasyMacBord", systemImage: menuBarSymbol) {
            MenuPanel(model: model)
                .frame(width: 300)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("EasyMacBord", id: AppWindowID.main) {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1120, height: 760)
    }

    private var menuBarSymbol: String {
        switch model.connection.state {
        case .connected: "keyboard.badge.ellipsis"
        case .connecting: "arrow.triangle.2.circlepath"
        case .disconnected, .unavailable: "keyboard"
        }
    }
}
