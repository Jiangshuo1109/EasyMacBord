import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    enum PrereleaseIdentifier: Equatable, Sendable {
        case number(Int)
        case text(String)
    }

    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [PrereleaseIdentifier]?

    init?(_ rawValue: String) {
        let tag = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let withoutBuildMetadata = withoutPrefix.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard withoutBuildMetadata.count <= 2,
              let versionPart = withoutBuildMetadata.first,
              !versionPart.isEmpty,
              withoutBuildMetadata.count == 1 || Self.isValidBuildMetadata(String(withoutBuildMetadata[1])) else {
            return nil
        }

        let components = versionPart.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = components.first,
              let parsedCore = Self.parseCore(String(core)) else {
            return nil
        }

        if components.count == 2 {
            guard let parsedPrerelease = Self.parsePrerelease(String(components[1])) else { return nil }
            prerelease = parsedPrerelease
        } else {
            prerelease = nil
        }

        major = parsedCore.0
        minor = parsedCore.1
        patch = parsedCore.2
    }

    var isPrerelease: Bool {
        prerelease != nil
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard let prerelease else { return core }
        return core + "-" + prerelease.map(Self.description(for:)).joined(separator: ".")
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case let (.some(lhsIdentifiers), .some(rhsIdentifiers)):
            for (lhsIdentifier, rhsIdentifier) in zip(lhsIdentifiers, rhsIdentifiers) {
                if lhsIdentifier == rhsIdentifier { continue }
                return Self.isPrereleaseIdentifier(lhsIdentifier, before: rhsIdentifier)
            }
            return lhsIdentifiers.count < rhsIdentifiers.count
        }
    }

    private static func parseCore(_ value: String) -> (Int, Int, Int)? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = parseNumber(String(components[0])),
              let minor = parseNumber(String(components[1])),
              let patch = parseNumber(String(components[2])) else {
            return nil
        }
        return (major, minor, patch)
    }

    private static func parsePrerelease(_ value: String) -> [PrereleaseIdentifier]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        var identifiers: [PrereleaseIdentifier] = []
        for component in components {
            let token = String(component)
            guard !token.isEmpty,
                  Self.isValidIdentifier(token) else {
                return nil
            }
            if Self.isASCIIInteger(token) {
                guard let number = parseNumber(token) else { return nil }
                identifiers.append(.number(number))
            } else {
                identifiers.append(.text(token))
            }
        }
        return identifiers
    }

    private static func parseNumber(_ value: String) -> Int? {
        guard !value.isEmpty,
              isASCIIInteger(value),
              value == "0" || !value.hasPrefix("0") else {
            return nil
        }
        return Int(value)
    }

    private static func isValidBuildMetadata(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            isValidIdentifier(String(component))
        }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar.value == 45)
        }
    }

    private static func isASCIIInteger(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 48 && scalar.value <= 57
        }
    }

    private static func isPrereleaseIdentifier(_ lhs: PrereleaseIdentifier, before rhs: PrereleaseIdentifier) -> Bool {
        switch (lhs, rhs) {
        case let (.number(lhsValue), .number(rhsValue)):
            return lhsValue < rhsValue
        case (.number, .text):
            return true
        case (.text, .number):
            return false
        case let (.text(lhsValue), .text(rhsValue)):
            return lhsValue < rhsValue
        }
    }

    private static func description(for identifier: PrereleaseIdentifier) -> String {
        switch identifier {
        case .number(let value): String(value)
        case .text(let value): value
        }
    }
}

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL
    let body: String?
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case htmlURL = "html_url"
        case body
        case assets
    }
}

struct ReleaseAssetSelection: Equatable, Sendable {
    let dmgURL: URL
    let checksumURL: URL

    static func select(from assets: [GitHubReleaseAsset]) -> ReleaseAssetSelection? {
        let dmgAssets = assets.filter { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix("-arm64.dmg")
        }
        guard let dmg = dmgAssets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }).first else {
            return nil
        }
        let expectedChecksumName = dmg.name + ".sha256"
        guard let checksum = assets.first(where: { $0.name == expectedChecksumName }) else {
            return nil
        }
        return ReleaseAssetSelection(dmgURL: dmg.browserDownloadURL, checksumURL: checksum.browserDownloadURL)
    }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: SemanticVersion
    let versionLabel: String
    let releaseNotes: String
    let releasePageURL: URL
    let dmgURL: URL
    let checksumURL: URL
}

enum GitHubReleaseCheckResult: Equatable, Sendable {
    case updateAvailable(AvailableUpdate)
    case upToDate
    case noUsableRelease
}

enum AppUpdateCheckState: Equatable {
    case idle
    case checking
    case completed(GitHubReleaseCheckResult, checkedAt: Date)
    case failed(message: String, checkedAt: Date)
}

enum GitHubReleaseCheckerError: Error, Equatable, Sendable {
    case network
    case invalidResponse
    case rateLimited
    case httpStatus(Int)
    case invalidPayload
}

protocol ReleaseHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionReleaseHTTPClient: ReleaseHTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

protocol GitHubReleaseChecking: Sendable {
    func check(currentVersion: SemanticVersion) async throws -> GitHubReleaseCheckResult
}

struct GitHubReleaseChecker: GitHubReleaseChecking {
    static let endpoint = URL(string: "https://api.github.com/repos/Jiangshuo1109/EasyMacBord/releases")!

    private let client: any ReleaseHTTPClient
    private let decoder: JSONDecoder

    init(client: any ReleaseHTTPClient = URLSessionReleaseHTTPClient(), decoder: JSONDecoder = JSONDecoder()) {
        self.client = client
        self.decoder = decoder
    }

    init(session: URLSession, decoder: JSONDecoder = JSONDecoder()) {
        self.init(client: URLSessionReleaseHTTPClient(session: session), decoder: decoder)
    }

    func check(currentVersion: SemanticVersion) async throws -> GitHubReleaseCheckResult {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EasyMacBord update checker", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            throw GitHubReleaseCheckerError.network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckerError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 || httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubReleaseCheckerError.rateLimited
            }
            throw GitHubReleaseCheckerError.httpStatus(httpResponse.statusCode)
        }

        let releases: [GitHubRelease]
        do {
            releases = try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw GitHubReleaseCheckerError.invalidPayload
        }

        let includePrereleases = currentVersion.isPrerelease
        let candidates = releases.compactMap { release -> AvailableUpdate? in
            guard !release.draft,
                  let version = SemanticVersion(release.tagName),
                  let selection = ReleaseAssetSelection.select(from: release.assets) else {
                return nil
            }
            let isPrerelease = release.prerelease || version.isPrerelease
            guard includePrereleases || !isPrerelease else { return nil }
            return AvailableUpdate(
                version: version,
                versionLabel: release.tagName,
                releaseNotes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                releasePageURL: release.htmlURL,
                dmgURL: selection.dmgURL,
                checksumURL: selection.checksumURL
            )
        }

        guard let newest = candidates.max(by: { $0.version < $1.version }) else {
            return .noUsableRelease
        }
        return newest.version > currentVersion ? .updateAvailable(newest) : .upToDate
    }
}
