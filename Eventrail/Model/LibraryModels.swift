import Foundation
import SwiftData

// The library as it is stored, and synced by SwiftData through the reader's
// private CloudKit database with nothing on top: each row is one CloudKit
// record, and two devices' copies of a record are settled the way CloudKit
// settles them — the copy that reached it last stands, whole.
//
// That rule is only safe where a record is written by nothing but the change
// it records, so the rows are cut by who writes them rather than by what they
// are about:
//
// - ``LibraryEntry`` is the reader's: whether an event is in the library,
//   whether it is hearted, and what they wrote on it. Written only when the
//   reader changes one of those, or an import of their account adds the event.
// - ``LibraryEvent`` is Eventernote's: the event's facts, a copy of its page,
//   rewritten by every read of that page on any device. Never the reader's
//   answer to anything, so a copy sent by a device that was behind costs at
//   most an older copy of a public page, which the next read mends.
// - ``FollowingReadMark`` is a Following date's read, written as the reader
//   opens a row — often, and on whichever device is in their hand.
// - ``LibraryLottery`` is one lottery round the reader entered for an event,
//   so two devices each adding a round while apart both keep theirs.
//
// CloudKit's rules shape every property here: each one has a default or is
// optional, and nothing is `.unique` — two devices each writing a row for the
// same event is expected, and ``LibraryDatabase/deduplicate(in:)`` keeps one,
// the same one on every device. Two entries are the exception to keeping one
// whole: the one kept first takes whatever the other gave later
// (``LibraryEntry/absorb(_:)``), since each was written by a device that had
// never seen the other.

/// Eventernote's facts about one event — a copy of its page, kept so the
/// library can be drawn and synced without asking the site again.
///
/// Anything may write it: an import, a read of the page, a hall's clock once
/// it is known. So it holds nothing the reader decided — that is
/// ``LibraryEntry`` — and it is never emptied: an event taken out of the
/// library keeps its facts, because a record emptied on one device lands
/// empty on every other.
@Model
final class LibraryEvent {
    /// Which of two rows for one event is kept, where they tie.
    var uid: UUID = UUID()
    /// Eventernote's id for the event, and what two rows for it share.
    var eventID: String = ""

    // MARK: Eventernote's facts

    /// Whether the columns below hold the event's facts. Builds before
    /// ``LibraryEntry`` set it false to drop the facts of an event nothing
    /// kept, and left the columns where they were — see ``facts``.
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

    // MARK: What builds before ``LibraryEntry`` kept here

    // Read once, by ``LibraryDatabase/adoptLegacyRecords(in:)``, and never
    // written again. Kept rather than dropped, since CloudKit's schema only
    // ever grows.
    var inLibrary: Bool = false
    var inLibraryChanged: Date?
    var isFavorite: Bool = false
    var favoriteChanged: Date?
    /// ``TicketStatus``'s raw value.
    var ticket: String = TicketStatus.none.rawValue
    var seat: String = ""
    var cost: Int?
    var lotteryEntries: Int?
    var note: String = ""
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

/// Everything the reader owns about one event: whether it is in the library,
/// whether it is hearted, and the ticket, seat, seat class, cost, lotteries
/// and note they wrote on it.
///
/// One record, written only when one of those changes — by the reader, or by
/// an import of their account adding the event — and never by a read of the
/// event's page, which is ``LibraryEvent``'s. So a device that is behind can
/// only send back an answer the reader gave on it, never one it merely held.
///
/// A removal is `inLibrary` false rather than a deleted row, so it reaches
/// every device, and the row is never deleted: a note outlives its event.
///
/// Carries a copy of the event as it stood when the reader last wrote here
/// (``kept``), so it can be listed the moment it lands — CloudKit sends an
/// entry and the facts beside it as two records, in whichever order it likes,
/// and an entry drawn from its facts alone was invisible on a device the facts
/// had not reached yet.
///
/// Each of its three parts — whether it is in the library, the heart, the
/// tracking record — is dated on its own (``changed(_:)``), because two
/// entries for one event are two devices' answers and neither saw the other:
/// a device whose import added the event before the entry with the reader's
/// note had reached it wrote a second entry saying only "in the library", and
/// keeping the newer entry whole dropped the note, the ticket and the heart on
/// every device.
@Model
final class LibraryEntry {
    /// Which of two entries for one event is kept, where they tie.
    var uid: UUID = UUID()
    /// Eventernote's id for the event, and what two entries for it share.
    var eventID: String = ""
    var inLibrary: Bool = false
    var isFavorite: Bool = false
    /// ``TicketStatus``'s raw value, so a status added later reads back as
    /// none rather than failing.
    var ticket: String = TicketStatus.none.rawValue
    var seat: String = ""
    var seatClass: String = ""
    /// What the ticket cost in whole yen, as builds before costs had a
    /// currency kept it. Read only where ``price`` and ``costHundredths`` are
    /// empty, and emptied as the cost is next changed — see ``tracking``.
    var cost: Int?
    /// ``Tracking/cost`` in hundredths of its currency, as builds before
    /// ``price`` kept it: ¥9,900 is 990000 and $49.99 is 4999. Read with
    /// ``costCurrency`` only where ``price`` is empty, and emptied with it as
    /// the cost is next changed.
    var costHundredths: Int?
    /// ``Tracking/currency``, beside ``costHundredths``: empty for yen written
    /// before costs had one.
    var costCurrency: String = ""
    /// ``Tracking/cost`` and ``Tracking/currency`` as one answer: the amount
    /// as typed, and its currency after a space — "9900 JPY", "49.99 USD" —
    /// or the amount alone for yen written before costs had a currency.
    /// Empty for not written down.
    ///
    /// One column rather than two, because CloudKit may settle two columns of
    /// one record apart: a device that changed only the currency and another
    /// that changed only the amount, apart, could leave an amount and a
    /// currency nobody wrote together — ¥9,900 read as NT$9,900.
    var price: String = ""
    /// How many lotteries were entered, as builds before each was an entry
    /// kept it. Read only where ``lotteries`` holds nothing and the event has
    /// no ``LibraryLottery`` rows, as one entry applied for that many times.
    var lotteryEntries: Int?
    /// ``Tracking/lotteries`` as JSON, as builds before ``LibraryLottery``
    /// kept them — see ``LotteryEntry/columnText(of:)``. Read only where the
    /// event has no rows of its own yet, and never written again: the first
    /// change to the list writes it into rows (``LibraryDatabase/writeLotteries``).
    var lotteries: String = ""
    var note: String = ""
    /// When the reader last changed any of it — which of two entries for one
    /// event is kept. Written to the millisecond, as CloudKit keeps it — see
    /// ``Foundation/Date/toTheMillisecond``.
    var modified: Date = Date.distantPast
    /// When each part was last given, to the millisecond — see
    /// ``changed(_:)``. All three nil on an entry written before parts were
    /// dated.
    var inLibraryChanged: Date?
    var favoriteChanged: Date?
    var trackingChanged: Date?
    /// The event as it stood when the reader last wrote here, as JSON.
    var snapshot: Data?

    init(eventID: String) {
        self.eventID = eventID
    }
}

/// One lottery round the reader entered for an event — a ``LotteryEntry``,
/// in a record of its own.
///
/// Its own record rather than part of the event's ``LibraryEntry``, because
/// CloudKit settles a record whole: kept as one list on the entry, two devices
/// each adding a round while apart left whichever reached iCloud last, and the
/// other round was gone. One round a record, each device's round is a record
/// of its own and both stand; the same round changed on both is settled as
/// any record is, by which reached iCloud last.
///
/// A round taken out is ``isRemoved`` rather than a deleted row, so it reaches
/// every device, as a removal from the library does.
@Model
final class LibraryLottery {
    /// Which of two rows for one round is kept, where they tie.
    var uid: UUID = UUID()
    /// Eventernote's id for the event the round was entered for.
    var eventID: String = ""
    /// ``LotteryEntry/id``, as text: what two rows for one round share, with
    /// ``eventID`` — a round carried over from before entries has the same id
    /// in every event.
    var entryID: String = ""
    /// The round as JSON, its keys sorted — see ``LotteryEntry/rowText(of:)``.
    /// Text, so the Console shows what a record holds. Emptied as it is taken
    /// out.
    var entry: String = ""
    var isRemoved: Bool = false
    /// Where it stood in the list as the reader last wrote it — the order two
    /// rounds of one kind are listed in (``Tracking/lotteriesInOrder``).
    var position: Int = 0
    /// When it was last written, to the millisecond — which of two rows for
    /// one round is kept.
    var modified: Date = Date.distantPast

    init(eventID: String, entryID: String) {
        self.eventID = eventID
        self.entryID = entryID
    }
}

/// Whether one event was in the library, as the builds between
/// ``LibraryEvent``'s own column and ``LibraryEntry`` kept it. Read once, by
/// ``LibraryDatabase/adoptLegacyRecords(in:)``, and never written again.
@Model
final class LibraryMembership {
    var uid: UUID = UUID()
    var eventID: String = ""
    var inLibrary: Bool = false
    var changed: Date?

    init(eventID: String) {
        self.eventID = eventID
    }
}

/// Whether the reader has read one date on the Following tab, or My Events —
/// see ``FollowingRead``.
///
/// A record of its own: a row is marked read as it is opened, on whichever
/// device is in the reader's hand, and a record written that often must carry
/// nothing but itself.
@Model
final class FollowingReadMark {
    /// Which of two marks for one date is kept, where they tie.
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

// MARK: - Rows as values

extension LibraryEvent {
    /// The event as Eventernote published it, or nil where this row holds no
    /// facts.
    ///
    /// Read wherever the columns hold a title, whatever ``hasFacts`` says: the
    /// builds before ``LibraryEntry`` cleared the flag to drop an event nothing
    /// kept and left its columns in place, so an event taken out on one of
    /// them and put back on this one still has something to show.
    var facts: Event? {
        guard hasFacts || !title.isEmpty else { return nil }
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

    /// Writes `event` into the columns, touching only the ones that move.
    func write(_ event: Event) {
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

    /// Which of two rows for one event to keep: the one holding facts, then
    /// the one read from the event's own page, then the later read — and the
    /// lower `uid` where nothing else tells them apart, so every device keeps
    /// the same one.
    static func isPreferred(_ row: LibraryEvent, over other: LibraryEvent) -> Bool {
        let mine = row.facts, theirs = other.facts
        if (mine != nil) != (theirs != nil) { return mine != nil }
        if let mine, let theirs {
            if mine.isDetailed != theirs.isDetailed { return mine.isDetailed }
            let read = (mine.readAt ?? .distantPast).toTheMillisecond
            let otherRead = (theirs.readAt ?? .distantPast).toTheMillisecond
            if read != otherRead { return read > otherRead }
        }
        return row.uid.uuidString < other.uid.uuidString
    }

    /// What a build before ``LibraryEntry`` kept on this row — whether the
    /// event was in the library, the heart, the tracking record and the
    /// Following read — as an archive, for
    /// ``LibraryDatabase/adoptLegacyRecords(in:)``.
    var legacyRecords: LibraryArchive {
        var archive = LibraryArchive()
        if let inLibraryChanged { archive.membership[eventID] = Stamped(inLibrary, at: inLibraryChanged) }
        if let favoriteChanged { archive.favorites[eventID] = Stamped(isFavorite, at: favoriteChanged) }
        if let trackingChanged {
            var edits: [Tracking.Field: Date] = [:]
            for (field, date) in trackingEdits {
                if let field = Tracking.Field(rawValue: field) { edits[field] = date }
            }
            var record = Tracking(ticket: TicketStatus(rawValue: ticket) ?? .none, seat: seat,
                                  cost: cost.map { Decimal($0) },
                                  lotteries: LotteryEntry.carriedOver(count: lotteryEntries),
                                  note: note, edits: edits)
            record.foldLegacyTicket()
            archive.tracking[eventID] = Stamped(record, at: trackingChanged)
        }
        if let readChanged {
            archive.followingReads = [eventID: Stamped(FollowingRead(fingerprint: readFingerprint,
                                                                     day: readDay ?? .distantPast),
                                                       at: readChanged)]
        }
        return archive
    }
}

extension LibraryEntry {
    /// What the reader has said about the event, apart from when.
    struct Answers: Equatable {
        var inLibrary = false
        var isFavorite = false
        /// With no ``Tracking/edits``: an entry is settled whole, so nothing
        /// here is older than the entry around it.
        var tracking = Tracking()

        /// Whether the reader has said nothing — the state of an event they
        /// never touched.
        var isEmpty: Bool { !inLibrary && !isFavorite && tracking.isEmpty }

        /// The parts in which these answers say something other than `other`.
        func parts(differingFrom other: Answers) -> [Part] {
            Part.allCases.filter { part in
                switch part {
                case .inLibrary: inLibrary != other.inLibrary
                case .favorite: isFavorite != other.isFavorite
                case .tracking: tracking != other.tracking
                }
            }
        }

        /// Takes `part` as `other` answers it.
        mutating func take(_ part: Part, from other: Answers) {
            switch part {
            case .inLibrary: inLibrary = other.inLibrary
            case .favorite: isFavorite = other.isFavorite
            case .tracking: tracking = other.tracking
            }
        }
    }

    /// The three answers an entry holds, each dated on its own.
    enum Part: CaseIterable {
        case inLibrary, favorite, tracking
    }

    var answers: Answers {
        Answers(inLibrary: inLibrary, isFavorite: isFavorite, tracking: tracking)
    }

    /// When this entry last gave `part`, or `.distantPast` where it never did.
    ///
    /// An entry written before parts were dated says only when it was last
    /// written as a whole, so each of its parts is dated then — the way two
    /// such entries were always settled.
    func changed(_ part: Part) -> Date {
        guard isDatedByPart else { return modified }
        let given = switch part {
        case .inLibrary: inLibraryChanged
        case .favorite: favoriteChanged
        case .tracking: trackingChanged
        }
        return given ?? .distantPast
    }

    private var isDatedByPart: Bool {
        inLibraryChanged != nil || favoriteChanged != nil || trackingChanged != nil
    }

    /// Writes `answers`, dating each part `dates` names as it says. A part it
    /// does not name keeps its answer's date, so the caller names only the
    /// parts the reader — or the archive being taken in — actually gave.
    ///
    /// Leaves ``modified`` to the caller.
    func give(_ answers: Answers, dated dates: [Part: Date]) {
        // An entry an older build wrote is dated part by part first, so the
        // parts left alone keep the date the whole entry had rather than
        // reading as never given once another part is dated.
        if !dates.isEmpty, !isDatedByPart, modified != .distantPast {
            for part in Part.allCases { setChanged(part, to: modified) }
        }
        update(\.inLibrary, to: answers.inLibrary)
        update(\.isFavorite, to: answers.isFavorite)
        tracking = answers.tracking
        for (part, when) in dates { setChanged(part, to: when.toTheMillisecond) }
    }

    private func setChanged(_ part: Part, to when: Date) {
        switch part {
        case .inLibrary: update(\.inLibraryChanged, to: when)
        case .favorite: update(\.favoriteChanged, to: when)
        case .tracking: update(\.trackingChanged, to: when)
        }
    }

    /// Takes from a second entry for the same event every part it gave later
    /// than this one — what ``LibraryDatabase/deduplicate(in:)`` does before
    /// deleting it.
    ///
    /// Two entries for one event were written by two devices that had not seen
    /// each other's, so a part one of them never gave says nothing against the
    /// other. Settled part by part, the same way on every device, so they all
    /// end on the same answers; a tie keeps this one's.
    func absorb(_ other: LibraryEntry) {
        var answers = self.answers
        var dates: [Part: Date] = [:]
        for part in Part.allCases
        where other.changed(part).toTheMillisecond > changed(part).toTheMillisecond {
            answers.take(part, from: other.answers)
            dates[part] = other.changed(part)
        }
        guard !dates.isEmpty else { return }
        give(answers, dated: dates)
        // The list an older build kept on the entry is not written by
        // ``tracking`` any more — rows are — so it comes across as it stands,
        // for an event whose list has not been moved into rows yet.
        if dates[.tracking] != nil {
            update(\.lotteries, to: other.lotteries)
            update(\.lotteryEntries, to: other.lotteryEntries)
            update(\.ticket, to: other.ticket)
        }
        update(\.modified, to: max(modified, other.modified.toTheMillisecond))
        if snapshot == nil { update(\.snapshot, to: other.snapshot) }
    }

    /// What the reader wrote on the event, its lotteries the list this entry
    /// kept before ``LibraryLottery`` — what an event with no rows of its own
    /// yet reads. Every other event reads ``tracking(lotteries:)``.
    ///
    /// Set, it writes everything but the lotteries, which are rows of their
    /// own (``LibraryDatabase/writeLotteries``): the old list stays as it is
    /// until the first change to it moves it into rows.
    var tracking: Tracking {
        get { tracking(lotteries: nil) }
        set {
            update(\.seat, to: newValue.seat)
            update(\.seatClass, to: newValue.seatClass)
            // Written only where the cost itself changed: a note edited beside
            // a cost an older build wrote must not rewrite the cost, and race
            // another device's change to it.
            let held = tracking
            if newValue.cost != held.cost || newValue.currency != held.currency {
                update(\.price, to: Self.priceText(of: newValue.cost, in: newValue.currency))
                // The cost now lives in the column above, so the old ones are
                // emptied rather than left to be read back over an emptied cost.
                update(\.costHundredths, to: nil)
                update(\.costCurrency, to: "")
                update(\.cost, to: nil)
            }
            update(\.note, to: newValue.note)
        }
    }

    /// What the reader wrote on the event, with `lotteries` — its rows' list
    /// (``LibraryDatabase/tracking(of:rows:)``) — in place of the old list
    /// this entry kept, where there is one.
    ///
    /// The old ticket column goes with the old list: an event with rows holds
    /// what it said among them already, folded in as the list was moved.
    func tracking(lotteries rows: [LotteryEntry]?) -> Tracking {
        let (amount, currency) = cost(in: price)
            ?? (costHundredths.map { Decimal($0) / 100 } ?? cost.map { Decimal($0) }, costCurrency)
        var record = Tracking(seat: seat, seatClass: seatClass, cost: amount, note: note, currency: currency)
        if let rows {
            record.lotteries = rows
        } else {
            record.ticket = TicketStatus(rawValue: ticket) ?? .none
            record.lotteries = LotteryEntry.entries(inColumn: lotteries)
                ?? LotteryEntry.carriedOver(count: lotteryEntries)
            // A ticket an older build marked bought reads as a won entry, and
            // is written so with the first change to the list.
            record.foldLegacyTicket()
        }
        return record
    }

    /// A cost as ``price`` holds it: the amount, and its currency after a
    /// space where it has one. Empty for none.
    static func priceText(of amount: Decimal?, in currency: String) -> String {
        guard let amount else { return "" }
        return currency.isEmpty ? "\(amount)" : "\(amount) \(currency)"
    }

    /// The amount and currency ``price`` holds, or nil where it is empty — or
    /// holds nothing this build can read, which reads as the older columns.
    private func cost(in text: String) -> (Decimal?, String)? {
        guard !text.isEmpty else { return nil }
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let amount = parts.first.flatMap({ Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) })
        else { return nil }
        return (amount, parts.count > 1 ? String(parts[1]) : "")
    }

    /// The event as it stood when the reader last wrote here — what the entry
    /// is drawn from until its ``LibraryEvent`` arrives.
    var kept: Event? {
        get { snapshot.flatMap { try? JSONDecoder().decode(Event.self, from: $0) } }
        set {
            let encoder = JSONEncoder()
            // The same event always encodes the same, so an unchanged one is
            // not a change to send.
            encoder.outputFormatting = .sortedKeys
            update(\.snapshot, to: newValue.flatMap { try? encoder.encode($0) })
        }
    }

    /// Which of two entries for one event to keep: the one the reader wrote
    /// last, and the lower `uid` where they wrote both at once — so every
    /// device keeps the same one.
    static func isPreferred(_ entry: LibraryEntry, over other: LibraryEntry) -> Bool {
        let written = entry.modified.toTheMillisecond, otherWritten = other.modified.toTheMillisecond
        if written != otherWritten { return written > otherWritten }
        return entry.uid.uuidString < other.uid.uuidString
    }
}

extension LibraryLottery {
    /// The round this row holds, or nil where it was taken out — or holds
    /// none this build can read.
    var lottery: LotteryEntry? {
        isRemoved ? nil : LotteryEntry.entry(inRow: entry)
    }

    /// Writes `lottery` — nil takes the round out — at `position`, dated
    /// `when`, touching only what moves. Answers whether anything did.
    ///
    /// A round this build cannot read back whole — one a later build wrote —
    /// is written over only where the reader changed that round: moved, or
    /// another round beside it changed, it keeps what this build would drop.
    @discardableResult
    func write(_ lottery: LotteryEntry?, at position: Int, dated when: Date) -> Bool {
        guard let lottery else {
            guard !isRemoved else { return false }
            update(\.isRemoved, to: true)
            update(\.entry, to: "")
            update(\.modified, to: when.toTheMillisecond)
            return true
        }
        var moved = false
        if isRemoved || self.lottery != lottery {
            update(\.isRemoved, to: false)
            update(\.entry, to: LotteryEntry.rowText(of: lottery))
            moved = true
        }
        if self.position != position {
            update(\.position, to: position)
            moved = true
        }
        if moved { update(\.modified, to: when.toTheMillisecond) }
        return moved
    }

    /// The row written last, and the lower `uid` on a tie.
    static func isPreferred(_ row: LibraryLottery, over other: LibraryLottery) -> Bool {
        let written = row.modified.toTheMillisecond, otherWritten = other.modified.toTheMillisecond
        if written != otherWritten { return written > otherWritten }
        return row.uid.uuidString < other.uid.uuidString
    }
}

extension FollowingReadMark {
    var read: Stamped<FollowingRead>? {
        get { changed.map { Stamped(FollowingRead(fingerprint: fingerprint, day: day), at: $0) } }
        set {
            update(\.fingerprint, to: newValue?.value.fingerprint)
            update(\.day, to: newValue?.value.day ?? .distantPast)
            update(\.changed, to: newValue?.modified)
        }
    }

    /// The mark written last, and the lower `uid` on a tie.
    static func isPreferred(_ mark: FollowingReadMark, over other: FollowingReadMark) -> Bool {
        let written = (mark.changed ?? .distantPast).toTheMillisecond
        let otherWritten = (other.changed ?? .distantPast).toTheMillisecond
        if written != otherWritten { return written > otherWritten }
        return mark.uid.uuidString < other.uid.uuidString
    }
}

extension FollowedPerformer {
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

    /// The follow written last, and the lower `uid` on a tie.
    static func isPreferred(_ row: FollowedPerformer, over other: FollowedPerformer) -> Bool {
        let written = (row.followChanged ?? .distantPast).toTheMillisecond
        let otherWritten = (other.followChanged ?? .distantPast).toTheMillisecond
        if written != otherWritten { return written > otherWritten }
        return row.uid.uuidString < other.uid.uuidString
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

    /// The row the other rows are folded into: the lowest `uid`, on every
    /// device.
    static func isPreferred(_ row: LibrarySettings, over other: LibrarySettings) -> Bool {
        row.uid.uuidString < other.uid.uuidString
    }

    /// Takes from another row whatever it wrote later.
    ///
    /// Unlike the other rows, two of these are expected rather than rare: a
    /// device writes one the first time the reader searches or links an
    /// account, whether or not the other device's has reached it yet. Keeping
    /// either whole would drop what only the other held — the linked account
    /// on one, the searches on the other — so the two are folded field by
    /// field.
    func absorb(_ other: LibrarySettings) {
        if other.recentSearchesChanged > recentSearchesChanged { searches = other.searches }
        if (other.accountChanged ?? .distantPast) > (accountChanged ?? .distantPast) {
            eventernoteAccount = other.eventernoteAccount
            eventernoteProfile = other.eventernoteProfile
        } else if eventernoteProfile == nil, other.account == account {
            eventernoteProfile = other.eventernoteProfile
        }
        update(\.lastRefreshed, to: [lastRefreshed, other.lastRefreshed].compactMap { $0 }.max())
        update(\.lastImported, to: [lastImported, other.lastImported].compactMap { $0 }.max())
    }
}

// MARK: - Dates as CloudKit keeps them

nonisolated extension Date {
    /// This moment cut to the millisecond, as CloudKit keeps a date.
    ///
    /// What every date that decides which of two rows is kept is compared
    /// by, and what ``LibraryEntry/modified`` is written as. A record this
    /// device wrote comes back from CloudKit a fraction older than it went, so
    /// compared exactly, two devices holding the same two rows could each
    /// find the other's the older — and each delete the one the other kept.
    var toTheMillisecond: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1000).rounded(.down) / 1000)
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
extension LibraryEntry: ChangeAvoidingModel {}
extension FollowedPerformer: ChangeAvoidingModel {}
extension LibrarySettings: ChangeAvoidingModel {}
extension FollowingReadMark: ChangeAvoidingModel {}
extension LibraryLottery: ChangeAvoidingModel {}
