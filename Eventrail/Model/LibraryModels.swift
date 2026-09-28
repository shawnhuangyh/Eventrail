import Foundation
import SwiftData

// The library as it is stored: one row per record the reader keeps, cut the
// way ``LibraryArchive/RecordKey`` cuts an archive, and synced by SwiftData
// through the reader's private CloudKit database.
//
// CloudKit's rules shape every property here: each one has a default or is
// optional, and nothing is `.unique` — two devices each writing a row for the
// same event is expected, and ``LibraryDatabase/deduplicate(in:)`` folds them
// back into one. `uid` is what decides which row survives, the same one on
// every device.
//
// Each of the reader's records carries the moment it changed beside it, so a
// removal is a value rather than a missing row: `inLibrary` false with a date
// is the tombstone ``LibraryArchive`` has always kept, and an import or a
// restore raises it by the same rules.

/// One event the reader has a record about: its facts, whether it is
/// favourited, and what the reader wrote on it. Whether it is in the library
/// and whether its Following date was read are records of their own — see
/// ``LibraryMembership`` and ``FollowingReadMark``.
@Model
final class LibraryEvent {
    /// Which of two rows for one event is kept — the lowest, on every device.
    var uid: UUID = UUID()
    /// Eventernote's id for the event, and what two rows for it share.
    var eventID: String = ""

    // MARK: Eventernote's facts

    /// Whether the columns below hold the event's facts. False for a row that
    /// only records a Following date's read, whose facts the library never
    /// kept.
    var hasFacts: Bool = false
    var title: String = ""
    var artist: String = ""
    var venue: String = ""
    var venueDetail: String?
    var venueAddress: String?
    var placeID: Int?
    var date: Date = Date.distantPast
    var doorsOpen: Date?
    var startsAt: Date?
    var endsAt: Date?
    /// The hall's clock — see ``Event/timeZone``.
    var timeZoneID: String = "Asia/Tokyo"
    var listedAttendees: Int?
    var performers: [Performer] = []
    var summary: String?
    var relatedLinks: [URL]?
    var hashtags: [Hashtag]?
    var editedBy: String?
    var editedAt: Date?
    var imageURL: URL?
    var sourceURL: URL?
    var isDetailed: Bool = false
    var detailFormat: Int?
    var readAt: Date?

    // MARK: The reader's records

    /// Whether the event is in the library, as builds before
    /// ``LibraryMembership`` kept it — and still read it. Mirrored here by
    /// every change made on this device (``mirror(_:)``), read back only where
    /// an older build wrote something newer (``legacyMembership``), and never
    /// the answer: a copy of this row sent by a device that had not yet heard
    /// of a removal carries the old yes.
    var inLibrary: Bool = false
    /// When ``inLibrary`` was last written; nil where it never was.
    var inLibraryChanged: Date?
    var isFavorite: Bool = false
    var favoriteChanged: Date?
    /// ``TicketStatus``'s raw value, so a status added later reads back as
    /// none rather than failing.
    var ticket: String = TicketStatus.none.rawValue
    var seat: String = ""
    var cost: Int?
    var lotteryEntries: Int?
    var note: String = ""
    var trackingChanged: Date?
    /// ``Tracking/edits``, keyed by ``Tracking/Field``'s raw value.
    var trackingEdits: [String: Date] = [:]

    // MARK: Where builds before ``FollowingReadMark`` kept the Following read

    // Read and never written: a device still on one of those builds writes
    // here, and ``LibraryDatabase/adoptLegacyReads(in:)`` takes what it wrote
    // into the marks. Kept rather than dropped, since CloudKit's schema only
    // ever grows and an older build still reads them.
    var readFingerprint: String?
    var readDay: Date?
    var readChanged: Date?

    init(eventID: String) {
        self.eventID = eventID
    }
}

/// Whether one event is in the library — a `false` with a date is the
/// tombstone a removal leaves.
///
/// A record of its own rather than two columns on the event's row, where
/// builds before this kept it. CloudKit keeps one record per row and settles
/// two devices' copies of it whole, so anything written to the event's row —
/// a read of its page, a note, a ticket, a heart — was sent with whether the
/// event is in the library as that device last knew it, and a device that had
/// not yet heard of a removal put the event back everywhere. Apart, only
/// adding or removing the event says whether it is kept.
@Model
final class LibraryMembership {
    /// Which of two records for one event is kept — the lowest, on every
    /// device.
    var uid: UUID = UUID()
    /// Eventernote's id for the event, and what two records for it share.
    var eventID: String = ""
    var inLibrary: Bool = false
    /// When ``inLibrary`` was last written; nil where it never was.
    var changed: Date?

    init(eventID: String) {
        self.eventID = eventID
    }
}

/// Whether the reader has read one date on the Following tab, or My Events —
/// see ``FollowingRead``.
///
/// A record of its own rather than three columns on the event's row, where
/// builds before this kept it. CloudKit keeps one record per row and settles
/// two devices' copies of it whole, so marking a date read sent the event's
/// entire row, its membership included — and a device that had not yet heard
/// the event was removed put it back in the library everywhere by opening it.
/// Apart, a read carries nothing but itself.
@Model
final class FollowingReadMark {
    /// Which of two marks for one date is kept — the lowest, on every device.
    var uid: UUID = UUID()
    /// Eventernote's id for the event, and what two marks for it share.
    var eventID: String = ""
    var fingerprint: String?
    var day: Date = Date.distantPast
    /// When the mark was last written; nil where it never was.
    var changed: Date?

    init(eventID: String) {
        self.eventID = eventID
    }
}

/// One performer the reader follows, or once did.
@Model
final class FollowedPerformer {
    var uid: UUID = UUID()
    /// Eventernote's actor id, and what two rows for the performer share.
    var actorID: Int = 0
    var isFollowing: Bool = false
    var followChanged: Date?
    /// Whether the columns below say who they are — see
    /// ``LibraryArchive/followedPerformers``.
    var hasProfile: Bool = false
    var name: String = ""
    var reading: String?
    var fanCount: Int?
    var slug: String = ""

    init(actorID: Int) {
        self.actorID = actorID
    }
}

/// What belongs to the whole library rather than to one event: the linked
/// account, recent searches and when the account was last read. One row,
/// however many devices wrote one.
@Model
final class LibrarySettings {
    var uid: UUID = UUID()
    var recentSearches: [String] = []
    var recentSearchesChanged: Date = Date.distantPast
    /// The linked Eventernote handle; nil with a date is an unlink.
    var account: String?
    var accountChanged: Date?
    var profileName: String?
    var profileAvatarURL: URL?
    var lastRefreshed: Date?
    var lastImported: Date?

    init() {}
}

// MARK: - Rows as records

extension LibraryEvent {
    var key: LibraryArchive.RecordKey { .event(eventID) }

    /// The event as Eventernote published it, or nil where this row holds no
    /// facts.
    var facts: Event? {
        get {
            guard hasFacts else { return nil }
            return Event(
                id: eventID, title: title, artist: artist, venue: venue,
                venueDetail: venueDetail, venueAddress: venueAddress, placeID: placeID,
                date: date, doorsOpen: doorsOpen, startsAt: startsAt, endsAt: endsAt,
                timeZone: TimeZone(identifier: timeZoneID) ?? Event.publishedZone,
                listedAttendees: listedAttendees, performers: performers,
                summary: summary, relatedLinks: relatedLinks, hashtags: hashtags,
                editedBy: editedBy, editedAt: editedAt, imageURL: imageURL,
                sourceURL: sourceURL ?? EventernoteClient.site.appending(path: "events/\(eventID)"),
                isDetailed: isDetailed, detailFormat: detailFormat, readAt: readAt
            )
        }
        set {
            // Left in the columns when the facts go: nothing reads them past
            // `hasFacts`, and emptying them would be one more change to send.
            guard let event = newValue else { return update(\.hasFacts, to: false) }
            update(\.hasFacts, to: true)
            update(\.title, to: event.title)
            update(\.artist, to: event.artist)
            update(\.venue, to: event.venue)
            update(\.venueDetail, to: event.venueDetail)
            update(\.venueAddress, to: event.venueAddress)
            update(\.placeID, to: event.placeID)
            update(\.date, to: event.date)
            update(\.doorsOpen, to: event.doorsOpen)
            update(\.startsAt, to: event.startsAt)
            update(\.endsAt, to: event.endsAt)
            update(\.timeZoneID, to: event.timeZone.identifier)
            update(\.listedAttendees, to: event.listedAttendees)
            update(\.performers, to: event.performers)
            update(\.summary, to: event.summary)
            update(\.relatedLinks, to: event.relatedLinks)
            update(\.hashtags, to: event.hashtags)
            update(\.editedBy, to: event.editedBy)
            update(\.editedAt, to: event.editedAt)
            update(\.imageURL, to: event.imageURL)
            update(\.sourceURL, to: event.sourceURL)
            update(\.isDetailed, to: event.isDetailed)
            update(\.detailFormat, to: event.detailFormat)
            update(\.readAt, to: event.readAt)
        }
    }

    /// Keeps the columns an older build reads membership from in step with
    /// a change made here, so a device not yet updated still sees it.
    func mirror(_ membership: Stamped<Bool>) {
        update(\.inLibrary, to: membership.value)
        update(\.inLibraryChanged, to: membership.modified)
    }

    var favorite: Stamped<Bool>? {
        get { favoriteChanged.map { Stamped(isFavorite, at: $0) } }
        set {
            update(\.isFavorite, to: newValue?.value ?? false)
            update(\.favoriteChanged, to: newValue?.modified)
        }
    }

    var tracking: Stamped<Tracking>? {
        get {
            trackingChanged.map { changed in
                var edits: [Tracking.Field: Date] = [:]
                for (field, date) in trackingEdits {
                    if let field = Tracking.Field(rawValue: field) { edits[field] = date }
                }
                let record = Tracking(ticket: TicketStatus(rawValue: ticket) ?? .none, seat: seat,
                                      cost: cost, lotteryEntries: lotteryEntries, note: note,
                                      edits: edits)
                return Stamped(record, at: changed)
            }
        }
        set {
            let record = newValue?.value ?? Tracking()
            update(\.ticket, to: record.ticket.rawValue)
            update(\.seat, to: record.seat)
            update(\.cost, to: record.cost)
            update(\.lotteryEntries, to: record.lotteryEntries)
            update(\.note, to: record.note)
            update(\.trackingEdits, to: Dictionary(uniqueKeysWithValues: record.edits.map { ($0.key.rawValue, $0.value) }))
            update(\.trackingChanged, to: newValue?.modified)
        }
    }

    /// This row as the part of an archive it stands for, or nil where it
    /// records nothing at all.
    var slice: LibraryArchive? {
        var archive = LibraryArchive()
        archive.events[eventID] = facts
        archive.tracking[eventID] = tracking
        archive.favorites[eventID] = favorite
        return archive.slice(for: key)
    }

    /// Takes on what `archive` says about this row's event. Whether it is in
    /// the library and whether its date was read are not this row's to take —
    /// see ``LibraryMembership`` and ``FollowingReadMark``.
    func take(_ archive: LibraryArchive) {
        facts = archive.events[eventID]
        tracking = archive.tracking[eventID]
        favorite = archive.favorites[eventID]
    }

    /// The Following read a build before ``FollowingReadMark`` wrote on this
    /// row, as the part of an archive it stands for.
    var legacyRead: LibraryArchive? {
        guard let readChanged else { return nil }
        var archive = LibraryArchive()
        archive.followingReads = [eventID: Stamped(FollowingRead(fingerprint: readFingerprint, day: readDay ?? .distantPast),
                                                   at: readChanged)]
        return archive.slice(for: .read(eventID))
    }

    /// Whether the event is in the library as this row's own columns say —
    /// what an older build wrote, or what this device mirrored there — as the
    /// part of an archive it stands for.
    var legacyMembership: LibraryArchive? {
        guard let inLibraryChanged else { return nil }
        var archive = LibraryArchive()
        archive.membership[eventID] = Stamped(inLibrary, at: inLibraryChanged)
        return archive.slice(for: .membership(eventID))
    }

    /// Takes the newest of what this row and its twins keep for an older
    /// build — whether the event is in the library, and whether its date was
    /// read — before the twins are folded away (``LibraryDatabase/deduplicate(in:)``).
    ///
    /// The fold merges the rows' records, and neither is in a record any more,
    /// so a surviving row this build wrote — hearted, with nothing mirrored on
    /// it — would otherwise tell a device still on an older build that the
    /// event its own twin kept is out of the library.
    func keepLegacyRecords(of twins: [LibraryEvent]) {
        var membership = self
        var read = self
        for twin in twins {
            if let changed = twin.inLibraryChanged, changed > (membership.inLibraryChanged ?? .distantPast) {
                membership = twin
            }
            if let changed = twin.readChanged, changed > (read.readChanged ?? .distantPast) {
                read = twin
            }
        }
        if let changed = membership.inLibraryChanged {
            mirror(Stamped(membership.inLibrary, at: changed))
        }
        update(\.readFingerprint, to: read.readFingerprint)
        update(\.readDay, to: read.readDay)
        update(\.readChanged, to: read.readChanged)
    }

    /// Whether this row still carries something an older build reads from it:
    /// whether the event is in the library, or a read whose night pruning has
    /// not reached. Such a row is not deleted for having nothing else to say,
    /// or the device still on that build would lose it and send the row
    /// straight back — the same reason a tombstone was never pruned.
    var holdsLegacyRecord: Bool {
        inLibraryChanged != nil || legacyRead?.pruned().followingReads?.isEmpty == false
    }
}

extension LibraryMembership {
    var key: LibraryArchive.RecordKey { .membership(eventID) }

    var membership: Stamped<Bool>? {
        get { changed.map { Stamped(inLibrary, at: $0) } }
        set {
            update(\.inLibrary, to: newValue?.value ?? false)
            update(\.changed, to: newValue?.modified)
        }
    }

    var slice: LibraryArchive? {
        var archive = LibraryArchive()
        archive.membership[eventID] = membership
        return archive.slice(for: key)
    }

    func take(_ archive: LibraryArchive) {
        membership = archive.membership[eventID]
    }
}

extension FollowingReadMark {
    var key: LibraryArchive.RecordKey { .read(eventID) }

    var read: Stamped<FollowingRead>? {
        get { changed.map { Stamped(FollowingRead(fingerprint: fingerprint, day: day), at: $0) } }
        set {
            update(\.fingerprint, to: newValue?.value.fingerprint)
            update(\.day, to: newValue?.value.day ?? .distantPast)
            update(\.changed, to: newValue?.modified)
        }
    }

    var slice: LibraryArchive? {
        var archive = LibraryArchive()
        if let read { archive.followingReads = [eventID: read] }
        return archive.slice(for: key)
    }

    func take(_ archive: LibraryArchive) {
        read = archive.followingReads?[eventID]
    }
}

extension FollowedPerformer {
    var key: LibraryArchive.RecordKey { .performer(String(actorID)) }

    var follow: Stamped<Bool>? {
        get { followChanged.map { Stamped(isFollowing, at: $0) } }
        set {
            update(\.isFollowing, to: newValue?.value ?? false)
            update(\.followChanged, to: newValue?.modified)
        }
    }

    var profile: PerformerProfile? {
        get {
            hasProfile
                ? PerformerProfile(id: actorID, name: name, reading: reading, fanCount: fanCount, slug: slug)
                : nil
        }
        set {
            guard let profile = newValue else { return update(\.hasProfile, to: false) }
            update(\.hasProfile, to: true)
            update(\.name, to: profile.name)
            update(\.reading, to: profile.reading)
            update(\.fanCount, to: profile.fanCount)
            update(\.slug, to: profile.slug)
        }
    }

    var slice: LibraryArchive? {
        var archive = LibraryArchive()
        let id = String(actorID)
        if let follow { archive.follows = [id: follow] }
        if let profile { archive.followedPerformers = [id: profile] }
        return archive.slice(for: key)
    }

    func take(_ archive: LibraryArchive) {
        let id = String(actorID)
        follow = archive.follows?[id]
        profile = archive.followedPerformers?[id]
    }
}

extension LibrarySettings {
    var searches: Stamped<[String]> {
        get { Stamped(recentSearches, at: recentSearchesChanged) }
        set {
            update(\.recentSearches, to: newValue.value)
            update(\.recentSearchesChanged, to: newValue.modified)
        }
    }

    var eventernoteAccount: Stamped<String?>? {
        get { accountChanged.map { Stamped(account, at: $0) } }
        set {
            update(\.account, to: newValue?.value ?? nil)
            update(\.accountChanged, to: newValue?.modified)
        }
    }

    var eventernoteProfile: LinkedProfile? {
        get { profileName.map { LinkedProfile(name: $0, avatarURL: profileAvatarURL) } }
        set {
            update(\.profileName, to: newValue?.name)
            update(\.profileAvatarURL, to: newValue?.avatarURL)
        }
    }

    var slice: LibraryArchive? {
        var archive = LibraryArchive()
        archive.recentSearches = searches
        archive.eventernoteAccount = eventernoteAccount
        archive.eventernoteProfile = eventernoteProfile
        archive.lastRefreshed = lastRefreshed
        archive.lastImported = lastImported
        return archive.slice(for: .settings)
    }

    func take(_ archive: LibraryArchive) {
        searches = archive.recentSearches
        eventernoteAccount = archive.eventernoteAccount
        eventernoteProfile = archive.eventernoteProfile
        update(\.lastRefreshed, to: archive.lastRefreshed)
        update(\.lastImported, to: archive.lastImported)
    }
}

// MARK: - Writing only what changed

/// Every row written is a record CloudKit sends again, so a column is only
/// assigned where its value actually moves.
protocol ChangeAvoidingModel: AnyObject {}

nonisolated extension ChangeAvoidingModel {
    fileprivate func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

extension LibraryEvent: ChangeAvoidingModel {}
extension FollowedPerformer: ChangeAvoidingModel {}
extension LibrarySettings: ChangeAvoidingModel {}
extension FollowingReadMark: ChangeAvoidingModel {}
extension LibraryMembership: ChangeAvoidingModel {}
