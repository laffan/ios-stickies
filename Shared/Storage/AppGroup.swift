import Foundation

/// The App Group shared by the app and the widget extension.
///
/// The identifier comes from `Config/Base.xcconfig` by way of both Info.plists,
/// so there is exactly one place to change it.
enum AppGroup {
    /// The value written into both targets' entitlements.
    ///
    /// Always the bare `group.…` form: Apple's developer portal stores an App
    /// Group's identifier without a team prefix (it keeps the prefix in a
    /// separate field) and rejects any identifier that doesn't start with
    /// `group.`. A team-prefixed literal in an entitlements file makes Xcode
    /// try to register a group under that name, which fails the build.
    private static let configuredIdentifier: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        // An unexpanded build setting means the xcconfig wasn't applied; fall
        // back rather than creating a container named "$(APP_GROUP_ID)".
        if let value, !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }
        return "group.com.example.stickies"
    }()

    /// The team ID, published through Info.plist purely so the container
    /// lookup below can try the prefixed form. It never appears in an
    /// entitlement.
    private static let teamIdentifier: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "DevelopmentTeamID") as? String,
              !value.isEmpty, !value.hasPrefix("$(")
        else {
            return nil
        }
        return value
    }()

    /// macOS has historically kept group containers under
    /// `~/Library/Group Containers/<team>.<group>` while iOS uses the bare
    /// identifier. Rather than encode a guess about which platform wants
    /// which, ask the file system which one actually exists.
    private static var candidateIdentifiers: [String] {
        var candidates = [configuredIdentifier]
        if let teamIdentifier, !configuredIdentifier.hasPrefix("\(teamIdentifier).") {
            candidates.append("\(teamIdentifier).\(configuredIdentifier)")
        }
        return candidates
    }

    /// The identifier that resolves to a real container, resolved once.
    static let identifier: String = {
        let manager = FileManager.default
        for candidate in candidateIdentifiers
        where manager.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
            return candidate
        }
        return configuredIdentifier
    }()

    /// Shared preferences. Falls back to standard defaults so a misconfigured
    /// App Group degrades to "the app still works, widgets don't" rather than
    /// crashing.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// True when the App Group is actually usable — surfaced in Settings
    /// because it's the single most common reason widgets come up empty.
    static var isConfigured: Bool {
        containerURL != nil && UserDefaults(suiteName: identifier) != nil
    }
}
