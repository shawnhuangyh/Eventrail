import Foundation
import OSLog
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Eventrail's own backup file, declared in [Info.plist](Info.plist) so the
    /// system knows the extension belongs to this app: the document picker can
    /// filter for it, and Files names it rather than calling it a document.
    static let eventrailBackup = UTType(exportedAs: "moe.shawn.Eventrail.backup")
}

/// A copy of the library the reader keeps themselves, as a file.
///
/// iCloud Sync answers a different question from this one. Sync keeps the
/// reader's devices agreeing with each other, which means it also carries a
/// deletion across — that is the point of it. A backup is the other half: one
/// moment, held outside the app, that nothing the reader does afterwards can
/// reach. It is also the only copy that survives the app being deleted, or a
/// reader who has switched iCloud off.
///
/// The file is Eventrail's own format, `.eventrail`: an eight-byte signature, a
/// version byte, and the archive as zlib-compressed JSON. The signature is what
/// makes a wrong file wrong *before* anything is decoded, and the extension is
/// what stops a backup from looking like a document any app may open and edit —
/// a hand-edited archive is a library with no way to tell it has been broken.
/// It is a container, not encryption: anyone determined can still read it, and
/// it is the reader's own data.
nonisolated struct LibraryBackup: Sendable {
    /// Marks the file as this app's. Eight bytes, so the check is exact rather
    /// than a guess at what the contents might be.
    private static let signature = Data("EVNTRAIL".utf8)

    /// The shape of what follows the header. Only the container is versioned —
    /// ``LibraryArchive`` already decodes its own older files.
    ///
    /// 2: a tracking record carries the seat and what the ticket cost. A build
    /// that has never heard of either would read the file, drop them, and write
    /// the loss back on the next sync, so it is told to refuse instead.
    ///
    /// 3: an event carries the description, the related links, the hashtags and
    /// the edit history its own page publishes. These are Eventernote's facts
    /// rather than the reader's, so an older build dropping them loses nothing
    /// that cannot be imported again — but the rule is the rule, and a file is
    /// refused by the build that cannot hold all of it.
    ///
    /// 4: a tracking record carries how many lottery entries the reader put
    /// in. The reader's own, like the seat and the cost at 2 — nothing can
    /// import it back — so a build that has never heard of it is told to refuse
    /// the file rather than drop it.
    /// 5: a tracking record carries when each of its five answers was last
    /// written, which is what lets two devices edit different answers between
    /// syncs and keep both. A build that has never heard of those dates would
    /// drop them and go back to settling the whole record at once, so the note
    /// typed on the other device goes missing the next time anything else on
    /// that record is touched.
    ///
    /// 6: the archive carries which Following dates the reader has looked at.
    /// Their own record, and nothing imports it back, so a build that has
    /// never heard of it is told to refuse the file rather than drop it.
    ///
    /// 7: an event carries when its own page was last read, which is what
    /// settles two copies of it in a merge. A build that dropped it would
    /// hand the next merge an undated copy that loses to every dated one.
    ///
    /// 8: a tracking record carries the class of seat the ticket was sold as.
    /// The reader's own, like the seat beside it, so a build that has never
    /// heard of it is told to refuse the file rather than drop it.
    ///
    /// 9: a tracking record's cost carries the currency it was paid in, and
    /// can carry cents. A build that has never heard of either would read a
    /// $49.99 ticket as ¥49 — or fail on the cents — so it is told to refuse
    /// the file instead.
    ///
    /// 10: a tracking record's lottery count is a list of entries — each
    /// round, its results day, the seats asked for and how it went. A build
    /// that has never heard of them would read the list as no lottery at all.
    static let currentFormat: UInt8 = 10

    var app: String
    var created: Date
    var archive: LibraryArchive

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "backup")

    init(archive: LibraryArchive, created: Date = .now) {
        self.app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.created = created
        self.archive = archive
    }

    /// What the file is called when it lands in Files, Mail or anywhere else the
    /// share sheet offers. Dated, because a reader keeping more than one wants
    /// to know which is which without opening either.
    var filename: String {
        let day = created.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Eventrail Backup \(day).eventrail"
    }

    /// Writes the backup where the share sheet can pick it up.
    ///
    /// The temporary directory is the right home for it: the copy that matters
    /// is the one the reader saves out of the share sheet, and leaving a second
    /// one inside the app would be a library the app quietly keeps twice.
    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: filename)
        try packed().write(to: url, options: .atomic)
        return url
    }

    /// Signature, version, then the compressed archive.
    ///
    /// Compressed for the same reason the iCloud payload is — event titles,
    /// venues and notes are mostly Japanese text, which is bulky as UTF-8 and
    /// compresses to roughly a fifth. There is no quota to meet here; it is a
    /// smaller file for nothing.
    private func packed() throws -> Data {
        let json = try JSONEncoder().encode(Contents(app: app, created: created, archive: archive))
        var data = Self.signature
        data.append(Self.currentFormat)
        try data.append((json as NSData).compressed(using: .zlib) as Data)
        return data
    }

    /// Reads a file the reader picked.
    ///
    /// A file chosen from elsewhere on the system is not ours until it proves it
    /// is, so this is the one place that refuses rather than setting the file
    /// aside and starting empty the way ``LibraryFile/load()`` does.
    static func read(at url: URL) throws -> LibraryBackup {
        // A document picked outside the container is handed over scoped, and
        // reading it without asking first returns nothing on a device.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard data.count > signature.count, data.prefix(signature.count) == signature else {
            return try rescued(data)
        }
        let format = data[data.startIndex + signature.count]
        // A file from a later version holds fields this one has never seen, and
        // reading it anyway would drop them silently — then write the loss back
        // on the next sync.
        guard format <= currentFormat else { throw Failure.tooNew }
        do {
            let json = try (data.dropFirst(signature.count + 1) as NSData).decompressed(using: .zlib) as Data
            let contents = try JSONDecoder().decode(Contents.self, from: json)
            return LibraryBackup(contents)
        } catch {
            log.error("A backup carrying our signature would not open: \(error.localizedDescription)")
            throw Failure.damaged
        }
    }

    /// The one file that is not a backup and is still worth reading: the app's
    /// own `library.json`, lifted off a device or out of a computer's backup of
    /// one. It is the same archive without the container, and refusing it would
    /// help nobody.
    private static func rescued(_ data: Data) throws -> LibraryBackup {
        guard let archive = try? JSONDecoder().decode(LibraryArchive.self, from: data) else {
            throw Failure.unreadable
        }
        log.notice("Reading a bare library file as a backup.")
        return LibraryBackup(archive: archive)
    }

    /// What the container holds, once it is open. Kept apart from the type
    /// itself so the signature and version stay out of the JSON, where a reader
    /// of the file could disagree with the header about what it is.
    private struct Contents: Codable {
        var app: String
        var created: Date
        var archive: LibraryArchive
    }

    private init(_ contents: Contents) {
        app = contents.app
        created = contents.created
        archive = contents.archive
    }

    enum Failure: LocalizedError {
        /// Written by a later version of the app, in a shape this one has never
        /// seen.
        case tooNew
        /// Ours by its signature, but the rest of it did not survive whatever
        /// carried it here.
        case damaged
        case unreadable

        var errorDescription: String? {
            switch self {
            case .tooNew:
                String(localized: "That backup was written by a newer version of Eventrail.")
            case .damaged:
                String(localized: "That backup is damaged and could not be opened.")
            case .unreadable:
                String(localized: "That file is not an Eventrail backup.")
            }
        }
    }
}
