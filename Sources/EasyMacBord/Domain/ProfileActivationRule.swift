import Foundation

/// A profile can be activated when a user-selected application becomes frontmost.
/// Only the bundle identifier is persisted; application paths remain in security
/// scoped bookmarks owned by the action registry.
struct ProfileActivationRule: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var profileID: UUID
    var applicationBundleID: String
    var applicationName: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        profileID: UUID,
        applicationBundleID: String,
        applicationName: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.profileID = profileID
        self.applicationBundleID = applicationBundleID
        self.applicationName = applicationName
        self.isEnabled = isEnabled
    }
}

enum ProfileActivationRuleIssue: Equatable {
    case missingApplication
    case missingProfile
    case duplicateApplication(String)
}

enum ProfileActivationRules {
    static func validate(
        _ rule: ProfileActivationRule,
        profiles: [Profile],
        existingRules: [ProfileActivationRule]
    ) -> ProfileActivationRuleIssue? {
        let bundleID = rule.applicationBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return .missingApplication }
        guard profiles.contains(where: { $0.id == rule.profileID }) else { return .missingProfile }
        if existingRules.contains(where: {
            $0.id != rule.id &&
                $0.isEnabled &&
                $0.applicationBundleID.caseInsensitiveCompare(bundleID) == .orderedSame
        }) {
            return .duplicateApplication(bundleID)
        }
        return nil
    }

    /// Rules are deliberately one-to-one by bundle identifier. This makes a
    /// foreground-app event deterministic and avoids repeated profile swaps.
    static func matchingRule(
        bundleIdentifier: String?,
        rules: [ProfileActivationRule],
        profiles: [Profile]
    ) -> ProfileActivationRule? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        let profileIDs = Set(profiles.map(\.id))
        return rules.first(where: {
            $0.isEnabled &&
                profileIDs.contains($0.profileID) &&
                $0.applicationBundleID.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        })
    }
}

enum ProfileAutoSyncPlan: Equatable {
    case ignore
    case selectOnly(UUID)
    case selectAndSchedule(UUID)

    static func make(
        bundleIdentifier: String?,
        rules: [ProfileActivationRule],
        profiles: [Profile],
        selectedProfileID: UUID,
        isEnabled: Bool,
        isDeviceConnected: Bool,
        isSyncing: Bool,
        isLocalSaveComplete: Bool
    ) -> ProfileAutoSyncPlan {
        guard isEnabled,
              let rule = ProfileActivationRules.matchingRule(
                bundleIdentifier: bundleIdentifier,
                rules: rules,
                profiles: profiles
              ),
              rule.profileID != selectedProfileID else {
            return .ignore
        }

        guard isDeviceConnected, !isSyncing, isLocalSaveComplete else {
            return .selectOnly(rule.profileID)
        }
        return .selectAndSchedule(rule.profileID)
    }

    /// A failed automatic send stays pending, but is retried only after the
    /// matching app is activated again or the transport reconnects.
    static func shouldRetryPendingSync(
        bundleIdentifier: String?,
        pendingProfileID: UUID?,
        rules: [ProfileActivationRule],
        profiles: [Profile],
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled,
              let pendingProfileID,
              let rule = ProfileActivationRules.matchingRule(
                bundleIdentifier: bundleIdentifier,
                rules: rules,
                profiles: profiles
              ) else {
            return false
        }
        return rule.profileID == pendingProfileID
    }
}
