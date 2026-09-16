import Foundation
import OSLog

/// Everything the reader has accumulated, in the form it is written to disk.
///
/// Imported event fields sit beside the reader's own records here, but they are
/// kept apart everywhere they are written: an import replaces ``events`` and
/// never touches ``tracking`` or ``favorites``.
nonisolated struct LibraryArchive: Codable, Sendable {
    var events: [Event] = []
    var tracking: [Event.ID: Tracking] = [:]
    var favorites: Set<Event.ID> = []
    var recentSearches: [String] = []
    var lastRefreshed: Date?
}

/// Keeps the archive in a JSON file inside the app's container.
///
/// Not SwiftData: the project defers that schema until it is settled, and this
/// keeps what the reader adds across launches in the meantime without
/// committing to a store. Nothing written here leaves the device.
nonisolated struct LibraryFile: Sendable {
    static let shared = LibraryFile()

    private static let log = Logger(subsystem: "com.shawnhuang.Eventrail", category: "library")

    var url: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "library.json")
    }()

    /// An unreadable file yields an empty library rather than a crash: the
    /// reader can always add events again, and a refusal to launch helps nobody.
    func load() -> LibraryArchive {
        guard let data = try? Data(contentsOf: url) else { return LibraryArchive() }
        do {
            return try JSONDecoder().decode(LibraryArchive.self, from: data)
        } catch {
            Self.log.error("Library file could not be read: \(error.localizedDescription)")
            return LibraryArchive()
        }
    }

    func save(_ archive: LibraryArchive) {
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.log.error("Library file could not be written: \(error.localizedDescription)")
        }
    }
}
