import Foundation
import XCTest
@testable import EasyMacBord

final class GitHubReleaseCheckerTests: XCTestCase {
    func testSemanticVersionOrdersPrereleasesBeforeFinalRelease() {
        let versions = [
            "v0.1.0-beta.2",
            "v0.1.0-alpha",
            "v0.1.0",
            "v0.1.0-beta.11",
            "v0.1.0-alpha.1",
            "v0.1.0-rc.1",
            "v0.1.0-beta"
        ].compactMap(SemanticVersion.init)

        XCTAssertEqual(
            versions.sorted().map(\.description),
            [
                "0.1.0-alpha",
                "0.1.0-alpha.1",
                "0.1.0-beta",
                "0.1.0-beta.2",
                "0.1.0-beta.11",
                "0.1.0-rc.1",
                "0.1.0"
            ]
        )
    }

    func testSemanticVersionAcceptsGitHubTagPrefixAndBuildMetadata() {
        XCTAssertEqual(SemanticVersion("v0.1.0-beta.1+20260827")?.description, "0.1.0-beta.1")
        XCTAssertNil(SemanticVersion("0.1"))
        XCTAssertNil(SemanticVersion("0.01.0"))
        XCTAssertNil(SemanticVersion("0.1.0-01"))
        XCTAssertNil(SemanticVersion("0.1.0-beta..1"))
        XCTAssertNil(SemanticVersion("0.1.0+"))
    }

    func testStableBuildExcludesPrereleaseAndSelectsArm64DmgWithChecksum() async throws {
        let client = FakeReleaseHTTPClient(response: makeResponse(releases: [
            release(tag: "v0.2.0-beta.1", prerelease: true, assets: validAssets(version: "0.2.0-beta.1")),
            release(tag: "v0.1.1", prerelease: false, assets: validAssets(version: "0.1.1"))
        ]))
        let checker = GitHubReleaseChecker(client: client)

        let result = try await checker.check(currentVersion: SemanticVersion("0.1.0")!)

        guard case .updateAvailable(let update) = result else {
            return XCTFail("Expected an available stable update")
        }
        XCTAssertEqual(update.version.description, "0.1.1")
        XCTAssertEqual(update.dmgURL.lastPathComponent, "EasyMacBord-0.1.1-arm64.dmg")
        XCTAssertEqual(update.checksumURL.lastPathComponent, "EasyMacBord-0.1.1-arm64.dmg.sha256")
        XCTAssertEqual(client.requestedURL, GitHubReleaseChecker.endpoint)
    }

    func testBetaBuildIncludesNewerPrerelease() async throws {
        let client = FakeReleaseHTTPClient(response: makeResponse(releases: [
            release(tag: "v0.1.0-beta.3", prerelease: true, assets: validAssets(version: "0.1.0-beta.3")),
            release(tag: "v0.1.0-beta.2", prerelease: true, assets: validAssets(version: "0.1.0-beta.2"))
        ]))
        let checker = GitHubReleaseChecker(client: client)

        let result = try await checker.check(currentVersion: SemanticVersion("0.1.0-beta.1")!)

        guard case .updateAvailable(let update) = result else {
            return XCTFail("Expected a newer beta update")
        }
        XCTAssertEqual(update.version.description, "0.1.0-beta.3")
    }

    func testDraftAndIncompleteReleasesAreNotUsable() async throws {
        let client = FakeReleaseHTTPClient(response: makeResponse(releases: [
            release(tag: "v0.3.0", draft: true, assets: validAssets(version: "0.3.0")),
            release(tag: "v0.2.0", assets: [asset(name: "EasyMacBord-0.2.0-arm64.dmg")]),
            release(tag: "not-a-version", assets: validAssets(version: "0.9.0"))
        ]))

        let result = try await GitHubReleaseChecker(client: client).check(currentVersion: SemanticVersion("0.1.0")!)

        XCTAssertEqual(result, .noUsableRelease)
    }

    func testReturnsUpToDateWhenLatestUsableReleaseIsNotNewer() async throws {
        let client = FakeReleaseHTTPClient(response: makeResponse(releases: [
            release(tag: "v0.1.0", assets: validAssets(version: "0.1.0"))
        ]))

        let result = try await GitHubReleaseChecker(client: client).check(currentVersion: SemanticVersion("0.1.0")!)

        XCTAssertEqual(result, .upToDate)
    }

    func testRejectsNonSuccessResponsesWithoutExposingPayload() async {
        let response = HTTPURLResponse(
            url: GitHubReleaseChecker.endpoint,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = FakeReleaseHTTPClient(response: (Data("private response".utf8), response))

        do {
            _ = try await GitHubReleaseChecker(client: client).check(currentVersion: SemanticVersion("0.1.0")!)
            XCTFail("Expected an HTTP error")
        } catch let error as GitHubReleaseCheckerError {
            XCTAssertEqual(error, .httpStatus(403))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRecognizesGitHubRateLimitHeader() async {
        let response = HTTPURLResponse(
            url: GitHubReleaseChecker.endpoint,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["X-RateLimit-Remaining": "0"]
        )!
        let client = FakeReleaseHTTPClient(response: (Data(), response))

        do {
            _ = try await GitHubReleaseChecker(client: client).check(currentVersion: SemanticVersion("0.1.0")!)
            XCTFail("Expected a rate-limit error")
        } catch let error as GitHubReleaseCheckerError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeResponse(releases: [[String: Any]]) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: releases)
        let response = HTTPURLResponse(
            url: GitHubReleaseChecker.endpoint,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    private func release(
        tag: String,
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [[String: String]]
    ) -> [String: Any] {
        [
            "tag_name": tag,
            "draft": draft,
            "prerelease": prerelease,
            "html_url": "https://github.com/Jiangshuo1109/EasyMacBord/releases/tag/\(tag)",
            "body": "Release notes for \(tag)",
            "assets": assets
        ]
    }

    private func validAssets(version: String) -> [[String: String]] {
        let dmg = "EasyMacBord-\(version)-arm64.dmg"
        return [asset(name: dmg), asset(name: "\(dmg).sha256")]
    }

    private func asset(name: String) -> [String: String] {
        [
            "name": name,
            "browser_download_url": "https://github.com/Jiangshuo1109/EasyMacBord/releases/download/test/\(name)"
        ]
    }
}

private final class FakeReleaseHTTPClient: ReleaseHTTPClient, @unchecked Sendable {
    let response: (Data, URLResponse)
    var requestedURL: URL?

    init(response: (Data, URLResponse)) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestedURL = request.url
        return response
    }
}
