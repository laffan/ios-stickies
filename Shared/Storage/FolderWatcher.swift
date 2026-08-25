import Foundation

/// Notices when the notes folder changes underneath us.
///
/// Two mechanisms, because neither is sufficient alone:
///
/// * a `DispatchSource` vnode watch on the directory, which fires immediately
///   for local edits (Finder, Files, another editor), and
/// * a low-frequency poll of the folder's fingerprint, because cloud
///   providers routinely materialise a file from another device without
///   producing a vnode event the extension-visible descriptor can see.
///
/// Callbacks are coalesced and delivered on the main queue.
final class FolderWatcher {
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.stickies.folderwatcher", qos: .utility)

    private var scope: FolderScope?
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var lastFingerprint = ""
    private var pendingWork: DispatchWorkItem?
    private var isRunning = false

    /// How long to wait after an event before reporting: an app saving a file
    /// often produces several events in a row.
    private let debounce: DispatchTimeInterval = .milliseconds(350)
    private let pollInterval: DispatchTimeInterval = .seconds(4)

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        tearDown()
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.attach()
            self.startPolling()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.tearDown()
        }
    }

    /// Re-resolve the folder — call after the user picks a different one.
    func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.tearDown()
            self.isRunning = true
            self.lastFingerprint = ""
            self.attach()
            self.startPolling()
        }
    }

    // MARK: - Watching

    private func attach() {
        guard let scope = FolderAccess.resolve() else { return }
        self.scope = scope

        let fd = open(scope.url.path, O_EVTONLY)
        guard fd >= 0 else {
            self.scope = nil
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source?.data ?? []
            if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
                // The directory itself moved; the descriptor is now useless.
                self.reattach()
            }
            self.scheduleNotification()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        lastFingerprint = currentFingerprint()
    }

    private func reattach() {
        source?.cancel()
        source = nil
        scope = nil
        guard isRunning else { return }
        queue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            guard let self, self.isRunning, self.source == nil else { return }
            self.attach()
        }
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.source == nil { self.attach() }
            let fingerprint = self.currentFingerprint()
            guard fingerprint != self.lastFingerprint else { return }
            self.lastFingerprint = fingerprint
            self.deliver()
        }
        timer.resume()
        pollTimer = timer
    }

    private func currentFingerprint() -> String {
        FolderAccess.withFolder { NoteFileIO.fingerprint(in: $0) } ?? ""
    }

    private func scheduleNotification() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastFingerprint = self.currentFingerprint()
            self.deliver()
        }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func deliver() {
        let callback = onChange
        DispatchQueue.main.async { callback() }
    }

    private func tearDown() {
        pendingWork?.cancel()
        pendingWork = nil
        pollTimer?.cancel()
        pollTimer = nil
        source?.cancel()
        source = nil
        scope = nil
    }
}
