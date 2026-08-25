import Foundation

/// Holds a started security-scoped access for as long as it's alive.
///
/// The app and the widget both live outside the user's chosen folder, so every
/// read and write has to happen inside one of these.
final class FolderScope {
    let url: URL
    private var isAccessing = false

    init(url: URL) {
        self.url = url
        isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing { url.stopAccessingSecurityScopedResource() }
    }
}

/// Persists the user's folder choice as a security-scoped bookmark in the App
/// Group, so the widget extension can reach the same folder the app does.
enum FolderAccess {
    private static let bookmarkKey = "stickies.folderBookmark"
    private static let displayPathKey = "stickies.folderDisplayPath"

    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    // MARK: - Choosing

    /// Record the folder the user picked. `url` must be a URL just handed to
    /// us by the system file importer.
    static func store(_ url: URL) throws {
        let scope = FolderScope(url: url)
        let bookmark = try withExtendedLifetime(scope) {
            try url.bookmarkData(
                options: creationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        let defaults = AppGroup.defaults
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(url.path, forKey: displayPathKey)
    }

    static func clear() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: displayPathKey)
    }

    static var hasFolder: Bool {
        AppGroup.defaults.data(forKey: bookmarkKey) != nil
    }

    /// Last known path, for display only. Reading this never touches the disk,
    /// which makes it safe to show while the folder is offline.
    static var displayPath: String? {
        AppGroup.defaults.string(forKey: displayPathKey)
    }

    static var displayName: String? {
        guard let path = displayPath else { return nil }
        return (path as NSString).lastPathComponent
    }

    // MARK: - Using

    /// Resolve the stored bookmark and begin access.
    ///
    /// Returns `nil` when no folder has been chosen or the bookmark can no
    /// longer be resolved (folder deleted, or iCloud not yet signed in).
    static func resolve() -> FolderScope? {
        guard let bookmark = AppGroup.defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        let scope = FolderScope(url: url)
        if isStale {
            // The folder moved. Refresh the bookmark while we still hold
            // access, otherwise the next launch loses it entirely.
            if let refreshed = try? url.bookmarkData(
                options: creationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                AppGroup.defaults.set(refreshed, forKey: bookmarkKey)
                AppGroup.defaults.set(url.path, forKey: displayPathKey)
            }
        }
        return scope
    }

    /// Run `body` with the notes folder available.
    static func withFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let scope = resolve() else { return nil }
        return try withExtendedLifetime(scope) { try body(scope.url) }
    }
}
