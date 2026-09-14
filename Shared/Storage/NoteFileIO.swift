import Foundation

/// All disk access for notes.
///
/// Every read and write goes through `NSFileCoordinator` so the folder can
/// safely live in iCloud Drive, Dropbox or any other synced location: the
/// coordinator is what makes another device's write and our read take turns.
enum NoteFileIO {
    enum IOError: LocalizedError {
        case folderUnavailable
        case unreadable(String)
        case nameTaken(String)

        var errorDescription: String? {
            switch self {
            case .folderUnavailable:
                return "The notes folder isn't available right now."
            case .unreadable(let name):
                return "Couldn't read “\(name)”."
            case .nameTaken(let name):
                return "A note called “\(name)” already exists."
            }
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .creationDateKey,
        .contentModificationDateKey,
        .fileSizeKey
    ]

    // MARK: - Listing

    /// Note files directly inside `folder`. Sub-folders are ignored: a sticky
    /// board is one flat folder, which keeps file names usable as widget ids.
    static func listNoteURLs(in folder: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        )

        var urls: [URL] = []
        for url in contents {
            if url.pathExtension.lowercased() == "icloud" {
                // An undownloaded iCloud file appears as ".Name.md.icloud".
                requestDownload(forPlaceholder: url, in: folder)
                continue
            }
            guard NoteFile.isNoteFile(url) else { continue }
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            if values?.isRegularFile == false { continue }
            urls.append(url)
        }
        return urls
    }

    private static func requestDownload(forPlaceholder url: URL, in folder: URL) {
        var name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return }
        name.removeFirst()
        name.removeLast(".icloud".count)
        let real = folder.appendingPathComponent(name)
        guard NoteFile.isNoteFile(real) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: real)
    }

    /// Cheap signature of the folder's contents, used to spot changes made by
    /// another app or another device without re-reading every file.
    static func fingerprint(in folder: URL) -> String {
        guard let urls = try? listNoteURLs(in: folder) else { return "" }
        let parts = urls.map { url -> String in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            return "\(url.lastPathComponent)|\(size)|\(Int(modified))"
        }
        return parts.sorted().joined(separator: ";")
    }

    // MARK: - Reading

    static func readAll(in folder: URL) -> [Note] {
        guard let urls = try? listNoteURLs(in: folder) else { return [] }
        return urls.compactMap { readNote(at: $0) }
    }

    static func readNote(at url: URL) -> Note? {
        guard let contents = coordinatedReadString(at: url) else { return nil }
        let parsed = NoteFile.parse(contents)
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let modified = values?.contentModificationDate ?? Date()
        let fileName = url.lastPathComponent

        return Note(
            fileName: fileName,
            body: parsed.body,
            color: parsed.color ?? StickyColor.derived(from: fileName),
            created: parsed.created ?? values?.creationDate ?? modified,
            modified: modified,
            formatting: parsed.formatting,
            countdown: parsed.countdown,
            passthroughFrontMatter: parsed.passthrough
        )
    }

    private static func coordinatedReadString(at url: URL) -> String? {
        var result: String?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            guard let data = try? Data(contentsOf: readURL) else { return }
            result = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        }
        return result
    }

    // MARK: - Writing

    static func write(_ note: Note, in folder: URL) throws {
        let url = folder.appendingPathComponent(note.fileName)
        let data = Data(NoteFile.serialize(note).utf8)

        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinationError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func delete(_ note: Note, in folder: URL) throws {
        let url = folder.appendingPathComponent(note.fileName)
        var coordinationError: NSError?
        var removeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinationError) { deleteURL in
            do {
                #if os(macOS)
                // Recoverable beats permanent for something a user might
                // delete by accident.
                try FileManager.default.trashItem(at: deleteURL, resultingItemURL: nil)
                #else
                try FileManager.default.removeItem(at: deleteURL)
                #endif
            } catch {
                do {
                    try FileManager.default.removeItem(at: deleteURL)
                } catch {
                    removeError = error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        if let removeError { throw removeError }
    }

    static func rename(_ note: Note, to newFileName: String, in folder: URL) throws {
        guard newFileName != note.fileName else { return }
        let source = folder.appendingPathComponent(note.fileName)
        let destination = folder.appendingPathComponent(newFileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            throw IOError.nameTaken(newFileName)
        }

        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: source,
            options: [.forMoving],
            writingItemAt: destination,
            options: [.forReplacing],
            error: &coordinationError
        ) { sourceURL, destinationURL in
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    static func existingFileNames(in folder: URL) -> Set<String> {
        let urls = (try? listNoteURLs(in: folder)) ?? []
        return Set(urls.map { $0.lastPathComponent })
    }
}
