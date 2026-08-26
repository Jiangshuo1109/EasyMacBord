import Foundation

struct InstalledApplication: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case user
        case local
        case system

        var title: String {
            switch self {
            case .user: "用户应用"
            case .local: "应用程序"
            case .system: "系统应用"
            }
        }
    }

    let url: URL
    let name: String
    let bundleIdentifier: String?
    let source: Source

    var id: String { url.standardizedFileURL.path }
}

enum InstalledApplicationCatalog {
    static func discover() -> [InstalledApplication] {
        discover(in: applicationRoots())
    }

    static func discover(in roots: [URL]) -> [InstalledApplication] {
        let fileManager = FileManager.default
        var discovered: [InstalledApplication] = []
        var identities = Set<String>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let candidate as URL in enumerator {
                guard candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                enumerator.skipDescendants()

                let bundle = Bundle(url: candidate)
                let bundleIdentifier = bundle?.bundleIdentifier
                let identity = bundleIdentifier ?? candidate.standardizedFileURL.path
                guard identities.insert(identity).inserted else { continue }

                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? candidate.deletingPathExtension().lastPathComponent
                discovered.append(
                    InstalledApplication(
                        url: candidate,
                        name: name,
                        bundleIdentifier: bundleIdentifier,
                        source: source(for: root)
                    )
                )
            }
        }

        return discovered.sorted {
            let result = $0.name.localizedStandardCompare($1.name)
            return result == .orderedSame ? $0.source.rawValue < $1.source.rawValue : result == .orderedAscending
        }
    }

    private static func applicationRoots() -> [URL] {
        let roots = FileManager.default.urls(
            for: .applicationDirectory,
            in: [.userDomainMask, .localDomainMask, .systemDomainMask]
        )
        var seen = Set<URL>()
        return roots.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
    }

    private static func source(for root: URL) -> InstalledApplication.Source {
        let path = root.standardizedFileURL.path
        if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) { return .user }
        if path.hasPrefix("/System/") { return .system }
        return .local
    }
}
