import Foundation
import OSLog

/// A value and when it last changed.
///
/// Two devices edit the same library with nothing arbitrating between them, so
/// every record the reader owns carries the moment it was written. A merge takes
/// the newer of two edits rather than the newer of two whole files, which is
/// what keeps a note typed on one device from being erased by an unrelated
/// change made on the other.
nonisolated struct Stamped<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: Value
    var modified: Date

    init(_ value: Value, at modified: Date = .now) {
        self.value = value
        self.modified = modified
    }

    /// The newer of the two. Ties keep `self`, so a merge is stable when two
    /// devices happen to write in the same instant.
    func newer(_ other: Stamped) -> Stamped {
        other.modified > modified ? other : self
    }
}

/// How a linked Eventernote account presents itself.
///
/// Kept with the library rather than fetched when a screen wants it: the Me tab
/// shows the reader their own account every time it opens, and it should not
/// have to reach the network — or show a blank circle until it answers — to do
/// that.
nonisolated struct LinkedProfile: Codable, Hashable, Sendable {
    /// The display name Eventernote prints above the handle.
    var name: String
    var avatarURL: URL?
}

/// Everything the reader has accumulated, as one value: the form a backup is
/// written in, the form an older build's library file was, and the form every
/// merge is made in. The library itself is kept as rows — see
/// ``LibraryDatabase``, which turns the one into the other.
///
/// Imported event facts and the reader's own records are kept apart: ``events``
/// is replaced wholesale by an import, while ``tracking``, ``membership`` and
/// ``favorites`` are only ever written by the reader and are merged, never
/// overwritten.
nonisolated struct LibraryArchive: Codable, Equatable, Sendable {
    /// Every event worth remembering, keyed by Eventernote's id — the library,
    /// plus anything favorited that is not in it.
    var events: [Event.ID: Event] = [:]
    /// Whether each event is in the library. A `false` entry is a tombstone: a
    /// removal has to travel to the other device too, or it would be undone by
    /// the next merge.
    var membership: [Event.ID: Stamped<Bool>] = [:]
    var tracking: [Event.ID: Stamped<Tracking>] = [:]
    var favorites: [Event.ID: Stamped<Bool>] = [:]
    /// The performers the reader follows, keyed by Eventernote's actor id.
    ///
    /// The reader's own record rather than the site's — following here never
    /// touches the favourite list their Eventernote account keeps, which the app
    /// only ever reads. An import seeds this from that list, but only ever adds
    /// to it. So it is stamped and merged like the rest, and unfollowing writes
    /// a `false` instead of dropping the key, for the same reason a removal is a
    /// tombstone: a dropped key would be handed straight back by the next
    /// merge — or, here, by the next import.
    ///
    /// Optional on the outside only so that an archive written before this
    /// existed still decodes, exactly as ``eventernoteAccount`` is.
    var follows: [String: Stamped<Bool>]?
    /// Who each followed actor id is, keyed the same way as ``follows``.
    ///
    /// Following records the reader's decision; this records Eventernote's
    /// facts about the person they decided about — the name, the reading, and
    /// the slug their listing is addressed by. Kept beside the flag rather than
    /// inside it so the flag stays a plain tombstoned `Bool`, and so a merge
    /// treats this the way it treats ``events``: not the reader's record, so no
    /// timestamp, and whichever device read the page has it.
    ///
    /// Without this the Following tab would know only that some actor id
    /// matters and have no way to name it or ask the site for its dates.
    var followedPerformers: [String: PerformerProfile]?
    /// Which dates on the Following tab the reader has looked at, keyed by
    /// event id — see ``FollowingRead``.
    ///
    /// Keyed by events the archive otherwise knows nothing about: a followed
    /// performer's date is not in ``events`` until the reader adds it. So each
    /// record carries its own night, and is pruned by that rather than by
    /// whether anything else points at it.
    ///
    /// Optional on the outside only so that an archive written before this
    /// existed still decodes, exactly as ``follows`` is.
    var followingReads: [Event.ID: Stamped<FollowingRead>]?
    var recentSearches: Stamped<[String]> = Stamped([], at: .distantPast)
    var lastRefreshed: Date?
    /// The Eventernote account the reader imports their history from.
    ///
    /// The reader's own setting, so it is stamped and merges like the rest: a
    /// handle named on the phone should reach the iPad. Unlinking writes a
    /// `nil` *inside* the stamp rather than dropping the record, for the same
    /// reason a removal is a tombstone — losing the record would let the next
    /// merge re-link the account.
    ///
    /// Optional on the outside only so that an archive written before this
    /// existed still decodes. Swift's synthesized decoder does not fall back to
    /// a property's default value, so a new non-optional key here would read as
    /// a corrupt file and empty every library in the field.
    var eventernoteAccount: Stamped<String?>?
    /// How the linked account presents itself: the display name and picture from
    /// its public page.
    ///
    /// These are Eventernote's facts about the account rather than the reader's
    /// own records, so like event facts they carry no timestamp of their own —
    /// they follow whichever link record wins a merge.
    var eventernoteProfile: LinkedProfile?
    /// When the linked account's history was last imported.
    var lastImported: Date?

    /// The library itself, in no particular order — every screen sorts it.
    var libraryEvents: [Event] {
        membership.compactMap { $0.value.value ? events[$0.key] : nil }
    }

    /// Whether the reader has put nothing in here at all.
    ///
    /// Not "the library is empty": a library emptied on purpose still holds the
    /// tombstones that say so, and those are worth syncing. This is the state a
    /// fresh install is in before anything has been read into it.
    var holdsNothing: Bool {
        membership.isEmpty && tracking.isEmpty && favorites.isEmpty
            && (follows?.isEmpty ?? true) && (followingReads?.isEmpty ?? true)
            && eventernoteAccount == nil
            && recentSearches.value.isEmpty
    }

    func isInLibrary(_ id: Event.ID) -> Bool { membership[id]?.value == true }
    func isFavorite(_ id: Event.ID) -> Bool { favorites[id]?.value == true }
    func isFollowing(_ actorID: Int) -> Bool { follows?[String(actorID)]?.value == true }

    /// Whether this copy of a Following row is one the reader has not seen —
    /// never marked, marked unread, or marked when the listing said something
    /// else.
    func isUnread(_ event: Event) -> Bool {
        followingReads?[event.id]?.value.matches(event) != true
    }

    /// Why this copy of a Following row is unread, or nil where it is read.
    func unread(_ event: Event) -> FollowingUnread? {
        guard let read = followingReads?[event.id]?.value, read.fingerprint != nil else { return .new }
        return read.matches(event) ? nil : .updated
    }

    /// The performers the reader follows and the app can still name.
    ///
    /// A follow with no profile beside it is dropped rather than shown as a
    /// blank row: an archive written before profiles were kept holds the id
    /// alone, and an id is not a person.
    var followedProfiles: [PerformerProfile] {
        (follows ?? [:])
            .compactMap { $0.value.value ? followedPerformers?[$0.key] : nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Folds another device's archive into this one.
    ///
    /// The reader's records merge record by record, newest edit winning. Event
    /// facts are not the reader's, so the more complete import wins and no
    /// timestamp is needed for them.
    func merging(_ other: LibraryArchive) -> LibraryArchive {
        var merged = self
        merged.combine(other)
        return merged.pruned()
    }

    /// Folds in a run of other copies at once — every row of the store, or
    /// the records one read of iCloud delivered, each a slice of somebody's
    /// archive — and prunes once at the end rather than after every one.
    ///
    /// Folded in place: a copy of the whole archive per slice made reading a
    /// library of nine hundred rows quadratic.
    func merging(contentsOf others: [LibraryArchive]) -> LibraryArchive {
        var merged = self
        for other in others { merged.combine(other) }
        return merged.pruned()
    }

    private mutating func combine(_ other: LibraryArchive) {
        // Settled against both sides as they stood, before either link moves.
        let account = Self.newer(eventernoteAccount, other.eventernoteAccount)
        let profile = Self.profile(forWinning: account, mine: self, theirs: other)

        for (id, event) in other.events {
            if let mine = events[id] {
                events[id] = Self.settle(mine, event)
            } else {
                events[id] = event
            }
        }

        membership.merge(other.membership) { $0.newer($1) }
        // Alone among the reader's records, a tracking record holds five
        // answers rather than one, so it is settled answer by answer — see
        // ``Stamped/merging(_:)``.
        tracking.merge(other.tracking) { $0.merging($1) }
        favorites.merge(other.favorites) { $0.newer($1) }
        Self.merge(&follows, other.follows) { $0.newer($1) }
        Self.merge(&followingReads, other.followingReads) { $0.newer($1) }
        // Both sides read the same public page, so either is true; this device's
        // copy is kept so the merge stays stable.
        Self.merge(&followedPerformers, other.followedPerformers) { mine, _ in mine }
        recentSearches = recentSearches.newer(other.recentSearches)
        eventernoteAccount = account
        eventernoteProfile = profile
        lastRefreshed = [lastRefreshed, other.lastRefreshed].compactMap { $0 }.max()
        lastImported = [lastImported, other.lastImported].compactMap { $0 }.max()
    }

    /// Merges into an optional dictionary without copying it: taken out of
    /// the property first, so the one being merged into is the only reference.
    /// Left non-nil, as a merge always has.
    private static func merge<Value>(
        _ mine: inout [String: Value]?, _ theirs: [String: Value]?,
        uniquingKeysWith combine: (Value, Value) -> Value
    ) {
        var merged = mine ?? [:]
        mine = nil
        merged.merge(theirs ?? [:], uniquingKeysWith: combine)
        mine = merged
    }

    /// Folds a backup the reader asked to restore into this archive.
    ///
    /// A restore is a merge with one difference, and it is the difference an
    /// import already makes: asking for the backup back outranks the removal
    /// made before it. A record the backup holds and this device says no to —
    /// a tombstoned event, an unfollowed performer, a note cleared by Delete
    /// All — is taken from the backup and stamped as of now, so the merge stops
    /// answering with the removal.
    ///
    /// Only a *no* is overruled. A note this device still holds keeps whichever
    /// copy was typed later, exactly as a sync would settle it, and nothing this
    /// device has that the backup does not is touched. So restoring the wrong
    /// file adds; it never erases.
    func restoring(_ backup: LibraryArchive) -> LibraryArchive {
        let now = Date.now
        var raised = backup

        for (id, record) in backup.membership where record.value && !isInLibrary(id) {
            raised.membership[id] = Stamped(true, at: now)
        }
        for (id, record) in backup.favorites where record.value && !isFavorite(id) {
            raised.favorites[id] = Stamped(true, at: now)
        }
        var follows = raised.follows ?? [:]
        for (key, record) in backup.follows ?? [:] where record.value && self.follows?[key]?.value != true {
            follows[key] = Stamped(true, at: now)
        }
        if !follows.isEmpty { raised.follows = follows }
        var reads = raised.followingReads ?? [:]
        for (id, record) in backup.followingReads ?? [:]
        where record.value.fingerprint != nil && followingReads?[id]?.value.fingerprint == nil {
            reads[id] = Stamped(record.value, at: now)
        }
        if !reads.isEmpty { raised.followingReads = reads }
        for (id, record) in backup.tracking
        where !record.value.isEmpty && (tracking[id]?.value.isEmpty ?? true) {
            raised.tracking[id] = record.restamped(at: now)
        }

        return merging(raised)
    }

    /// The name and picture belonging to the link that won.
    ///
    /// Picked by which account each side holds rather than by recency: the
    /// other device's picture beside a handle it was never taken from would
    /// caption the newly linked account with the old one's face. A device that
    /// has not read the page yet defers to one that has.
    private static func profile(
        forWinning account: Stamped<String?>?, mine: LibraryArchive, theirs: LibraryArchive
    ) -> LinkedProfile? {
        guard let handle = account?.value else { return nil }
        return [mine, theirs]
            .filter { $0.eventernoteAccount?.value == handle }
            .compactMap(\.eventernoteProfile)
            .first
    }

    /// The newer of two records either device may not have at all.
    private static func newer<Value>(
        _ mine: Stamped<Value>?, _ theirs: Stamped<Value>?
    ) -> Stamped<Value>? {
        guard let mine else { return theirs }
        guard let theirs else { return mine }
        return mine.newer(theirs)
    }

    /// Two devices' copies of one event.
    ///
    /// Both are imports of the same public page, so neither is the reader's
    /// and neither needs a timestamp of its own — but the page changes, so
    /// they are not equally true. Where both read the event's own page, the
    /// later read's answers stand and the earlier one only fills what it left
    /// empty; a copy with no ``Event/readAt`` was read before either device
    /// kept one, so it counts as the earlier. Otherwise the one that read the
    /// page carries more of it.
    static func settle(_ mine: Event, _ theirs: Event) -> Event {
        if mine.isDetailed, theirs.isDetailed, mine.readAt != theirs.readAt {
            let mineIsLater = (mine.readAt ?? .distantPast) > (theirs.readAt ?? .distantPast)
            return mineIsLater ? theirs.merging(mine) : mine.merging(theirs)
        }
        return mine.isDetailed ? mine.merging(theirs) : theirs.merging(mine)
    }

    /// Drops what neither device needs to keep agreeing on: events nothing
    /// points at any more, and whatever was only ever about them.
    ///
    /// **Tombstones are never dropped.** A removal forgotten after some months
    /// is a removal a device that slept through those months undoes: it still
    /// holds the old yes, finds no no to lose to, and hands the record back.
    /// Nothing a timestamp can say fixes that — the device has no way of
    /// telling a key that was pruned from one that never existed — and a
    /// tombstone is an id and a date, so keeping every one costs next to
    /// nothing. The same goes for a tracking record cleared on purpose.
    func pruned() -> LibraryArchive {
        var pruned = self

        // Who someone is only matters while they are followed — the same reason
        // an event nothing points at any more is dropped below.
        pruned.followedPerformers = followedPerformers?.filter { pruned.follows?[$0.key]?.value == true }
        // A night that has been is off the Following tab, and so is whether it
        // was read. By the night rather than by the stamp, so both devices
        // drop the same records and neither hands one back. A few days' grace
        // covers a device whose clock or zone disagrees with the hall's.
        let over = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
        pruned.followingReads = followingReads?.filter { $0.value.value.day > over }
        pruned.events = events.filter { pruned.isInLibrary($0.key) || pruned.isFavorite($0.key) }
        return pruned
    }
}

/// The archive cut into records, one per thing the reader keeps a record
/// *about*: an event (whether it is in the library, its tracking, the
/// favourite, the Following read, and the facts that go with it), a performer
/// (the follow and who they are), and one for the settings that belong to the
/// whole library.
///
/// Each record is a slice — an ordinary archive holding only that one thing —
/// so records are folded back together by the same ``merging(_:)`` a whole
/// archive always was, and every rule written there holds record by record
/// without being written twice. It is how the library is stored: one row per
/// record — see ``LibraryEvent``, ``FollowedPerformer`` and
/// ``LibrarySettings``.
nonisolated extension LibraryArchive {
    /// What one record is about.
    enum RecordKey: Hashable, Sendable {
        case event(Event.ID)
        case performer(String)
        case settings
    }

    /// Every record this archive has something to say in.
    var recordKeys: Set<RecordKey> {
        var keys = Set<RecordKey>()
        for id in events.keys { keys.insert(.event(id)) }
        for id in membership.keys { keys.insert(.event(id)) }
        for id in tracking.keys { keys.insert(.event(id)) }
        for id in favorites.keys { keys.insert(.event(id)) }
        for id in (followingReads ?? [:]).keys { keys.insert(.event(id)) }
        for id in (follows ?? [:]).keys { keys.insert(.performer(id)) }
        if slice(for: .settings) != nil { keys.insert(.settings) }
        return keys
    }

    /// The part of this archive one record carries, or nil where it holds
    /// nothing about that key — which is a record to delete rather than one
    /// to save empty.
    func slice(for key: RecordKey) -> LibraryArchive? {
        var slice = LibraryArchive()
        switch key {
        case .event(let id):
            slice.events[id] = events[id]
            slice.membership[id] = membership[id]
            slice.tracking[id] = tracking[id]
            slice.favorites[id] = favorites[id]
            if let read = followingReads?[id] { slice.followingReads = [id: read] }
            let holdsSomething = slice.events[id] != nil || slice.membership[id] != nil
                || slice.tracking[id] != nil || slice.favorites[id] != nil
                || slice.followingReads != nil
            return holdsSomething ? slice : nil
        case .performer(let id):
            guard let follow = follows?[id] else { return nil }
            slice.follows = [id: follow]
            if let profile = followedPerformers?[id] { slice.followedPerformers = [id: profile] }
            return slice
        case .settings:
            slice.recentSearches = recentSearches
            slice.eventernoteAccount = eventernoteAccount
            slice.eventernoteProfile = eventernoteProfile
            slice.lastRefreshed = lastRefreshed
            slice.lastImported = lastImported
            // A fresh install's defaults are not a setting anybody made.
            let holdsSomething = recentSearches.modified != .distantPast
                || eventernoteAccount != nil || eventernoteProfile != nil
                || lastRefreshed != nil || lastImported != nil
            return holdsSomething ? slice : nil
        }
    }
}

/// The JSON file older builds kept the library in, read now only to be moved
/// into ``LibraryDatabase`` — see ``LibraryDatabase/moveIn(from:)`` — and
/// written only by the tests that make one.
nonisolated struct LibraryFile: Sendable {
    static let shared = LibraryFile()

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "library")

    var url: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "library.json")
    }()

    /// What a launch found on disk.
    struct Contents {
        var archive: LibraryArchive
        /// Files set aside because this build could not read them, now or on
        /// an earlier launch. Nothing ever writes over them.
        var unreadable = 0
        /// Files set aside earlier that were read this time and folded back
        /// in. They are the only copy of what they hold until the merged
        /// library is on disk, so they are handed back to be deleted after the
        /// first save that lands (``discard(_:)``) rather than deleted here.
        var recoveredCopies: [URL] = []
        /// Whether a file set aside earlier was read this time and folded back
        /// in — which the store has to write down.
        var recovered: Bool { !recoveredCopies.isEmpty }
        /// Whether the library file is still where it was and could not be
        /// read — the bytes would not open (a device not yet unlocked since it
        /// started, most likely), or would not decode and could not be moved
        /// aside. The empty library that comes back beside it is not the
        /// reader's, and a save would write it over the one that is.
        var isBlocked = false
    }

    /// Reads the library, and never loses one it cannot read.
    ///
    /// An unreadable file used to yield an empty library, and the next save
    /// wrote that empty library over it: one field decoded wrongly, and every
    /// record on a device without sync was gone. So a file that will not
    /// decode is moved aside under a name of its own and the app starts empty
    /// beside it, where nothing it saves can reach it. Every launch tries the
    /// ones set aside again, so a build that has learnt to read them folds
    /// them back in with an ordinary merge — the records written since keep
    /// whichever copy is newer — and deletes them once that merge is saved.
    ///
    /// Where the file cannot even be moved aside, or its bytes cannot be read
    /// at all, it is left where it is and the answer says so
    /// (``Contents/isBlocked``): nothing may be saved over it until a later
    /// read gets through.
    func load() -> Contents {
        var contents = Contents(archive: LibraryArchive())
        do {
            let data = try Data(contentsOf: url)
            if let archive = Self.decode(data) {
                contents.archive = archive
            } else if !setAside() {
                contents.isBlocked = true
            }
        } catch CocoaError.fileReadNoSuchFile {
            // No library yet: a first launch, or one after Delete All's file went.
        } catch {
            Self.log.error("Library file could not be opened: \(error.localizedDescription, privacy: .public)")
            contents.isBlocked = true
        }

        for copy in setAsideCopies() {
            guard let data = try? Data(contentsOf: copy), let archive = Self.decode(data) else {
                contents.unreadable += 1
                continue
            }
            Self.log.notice("Recovered a library file set aside on an earlier launch.")
            contents.archive = contents.archive.merging(archive)
            contents.recoveredCopies.append(copy)
        }
        return contents
    }

    /// Deletes set-aside copies ``load()`` folded back in, once the library
    /// holding them has been saved.
    func discard(_ copies: [URL]) {
        for copy in copies {
            try? FileManager.default.removeItem(at: copy)
        }
    }

    /// Where ``retire()`` leaves the last library this file held.
    var retiredURL: URL {
        url.deletingLastPathComponent().appending(path: "library.pre-swiftdata.json")
    }

    /// Moves the file out of the way once ``LibraryDatabase`` holds what it
    /// did, under a name nothing reads — the last copy of the library in this
    /// format, kept rather than deleted.
    func retire() {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: retiredURL)
        do {
            try FileManager.default.moveItem(at: url, to: retiredURL)
        } catch {
            Self.log.error("Library file could not be moved aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ data: Data) -> LibraryArchive? {
        if let archive = try? JSONDecoder().decode(LibraryArchive.self, from: data) {
            return archive
        }
        // The first shipped format had no timestamps on it. Rather than drop a
        // library that predates syncing, read it and stamp it as it stands.
        if let legacy = try? JSONDecoder().decode(LegacyArchive.self, from: data) {
            log.notice("Migrating a pre-sync library file.")
            return legacy.migrated()
        }
        return nil
    }

    private static let setAsidePrefix = "library.unreadable-"

    /// Whether the unreadable file is out of the way.
    private func setAside() -> Bool {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted))
        let destination = url.deletingLastPathComponent()
            .appending(path: "\(Self.setAsidePrefix)\(stamp)-\(UUID().uuidString.prefix(8)).json")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            Self.log.error("Library file could not be read; set aside as \(destination.lastPathComponent, privacy: .public).")
            return true
        } catch {
            Self.log.error("Library file could not be read or set aside: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func setAsideCopies() -> [URL] {
        let directory = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix(Self.setAsidePrefix) }.sorted()
            .map { directory.appending(path: $0) }
    }

    /// Whether the library landed on disk.
    @discardableResult
    func save(_ archive: LibraryArchive) -> Bool {
        do {
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            return true
        } catch {
            Self.log.error("Library file could not be written: \(error.localizedDescription)")
            return false
        }
    }
}

/// The archive as it was written before records carried timestamps.
private nonisolated struct LegacyArchive: Codable {
    var events: [Event] = []
    var tracking: [Event.ID: Tracking] = [:]
    var favorites: Set<Event.ID> = []
    var recentSearches: [String] = []
    var lastRefreshed: Date?

    func migrated() -> LibraryArchive {
        // Everything predates the first sync, so it loses to any later edit on
        // another device — which is the right way round for a one-device history.
        let when = Date.now
        var archive = LibraryArchive()
        archive.events = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        archive.membership = events.reduce(into: [:]) { $0[$1.id] = Stamped(true, at: when) }
        archive.tracking = tracking.mapValues { Stamped($0, at: when) }
        archive.favorites = favorites.reduce(into: [:]) { $0[$1] = Stamped(true, at: when) }
        archive.recentSearches = Stamped(recentSearches, at: when)
        archive.lastRefreshed = lastRefreshed
        return archive
    }
}
