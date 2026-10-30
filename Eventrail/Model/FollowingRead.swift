import CryptoKit
import Foundation

/// Whether the reader has looked at one date on the Following tab — the
/// record behind the dot on its row.
///
/// The tab is a stream of things somebody else published, and the reader comes
/// back to it to see what is new — so, like a mailbox, a row carries a dot
/// until it has been opened, swiped, or marked in a batch.
///
/// **What is written down is the copy that was read, not only that it was.**
/// A mark keeps a fingerprint of the row as the listing printed it then
/// (``Event/listingFingerprint``). A refresh that brings the row back with a
/// different title, hall, day, times or bill no longer matches it, and the row
/// reads as unread again with nothing having to notice the change as it lands:
/// unread is simply "not the copy the reader saw".
///
/// The reader's own record, so it lives in ``LibraryArchive/followingReads``,
/// stamped and synced like a favourite: a date read on the phone is read on the
/// iPad. Marking a date unread — and Delete All — writes a record with no
/// fingerprint rather than dropping the key, for the reason a removal is a
/// tombstone: a dropped key would let the next merge hand the other device's
/// read straight back. Clear Cache does not reach it; it is not a copy of
/// anything Eventernote holds.
nonisolated struct FollowingRead: Codable, Hashable, Sendable {
    /// The fingerprint of the copy that was read, or nil where the date was
    /// marked unread again.
    var fingerprint: String?
    /// The event the record is about, which is what decides when it can go:
    /// see ``LibraryArchive/pruned()``.
    var day: Date

    /// Why `event` is unread, read against `read` — the mark kept for it, or
    /// none — or nil where it is read. With `copy`, the copy that mark was
    /// taken of (``ReadCopies``), an Updated date says what changed.
    static func unread(_ event: Event, read: FollowingRead?, copy: ListingCopy? = nil) -> FollowingUnread? {
        guard let read, read.fingerprint != nil else { return .new }
        return read.matches(event) ? nil : .updated(copy.flatMap { ListingChanges(from: $0, to: event) })
    }

    func matches(_ event: Event) -> Bool {
        guard let fingerprint else { return false }
        if fingerprint == event.listingFingerprint { return true }
        // A mark written before the fingerprint read the wall clock still
        // counts for the copy it was taken of, rather than every date the
        // reader had looked at coming back Updated at once. That copy was the
        // Following row as the listing printed it, read on Tokyo time; a row
        // since re-read on its hall's clock abroad is read back onto Tokyo's
        // first, or every instant in it differs from the one that was marked.
        //
        // And that copy had every time on the event's own day, before a clock
        // earlier than the one before it was read as the next morning, so the
        // mark is also held against the times put back on that day.
        let tokyo = event.timeZone == Event.publishedZone ? event : event.published(in: Event.publishedZone)
        return [tokyo, tokyo.onItsOwnDay].contains { fingerprint == $0.instantFingerprint }
    }
}

/// Why a Following date is unread, which is what its row's tag says.
nonisolated enum FollowingUnread: Hashable, Sendable {
    /// Never looked at — or marked unread again, which throws away the copy
    /// that was read and so leaves nothing to say it changed from.
    case new
    /// Looked at, and the listing has printed something different since —
    /// with what, where this device still holds the copy that was looked at
    /// (``ReadCopies``).
    case updated(ListingChanges?)

    /// What changed, where it is known.
    var changes: ListingChanges? {
        if case .updated(let changes) = self { changes } else { nil }
    }
}

nonisolated extension Event {
    /// What a listing row says about the event, boiled down to something that
    /// changes exactly when the row does — see ``FollowingRead``.
    ///
    /// Only what a performer's listing prints: the title, the hall, the day,
    /// whatever times it carries and the bill. Not the head count, which moves
    /// with every member who lists the event, and not the flyer, whose URL the
    /// host keeps when the picture is replaced. Hashed so a mark is a short
    /// string rather than a copy of the row, and hashed with SHA-256 rather
    /// than `hashValue`, which is seeded afresh on every launch — and on every
    /// device, which a synced mark has to agree across.
    ///
    /// The times are taken as the page prints them — the wall clock in the
    /// event's own zone — rather than as instants. The Following tab's copy
    /// of an event abroad stays on Tokyo time while the library's is re-read in
    /// the hall's zone (``Event/published(in:)``), and the two tabs share one
    /// mark: as instants the same unchanged row would read Updated on
    /// whichever tab had not marked it.
    ///
    /// The day once and each time as a clock alone, since that is all the page
    /// prints: which morning an after-midnight time falls on is this app's
    /// reading of it (see ``inOrder(_:_:_:)``), and a better reading must not
    /// make an unchanged row read Updated.
    ///
    /// Taken over ``ListingCopy``, which keeps the same fields whole, so the
    /// two cannot come to disagree about what a change is.
    var listingFingerprint: String { ListingCopy(self).fingerprint }

    /// Every time put back on the event's own day, as every copy was read
    /// before an after-midnight clock was taken to be the next morning. Only
    /// for recognising a mark taken then — see ``FollowingRead/matches(_:)``.
    var onItsOwnDay: Event {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        func onDay(_ time: Date?) -> Date? {
            guard let time else { return nil }
            var parts = calendar.dateComponents([.hour, .minute], from: time)
            parts.year = day.year
            parts.month = day.month
            parts.day = day.day
            return calendar.date(from: parts)
        }
        var event = self
        event.doorsOpen = onDay(doorsOpen)
        event.startsAt = onDay(startsAt)
        event.endsAt = onDay(endsAt)
        return event
    }

    /// The fingerprint as it was taken before it read the wall clock, over the
    /// instants themselves. Only ever compared against, never written.
    var instantFingerprint: String {
        let times = [date, doorsOpen, startsAt, endsAt]
            .map { $0.map { String(Int($0.timeIntervalSince1970)) } ?? "-" }
        return Self.digest([title, venue] + times + performers.map(\.name))
    }

    fileprivate static func digest(_ fields: [String]) -> String {
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1F}").utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// What a listing row prints about an event — the fields
/// ``Event/listingFingerprint`` is taken over, kept whole rather than hashed,
/// so a row that comes back changed can say what changed (``ListingChanges``).
///
/// The day and times as the page prints them, a written date and clocks with
/// no zone, for the reason the fingerprint reads them so: the Following tab's
/// copy of an event abroad is on Tokyo time and the library's on its hall's,
/// and the two are one copy.
nonisolated struct ListingCopy: Codable, Hashable, Sendable {
    /// A time as the page prints it, with no day: which morning a time after
    /// midnight falls on is this app's reading (``Event/inOrder(_:_:_:)``).
    struct Clock: Codable, Hashable, Sendable {
        var hour: Int
        var minute: Int
    }

    var title: String
    var venue: String
    var day: CalendarDay
    var doorsOpen: Clock?
    var startsAt: Clock?
    var endsAt: Clock?
    /// The bill's names, in the listing's order.
    var performers: [String]
    /// The clock the copy was read on. Not anything the page prints, so not
    /// in the ``fingerprint``: only for putting what a hall since replaced
    /// printed back on that hall's clock (``ListingChanges``). Nil in a copy
    /// kept before it was.
    var zone: TimeZone?

    init(_ event: Event) {
        let calendar = Calendar.gregorian(in: event.timeZone)
        func clock(_ time: Date?) -> Clock? {
            time.map { time in
                let parts = calendar.dateComponents([.hour, .minute], from: time)
                return Clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        }
        title = event.title
        venue = event.venue
        day = CalendarDay(event.date, in: calendar)
        doorsOpen = clock(event.doorsOpen)
        startsAt = clock(event.startsAt)
        endsAt = clock(event.endsAt)
        performers = event.performers.map(\.name)
        zone = event.timeZone
    }

    /// Whether the two print the same, whichever clock each was read on.
    func printsTheSame(as other: ListingCopy) -> Bool {
        var other = other
        other.zone = zone
        return self == other
    }

    /// See ``Event/listingFingerprint``. Spelled as it always was — the day
    /// and the clocks unpadded — or every mark already written would stop
    /// matching its copy, and every date read so far would come back Updated.
    var fingerprint: String {
        let printedDay = "\(day.year)-\(day.month)-\(day.day)"
        let times = [doorsOpen, startsAt, endsAt].map { clock in
            clock.map { "\($0.hour):\($0.minute)" } ?? "-"
        }
        return Event.digest([title, venue, printedDay] + times + performers)
    }
}

/// What a listing row prints differently now from the copy the reader read:
/// what an Updated row prints anew, and its sheet's What Changed card.
nonisolated struct ListingChanges: Hashable, Sendable {
    /// One thing the row says differently, in the order ``changes`` lists them.
    enum Change: Hashable, Sendable {
        case day
        case time(Stop)
        case venue(was: String, now: String)
        /// Names billed now and not then, and then and not now, each in the
        /// order its own copy bills them.
        case performers(added: [String], removed: [String])
        /// The same names, billed in another order — which the fingerprint
        /// counts, so an Updated row has to say so.
        case billingOrder
        case title(was: String, now: String)
    }

    /// The times a page prints, in running order.
    enum Stop: Hashable, Sendable, CaseIterable {
        case doorsOpen, startsAt, endsAt
    }

    /// The day first, then the times, the hall and the bill: what decides
    /// whether the reader can still be there ahead of what only renames it.
    let changes: [Change]
    /// The event with the day and times the reader read, on the clock of the
    /// hall they were read at. Only ever printed — see ``shown(on:)``.
    private let before: Event
    private let after: Event

    /// Nil where `read` is the copy `event` prints — which an Updated date
    /// never is.
    init?(from read: ListingCopy, to event: Event) {
        let now = ListingCopy(event)
        var changes: [Change] = []
        if read.day != now.day { changes.append(.day) }
        if read.doorsOpen != now.doorsOpen { changes.append(.time(.doorsOpen)) }
        if read.startsAt != now.startsAt { changes.append(.time(.startsAt)) }
        if read.endsAt != now.endsAt { changes.append(.time(.endsAt)) }
        if read.venue != now.venue { changes.append(.venue(was: read.venue, now: now.venue)) }
        let added = now.performers.filter { !read.performers.contains($0) }
        let removed = read.performers.filter { !now.performers.contains($0) }
        if !added.isEmpty || !removed.isEmpty {
            changes.append(.performers(added: added, removed: removed))
        } else if read.performers != now.performers {
            changes.append(.billingOrder)
        }
        if read.title != now.title { changes.append(.title(was: read.title, now: now.title)) }
        guard !changes.isEmpty else { return nil }
        self.changes = changes

        // The copy read, put back on its hall's clock as the page would have
        // printed it: its day's midnight, and each time on that day, read in
        // running order. The same hall's is the clock the event is on now,
        // which may know it better than the copy did — a Following row is on
        // Tokyo time until the hall is placed. A hall since replaced keeps
        // the clock it was read on, or a Tokyo 18:00 replaced by a Taipei
        // 19:00 would read 18:00 in Taipei, an hour late on the reader's.
        let zone = read.venue == now.venue ? event.timeZone : read.zone ?? event.timeZone
        let calendar = Calendar.gregorian(in: zone)
        func on(_ clock: ListingCopy.Clock?) -> Date? {
            clock.flatMap { clock in
                calendar.date(from: DateComponents(year: read.day.year, month: read.day.month, day: read.day.day,
                                                   hour: clock.hour, minute: clock.minute))
            }
        }
        var before = event
        before.timeZone = zone
        if read.day != now.day || zone != event.timeZone { before.date = read.day.date(in: calendar) }
        (before.doorsOpen, before.startsAt, before.endsAt) = Event.inOrder(
            on(read.doorsOpen), on(read.startsAt), on(read.endsAt))
        self.before = before
        after = event
    }

    /// The event as read and as printed now, each on `clock`: for their days
    /// and times alone, since the one read keeps today's title, hall and bill
    /// (those are in ``changes``).
    func shown(on clock: TimeDisplay) -> (was: Event, now: Event) {
        (before.shown(on: clock), after.shown(on: clock))
    }

    /// Whether the day, or one of the times, is among ``changes``.
    func changed(_ change: Change) -> Bool { changes.contains(change) }

    var venueChanged: Bool {
        changes.contains { if case .venue = $0 { true } else { false } }
    }

    var titleChanged: Bool {
        changes.contains { if case .title = $0 { true } else { false } }
    }

    /// The names billed now and not when it was read.
    var added: [String] {
        for case let .performers(added, _) in changes { return added }
        return []
    }
}
