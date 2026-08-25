import Foundation

/// The App Group shared by the app and the widget extension.
///
/// The identifier is injected into both Info.plists from `Config/Base.xcconfig`
/// so there is exactly one place to change it.
enum AppGroup {
    static let identifier: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        // An unexpanded build setting means the xcconfig wasn't applied; fall
        // back rather than creating a container named "$(APP_GROUP_ID)".
        if let value, !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }
        return "group.com.example.stickies"
    }()

    /// Shared preferences. Falls back to standard defaults so a
    /// misconfigured App Group degrades to "the app still works, widgets
    /// don't" instead of crashing.
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
