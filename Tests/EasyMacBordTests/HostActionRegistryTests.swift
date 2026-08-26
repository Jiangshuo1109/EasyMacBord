import XCTest
@testable import EasyMacBord

final class HostActionRegistryTests: XCTestCase {
    func testRegisteredTargetCanBeRetrievedByItsUUID() async {
        let id = UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
        let target = HostActionTarget(id: id, kind: .url, title: "项目主页", payload: "https://example.com")
        let registry = HostActionRegistry()

        await registry.register(target)

        let registered = await registry.target(for: id)
        let missing = await registry.target(for: UUID())
        XCTAssertEqual(registered, target)
        XCTAssertNil(missing)
    }

    func testReplaceRemovesTargetsThatAreNoLongerPersisted() async {
        let registry = HostActionRegistry()
        let preserved = HostActionTarget(kind: .system, title: "截屏", payload: "screenshot")
        await registry.register(HostActionTarget(kind: .url, title: "旧动作", payload: "https://old.example"))

        await registry.replace(with: [preserved])

        let targets = await registry.allTargets()
        XCTAssertEqual(targets, [preserved])
    }
}
