import XCTest
@testable import EasyMacBord

final class MainWindowCoordinatorTests: XCTestCase {
    @MainActor
    func testRestoresRegisteredWindowWithoutRequestingAnotherOne() {
        var activationCount = 0
        var requestCount = 0
        let window = FakeMainWindow(isMiniaturized: true)
        let coordinator = MainWindowCoordinator {
            activationCount += 1
        }
        coordinator.register(window)
        coordinator.installWindowRequest {
            requestCount += 1
        }

        let result = coordinator.showMainWindow()

        XCTAssertEqual(result, .restored)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(window.deminiaturizeCount, 1)
        XCTAssertEqual(window.makeKeyCount, 1)
    }

    @MainActor
    func testRequestsWindowOnlyWhenNoneIsRegistered() {
        var activationCount = 0
        var requestCount = 0
        let coordinator = MainWindowCoordinator {
            activationCount += 1
        }
        coordinator.installWindowRequest {
            requestCount += 1
        }

        let result = coordinator.showMainWindow()

        XCTAssertEqual(result, .requested)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testDoesNotRequestMoreThanOneWindowWhileFirstRequestIsPending() {
        var requestCount = 0
        let coordinator = MainWindowCoordinator()
        coordinator.installWindowRequest {
            requestCount += 1
        }

        XCTAssertEqual(coordinator.showMainWindow(), .requested)
        XCTAssertEqual(coordinator.showMainWindow(), .requestInProgress)
        XCTAssertEqual(requestCount, 1)
    }
}

@MainActor
private final class FakeMainWindow: MainWindowHandling {
    let isMiniaturized: Bool
    private(set) var deminiaturizeCount = 0
    private(set) var makeKeyCount = 0

    init(isMiniaturized: Bool) {
        self.isMiniaturized = isMiniaturized
    }

    func deminiaturize(_ sender: Any?) {
        deminiaturizeCount += 1
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyCount += 1
    }
}
