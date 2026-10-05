import SwiftUI

/// Whether the reader said they held a ticket, as records from before the
/// lottery entries said it — see ``Tracking/ticket``.
nonisolated enum TicketStatus: String, CaseIterable, Hashable, Codable {
    case none, purchased
}

/// The seat classes common enough to be a chip on the ticket sheet.
///
/// A menu rather than the whole of the answer: ``Tracking/seatClass`` is text,
/// and these are what a Japanese promoter prints on nearly every ticket.
///
/// Written down as the ticket prints it — the raw value — and shown in the
/// reader's language, so a class chosen on a phone set to English reads back
/// as 一般席 on an iPad set to Japanese, and one typed before the chips were
/// translated is still recognised.
nonisolated enum SeatClass: String, CaseIterable, Identifiable {
    case s = "S席"
    case a = "A席"
    case general = "一般席"

    var id: String { rawValue }

    /// What the chip and the seat tile call it.
    var label: LocalizedStringKey {
        switch self {
        case .s: "S Seat"
        case .a: "A Seat"
        case .general: "General Seat"
        }
    }

    /// ``label`` as a string, to tell whether it reads any differently from
    /// the class as the ticket prints it — S Seat beside S席, and nothing
    /// beside it in Japanese.
    var name: String {
        switch self {
        case .s: String(localized: "S Seat")
        case .a: String(localized: "A Seat")
        case .general: String(localized: "General Seat")
        }
    }

    /// What the chip's badge says: the letter where the class has one, and a
    /// letter for the one that has none in English.
    var badge: Text {
        switch self {
        case .s: Text(verbatim: "S")
        case .a: Text(verbatim: "A")
        case .general: Text("G", comment: "The badge on the chip for the general seat class, 一般席.")
        }
    }

    /// Where a class stands, highest first: S, A, General, then any class the
    /// chips do not offer.
    static func order(of seatClass: String) -> Int {
        allCases.firstIndex { $0.rawValue == seatClass } ?? allCases.count
    }
}

/// The reader's private record for one event.
///
/// Every field here belongs to the reader and to this app. A refresh of the
/// public page never touches them.
///
/// There were two more once — how interested the reader was, and whether they
/// turned up. Both asked the library a question it already answers. An event is
/// in the library because the reader means to go, so "interested" was a second
/// word for being there at all; and an event in the library that has already
/// happened is one they went to, so attendance was a second word for the date.
/// What is left is the ticket: how the reader tried for one and whether they
/// got it, which the library cannot say by itself, and once they did, the
/// things about it worth keeping after the event is over — and whatever the
/// reader wants to write down.
///
/// Dropping the two needed no migration: a record written before this still
/// carries `interest` and `attendance`, and a decoder ignores keys it has no
/// property for. Adding one needs none either, but only because the decoder
/// below reads every key as optional — a synthesized one treats a key an older
/// record does not carry as a corrupt file, and takes the whole library with
/// it. So an older record simply has no seat, no seat class, no cost and no
/// lottery: nothing written down — and a cost with no currency, which is yen.
nonisolated struct Tracking: Hashable, Codable {
    /// Whether the reader held a ticket, as they once said it with a pair of
    /// chips. The entries say it now (``hasTicket``: a lottery won, a
    /// first-come round got), so this is only ever read: a record holding
    /// `.purchased` has it folded into its entries as it is read
    /// (``foldLegacyTicket()``) and is none from then on. Kept, and still an
    /// answer in ``Field``, because archives carry it.
    var ticket: TicketStatus = .none
    /// Where the reader sat, as the ticket prints it.
    ///
    /// One free line rather than a row and a number in fields of their own: a
    /// hall prints 1階 L列 23番, an arena prints A5ブロック 12番, and a live
    /// house prints an entry number and no seat at all. Anything that insisted
    /// on a shape would be wrong for two of the three.
    var seat: String = ""
    /// Which class of seat the ticket was sold as — S席, A席, 一般席 — as the
    /// promoter printed it.
    ///
    /// Beside ``seat`` rather than inside it: the seat is where the reader
    /// sat, and this is what they paid for, which the ticket prints on a line
    /// of its own and the sheet asks with a row of chips. Kept as text rather
    /// than as a case, so a class the chips do not offer reads back as itself.
    /// Empty is "not written down".
    var seatClass: String = ""
    /// What the ticket cost, in ``currency``, exactly as the reader typed it.
    ///
    /// Nil is "not written down", which is not the same as free — a lottery
    /// seat or an invite really does cost nothing, and it is worth being able
    /// to record that.
    ///
    /// A `Decimal`, because a ticket abroad is sold for 49.99. A record written
    /// before then holds a whole number of yen here, which reads back as the
    /// same number — see ``currency``.
    var cost: Decimal?
    /// Every round of the sale the reader tried for — the round, how many
    /// times they applied in it, the day the results come out, the seats
    /// asked for in order of preference and how it went — in the order they
    /// were added.
    ///
    /// A count once, which said how hard the reader tried and nothing about
    /// how it went. A record written then reads back as one entry applied for
    /// that many times (``LotteryEntry/carriedOver(count:)``), so the count is
    /// still what the applications add up to.
    ///
    /// One answer, settled whole: an entry is not dated on its own, so two
    /// devices adding different entries between syncs keep the later list,
    /// as two devices editing the note do.
    var lotteries: [LotteryEntry] = []
    var note: String = ""
    /// The ISO 4217 code ``cost`` is in — JPY, TWD, USD — chosen beside it on
    /// the ticket sheet.
    ///
    /// Empty on a record written before a cost had a currency, when every cost
    /// was yen — which is what ``price`` reads it as — and wherever no cost is
    /// written: a currency is half of the answer "what it cost", and means
    /// nothing without the amount. So it is not an answer of its own in
    /// ``Field`` but rides with ``cost``, settled and dated as one: ¥9,900 and
    /// $99 are two answers, and a merge taking the amount from one device and
    /// the currency from the other would make a third nobody gave.
    var currency: String = ""
    /// When each answer above was last written, where that is older than the
    /// record holding it.
    ///
    /// Not one of the reader's answers but the app's note about them, and it
    /// is what lets a merge settle this record an answer at a time — see
    /// ``Stamped/merging(_:)``. A record carries one stamp for six answers,
    /// so a cost typed on the iPad after a note was typed on the phone would
    /// otherwise carry the iPad's whole record — its older copy of the note
    /// included — over the newer note. That is the erasure ``Stamped`` exists
    /// to stop, one level down.
    ///
    /// A field missing from here is exactly as old as its record. That is what
    /// an archive written before this existed says about all six, and what an
    /// answer written in the same breath as its record says about itself, so
    /// only an answer *older* than the record around it is written down and a
    /// record edited once carries nothing here at all.
    var edits: [Field: Date] = [:]

    /// The six answers a record holds, named so that a merge can take them
    /// one at a time.
    ///
    /// Named by their raw value in an archive's ``edits``, so a raw value
    /// never changes: ``lotteries`` keeps the name of the count it replaced,
    /// and the date the count was written is the date of the list it reads
    /// back as.
    ///
    /// A field added to this struct belongs here too, and the switches in
    /// ``sameAnswer(for:as:)`` and ``take(_:from:)`` will not compile until it
    /// is — which is the point of naming them rather than reaching for a
    /// key path. The one exception is ``currency``, which is part of the
    /// ``cost`` answer rather than an answer of its own.
    nonisolated enum Field: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
        case ticket, seat, seatClass, cost, note
        case lotteries = "lotteryEntries"
    }

    /// Whether the reader has written anything down here.
    ///
    /// Read off the answers alone: ``edits`` says when they were written, and
    /// a record whose every answer has since been cleared is empty however
    /// recently that happened.
    var isEmpty: Bool {
        ticket == .none && seat.isEmpty && seatClass.isEmpty && cost == nil
            && lotteries.isEmpty && note.isEmpty
    }

    /// What the ticket cost and what in, or nil where nothing is written.
    ///
    /// The one place an empty ``currency`` is read as yen: everything that
    /// reads a cost back reads it through here.
    var price: Money? {
        cost.map { Money(amount: $0, currency: currency.isEmpty ? Currencies.yen : currency) }
    }
}

nonisolated extension Tracking {
    /// Whether two records give the same answer to one question.
    fileprivate func sameAnswer(for field: Field, as other: Tracking) -> Bool {
        switch field {
        case .ticket: ticket == other.ticket
        case .seat: seat == other.seat
        case .seatClass: seatClass == other.seatClass
        case .cost: cost == other.cost && currency == other.currency
        case .lotteries: lotteries == other.lotteries
        case .note: note == other.note
        }
    }

    /// Takes one answer from another record and leaves the other five alone.
    fileprivate mutating func take(_ field: Field, from other: Tracking) {
        switch field {
        case .ticket: ticket = other.ticket
        case .seat: seat = other.seat
        case .seatClass: seatClass = other.seatClass
        case .cost:
            cost = other.cost
            currency = other.currency
        case .lotteries: lotteries = other.lotteries
        case .note: note = other.note
        }
    }

    /// This record with every answer `edited` gives differently from
    /// `original` taken from it — what a sheet holding a copy changed, laid
    /// over the record as it stands now. An answer that arrived from another
    /// device while the copy was open keeps what it arrived with, unless the
    /// reader changed that one too.
    func applying(changesFrom original: Tracking, to edited: Tracking) -> Tracking {
        var record = self
        for field in Field.allCases where !edited.sameAnswer(for: field, as: original) {
            record.take(field, from: edited)
        }
        return record
    }
}

/// The reader's record, settled one answer at a time.
///
/// ``Stamped`` settles everything else record by record, which is right where
/// a record holds one answer: a membership, a favourite, a follow. This one
/// holds six, and the device that wrote last had almost certainly written
/// about one of them — so taking its whole record hands back its stale copy of
/// the other five. Two devices editing different answers between syncs now
/// keep both.
///
/// Two devices editing the *same* answer between syncs is still the later
/// write, because nothing here can know which of them the reader meant. That
/// is the one case a merge cannot settle without asking, and it is not worth a
/// second copy of a note the reader would then have to reconcile by hand.
nonisolated extension Stamped where Value == Tracking {
    /// This record as it stands after the reader edited it on this device.
    ///
    /// The answers they changed are as new as the record itself and need no
    /// date of their own; the answers they left alone keep the age they came
    /// in with, so an untouched note does not arrive at the other device
    /// wearing the timestamp of the cost typed beside it.
    func edited(to new: Tracking, at date: Date = .now) -> Stamped<Tracking> {
        var edited = new
        edited.edits = [:]
        for field in Tracking.Field.allCases where new.sameAnswer(for: field, as: value) {
            let age = value.edits[field] ?? modified
            if age < date { edited.edits[field] = age }
        }
        return Stamped(edited, at: date)
    }

    /// This record and the other device's, answer by answer.
    ///
    /// Ties keep this device's answer, so a merge stays stable when two
    /// devices happen to write in the same instant — the same way
    /// ``Stamped/newer(_:)`` settles a record.
    func merging(_ other: Stamped<Tracking>) -> Stamped<Tracking> {
        let when = max(modified, other.modified)
        var merged = Tracking()
        for field in Tracking.Field.allCases {
            let mine = value.edits[field] ?? modified
            let theirs = other.value.edits[field] ?? other.modified
            merged.take(field, from: theirs > mine ? other.value : value)
            // Written down only where it is older than the record it lands in.
            // Left out, it would be read as of the merged record's own stamp —
            // which here is the newer of two devices, and would age this answer
            // up past an edit a third device made in between.
            let written = max(mine, theirs)
            if written < when { merged.edits[field] = written }
        }
        return Stamped(merged, at: when)
    }

    /// The same answers, every one of them as new as the record.
    ///
    /// What a restore raises a backup's record by: the dates in the file are
    /// the ages the answers had when it was written, and a restore is asking
    /// for them back *now* — see ``LibraryArchive/restoring(_:)``.
    func restamped(at date: Date = .now) -> Stamped<Tracking> {
        var raised = value
        raised.edits = [:]
        return Stamped(raised, at: date)
    }
}

nonisolated extension Tracking {
    /// Read one key at a time, so a record written before a field existed
    /// arrives with that field's default instead of failing.
    ///
    /// The synthesized decoder does not fall back to a property's default: a
    /// key it cannot find is an error, and an error thrown here is not one
    /// record lost but the whole archive — ``LibraryFile`` has nothing left to
    /// read and the library comes up empty. Every field added to this struct
    /// since the first release would have taken the reader's library with it,
    /// which is what the lottery count and the ticket tier did until this was
    /// written. The archive says the same thing about its own new keys, and
    /// answers it the same way: nothing here may insist on being present.
    ///
    /// Encoding stays synthesized — a record is always written whole — and so
    /// do `CodingKeys`, which is why this is an extension rather than a second
    /// init in the body: declared there it would take the memberwise init with
    /// it.
    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ticket: try record.decodeIfPresent(TicketStatus.self, forKey: .ticket) ?? .none,
            seat: try record.decodeIfPresent(String.self, forKey: .seat) ?? "",
            seatClass: try record.decodeIfPresent(String.self, forKey: .seatClass) ?? "",
            // Read as a `Decimal` whether it was written as one or, before
            // costs had currencies, as a whole number of yen.
            cost: try record.decodeIfPresent(Decimal.self, forKey: .cost),
            // A record from before entries holds a count, which reads back
            // as one entry applied for that many times — and a zero, written
            // before zero became "not written down", as none.
            lotteries: try record.decodeIfPresent([LotteryEntry].self, forKey: .lotteries)
                ?? LotteryEntry.carriedOver(count: try decoder.container(keyedBy: LegacyKeys.self)
                    .decodeIfPresent(Int.self, forKey: .lotteryEntries)),
            note: try record.decodeIfPresent(String.self, forKey: .note) ?? "",
            currency: try record.decodeIfPresent(String.self, forKey: .currency) ?? "",
            edits: try record.decodeIfPresent([Field: Date].self, forKey: .edits) ?? [:])
        foldLegacyTicket()
    }

    /// Keys a record no longer writes, read so that what they held is not lost.
    private enum LegacyKeys: String, CodingKey {
        /// How many lotteries were entered, before each was an entry.
        case lotteryEntries
    }
}

/// The single badge shown on a row.
///
/// Read from where the event stands and from the rounds the reader wrote
/// down: in the library or not, past or still to come, ticket in hand or not.
/// ``EventStore/status(for:)`` is the one place it is worked out, because it is
/// the only place that knows whether the event is in the library.
enum TrackingStatus: Hashable {
    case untracked, planned, ticketed, attended
    /// Kept, past, and no ticket recorded — not attended, since only a ticket
    /// says that (``EventStore/hasAttended(_:)``).
    case unticketed

    var label: LocalizedStringKey {
        switch self {
        case .untracked: "Untracked"
        case .planned: "Planning"
        case .ticketed: "Ticketed"
        case .attended: "Attended"
        case .unticketed: "No Ticket"
        }
    }

    var tint: Color {
        switch self {
        case .untracked, .unticketed: .secondary
        case .planned: .trackInterest
        case .ticketed: .trackTicket
        case .attended: .trackAttended
        }
    }
}
