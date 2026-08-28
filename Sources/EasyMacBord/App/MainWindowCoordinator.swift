import AppKit
import SwiftUI

@MainActor
protocol MainWindowHandling: AnyObject {
    var isMiniaturized: Bool { get }

    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: MainWindowHandling {}

@MainActor
enum MainWindowPresentation: Equatable {
    case restored
    case requested
    case requestInProgress
}

/// Keeps a menu-bar application's primary window recoverable from the Dock and menu commands.
@MainActor
final class MainWindowCoordinator {
    static let shared = MainWindowCoordinator()

    private weak var mainWindow: (any MainWindowHandling)?
    private var requestWindow: () -> Void = {}
    private var isRequestingWindow = false
    private let activateApplication: () -> Void

    init(activateApplication: @escaping () -> Void = {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }) {
        self.activateApplication = activateApplication
    }

    func register(_ window: any MainWindowHandling) {
        mainWindow = window
        isRequestingWindow = false
    }

    func installWindowRequest(_ requestWindow: @escaping () -> Void) {
        self.requestWindow = requestWindow
    }

    @discardableResult
    func showMainWindow() -> MainWindowPresentation {
        activateApplication()
        guard let mainWindow else {
            guard !isRequestingWindow else { return .requestInProgress }
            isRequestingWindow = true
            requestWindow()
            return .requested
        }
        if mainWindow.isMiniaturized {
            mainWindow.deminiaturize(nil)
        }
        mainWindow.makeKeyAndOrderFront(nil)
        return .restored
    }
}

@MainActor
final class EasyMacBordApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        MainWindowCoordinator.shared.showMainWindow()
        return true
    }
}

struct MainWindowRegistration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MainWindowProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MainWindowProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
#if DEBUG
        if let size = DebugWindowSize(arguments: ProcessInfo.processInfo.arguments) {
            window.setContentSize(NSSize(width: size.width, height: size.height))
        }
#endif
        window.tabbingMode = .disallowed
        MainWindowCoordinator.shared.register(window)
    }
}

struct MainWindowHost<Content: View>: View {
    @Environment(\.openWindow) private var openWindow
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(MainWindowRegistration())
            .onAppear {
                MainWindowCoordinator.shared.installWindowRequest {
                    self.openWindow(id: AppWindowID.main)
                }
            }
    }
}
