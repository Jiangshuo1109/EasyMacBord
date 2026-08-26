import Foundation
import XCTest
@testable import EasyMacBord

final class InstalledApplicationCatalogTests: XCTestCase {
    func testFindsTopLevelAndNestedApplications() throws {
        let root = try makeTemporaryDirectory()
        try makeApplication(named: "Focus.app", in: root)
        let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        try makeApplication(named: "Console.app", in: utilities)

        let applications = InstalledApplicationCatalog.discover(in: [root])

        XCTAssertEqual(applications.map(\.name), ["Console", "Focus"])
    }

    func testUsesTheFirstRootForDuplicatedBundleIdentifier() throws {
        let firstRoot = try makeTemporaryDirectory()
        let secondRoot = try makeTemporaryDirectory()
        try makeApplication(named: "Preferred.app", bundleIdentifier: "com.example.tool", in: firstRoot)
        try makeApplication(named: "Duplicate.app", bundleIdentifier: "com.example.tool", in: secondRoot)

        let applications = InstalledApplicationCatalog.discover(in: [firstRoot, secondRoot])

        XCTAssertEqual(applications.count, 1)
        XCTAssertEqual(applications.first?.name, "Preferred")
    }

    func testKeepsApplicationsWithoutBundleMetadataDistinct() throws {
        let root = try makeTemporaryDirectory()
        try makeApplication(named: "One.app", in: root)
        try makeApplication(named: "Two.app", in: root)

        let applications = InstalledApplicationCatalog.discover(in: [root])

        XCTAssertEqual(applications.map(\.name), ["One", "Two"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeApplication(named name: String, bundleIdentifier: String? = nil, in directory: URL) throws {
        let app = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        guard let bundleIdentifier else { return }

        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": bundleIdentifier] as NSDictionary
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
