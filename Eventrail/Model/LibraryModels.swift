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
//
// What the reader writes themselves — the tracking answers, the linked
// account, their searches — is `.allowsCloudEncryption`: CloudKit keeps it in
// the record's encrypted values, as the sync before SwiftData kept its whole
// payload. A field's encryption is fixed once CloudKit's schema has it, so a
// field added here that the reader writes should be marked before it first
// syncs, not after.

/// One event the reader has a record about: in the library, favourited,
/// written on, or read on the Following tab.
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

    var inLibrary: Bool = false
    /// When ``inLibrary`` was last written; nil where it never was.
    var inLibraryChanged: Date?
    var isFavorite: Bool = false
    var favoriteChanged: Date?
    /// ``TicketStatus``'s raw value, so a status added later reads back as
    /// none rather than failing.
    @Attribute(.allowsCloudEncryption) var ticket: String = TicketStatus.none.rawValue
    @Attribute(.allowsCloudEncryption) var seat: String = ""
    @Attribute(.allowsCloudEncryption) var cost: Int?
    @Attribute(.allowsCloudEncryption) var lotteryEntries: Int?
    @Attribute(.allowsCloudEncryption) var note: String = ""
    var trackingChanged: Date?
    /// ``Tracking/edits``, keyed by ``Tracking/Field``'s raw value.
    var trackingEdits: [String: Date] = [:]
    var readFingerprint: String?
    var readDay: Date?
    var readChanged: Date?

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
    @Attribute(.allowsCloudEncryption) var recentSearches: [String] = []
    var recentSearchesChanged: Date = Date.distantPast
    /// The linked Eventernote handle; nil with a date is an unlink.
    @Attribute(.allowsCloudEncryption) var account: String?
    var accountChanged: Date?
    @Attribute(.allowsCloudEncryption) var profileName: String?
    @Attribute(.allowsCloudEncryption) var profileAvatarURL: URL?
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

    var membership: Stamped<Bool>? {
        get { inLibraryChanged.map { Stamped(inLibrary, at: $0) } }
        set {
            update(\.inLibrary, to: newValue?.value ?? false)
            update(\.inLibraryChanged, to: newValue?.modified)
        }
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

    var followingRead: Stamped<FollowingRead>? {
        get {
            readChanged.map { Stamped(FollowingRead(fingerprint: readFingerprint, day: readDay ?? .distantPast), at: $0) }
        }
        set {
            update(\.readFingerprint, to: newValue?.value.fingerprint)
            update(\.readDay, to: newValue?.value.day)
            update(\.readChanged, to: newValue?.modified)
        }
    }

    /// This row as the part of an archive it stands for, or nil where it
    /// records nothing at all.
    var slice: LibraryArchive? {
        var archive = LibraryArchive()
        archive.events[eventID] = facts
        archive.membership[eventID] = membership
        archive.tracking[eventID] = tracking
        archive.favorites[eventID] = favorite
        if let followingRead { archive.followingReads = [eventID: followingRead] }
        return archive.slice(for: key)
    }

    /// Takes on what `archive` says about this row's event.
    func take(_ archive: LibraryArchive) {
        facts = archive.events[eventID]
        membership = archive.membership[eventID]
        tracking = archive.tracking[eventID]
        favorite = archive.favorites[eventID]
        followingRead = archive.followingReads?[eventID]
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
