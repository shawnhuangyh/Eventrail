import SwiftUI

nonisolated enum TicketStatus: String, CaseIterable, Identifiable, Hashable, Codable {
    case none, purchased

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .none: "Not purchased"
        case .purchased: "Purchased"
        }
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
/// What is left is the ticket: whether it is in hand, which the library cannot
/// say by itself, and once it is, the two things about it worth keeping after
/// the night is over — and whatever the reader wants to write down.
///
/// Dropping the two needed no migration: a record written before this still
/// carries `interest` and `attendance`, and a decoder ignores keys it has no
/// property for. Adding one needs none either, but only because the decoder
/// below reads every key as optional — a synthesized one treats a key an older
/// record does not carry as a corrupt file, and takes the whole library with
/// it. So an older record simply has no seat, no cost and no lottery count:
/// nothing written down.
nonisolated struct Tracking: Hashable, Codable {
    var ticket: TicketStatus = .none
    /// Where the reader sat, as the ticket prints it.
    ///
    /// One free line rather than a row and a number in fields of their own: a
    /// hall prints 1階 L列 23番, an arena prints A5ブロック 12番, and a live
    /// house prints an entry number and no seat at all. Anything that insisted
    /// on a shape would be wrong for two of the three.
    var seat: String = ""
    /// What the ticket cost, in whole yen.
    ///
    /// Nil is "not written down", which is not the same as free — a lottery
    /// seat or an invite really does cost nothing, and it is worth being able
    /// to record that.
    var cost: Int?
    /// How many entries the reader put into the lottery for this night.
    ///
    /// Nil is "not written down". Zero is an answer somebody gave — a seat
    /// bought the moment it went on sale, or an invite — so clearing the field
    /// goes back to nil rather than settling on 0, and a night nobody filled in
    /// is never counted as a night with no applications.
    var lotteryEntries: Int?
    var note: String = ""
    /// When each answer above was last written, where that is older than the
    /// record holding it.
    ///
    /// Not one of the reader's answers but the app's note about them, and it
    /// is what lets a merge settle this record an answer at a time — see
    /// ``Stamped/merging(_:)``. A record carries one stamp for five answers,
    /// so a cost typed on the iPad after a note was typed on the phone would
    /// otherwise carry the iPad's whole record — its older copy of the note
    /// included — over the newer note. That is the erasure ``Stamped`` exists
    /// to stop, one level down.
    ///
    /// A field missing from here is exactly as old as its record. That is what
    /// an archive written before this existed says about all five, and what an
    /// answer written in the same breath as its record says about itself, so
    /// only an answer *older* than the record around it is written down and a
    /// record edited once carries nothing here at all.
    var edits: [Field: Date] = [:]

    /// The five answers a record holds, named so that a merge can take them
    /// one at a time.
    ///
    /// A field added to this struct belongs here too, and the switches in
    /// ``sameAnswer(for:as:)`` and ``take(_:from:)`` will not compile until it
    /// is — which is the point of naming them rather than reaching for a
    /// key path.
    nonisolated enum Field: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
        case ticket, seat, cost, lotteryEntries, note
    }

    /// Whether the reader has written anything down here.
    ///
    /// Read off the answers alone: ``edits`` says when they were written, and
    /// a record whose every answer has since been cleared is empty however
    /// recently that happened.
    var isEmpty: Bool {
        ticket == .none && seat.isEmpty && cost == nil
            && lotteryEntries == nil && note.isEmpty
    }
}

nonisolated extension Tracking {
    /// Whether two records give the same answer to one question.
    fileprivate func sameAnswer(for field: Field, as other: Tracking) -> Bool {
        switch field {
        case .ticket: ticket == other.ticket
        case .seat: seat == other.seat
        case .cost: cost == other.cost
        case .lotteryEntries: lotteryEntries == other.lotteryEntries
        case .note: note == other.note
        }
    }

    /// Takes one answer from another record and leaves the other four alone.
    fileprivate mutating func take(_ field: Field, from other: Tracking) {
        switch field {
        case .ticket: ticket = other.ticket
        case .seat: seat = other.seat
        case .cost: cost = other.cost
        case .lotteryEntries: lotteryEntries = other.lotteryEntries
        case .note: note = other.note
        }
    }
}

/// The reader's record, settled one answer at a time.
///
/// ``Stamped`` settles everything else record by record, which is right where
/// a record holds one answer: a membership, a favourite, a follow. This one
/// holds five, and the device that wrote last had almost certainly written
/// about one of them — so taking its whole record hands back its stale copy of
/// the other four. Two devices editing different answers between syncs now
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
            cost: try record.decodeIfPresent(Int.self, forKey: .cost),
            lotteryEntries: try record.decodeIfPresent(Int.self, forKey: .lotteryEntries),
            note: try record.decodeIfPresent(String.self, forKey: .note) ?? "",
            edits: try record.decodeIfPresent([Field: Date].self, forKey: .edits) ?? [:])
    }
}

/// Writes an amount of yen into a text field, and reads one back out.
///
/// Yen because Eventernote lists Japanese events at Japanese halls and prices
/// every one of them in yen; a currency of its own per ticket would be a second
/// field to fill in for the sake of the evening somebody spends abroad.
///
/// `TextField(value:format:)` insists the value and the style agree on a type,
/// and no built-in style takes an optional — hence this one. Parsing reads the
/// digits out of whatever is in the field and ignores the rest, so the ¥ and
/// the separators the style itself wrote survive an edit, and a full-width
/// １２３４ from a Japanese keyboard is the same number as 1234.
nonisolated struct YenAmount: ParseableFormatStyle {
    var parseStrategy: Strategy { Strategy() }

    func format(_ value: Int?) -> String {
        value.map { $0.formatted(.currency(code: "JPY")) } ?? ""
    }

    nonisolated struct Strategy: ParseStrategy {
        /// Nine digits is ¥999,999,999. Past that the reader is leaning on a
        /// key rather than recording a ticket, and the arithmetic would
        /// eventually overflow.
        func parse(_ value: String) -> Int? {
            let digits = value.compactMap(\.wholeNumberValue).prefix(9)
            guard !digits.isEmpty else { return nil }
            return digits.reduce(0) { $0 * 10 + $1 }
        }
    }
}

nonisolated extension FormatStyle where Self == YenAmount {
    static var yen: YenAmount { YenAmount() }
}

/// Writes a count of lottery entries into a text field, and reads one back out.
///
/// The same shape as ``YenAmount`` and for the same two reasons: no built-in
/// style takes an optional, and an empty field has to read back as nil rather
/// than as zero, which here is the difference between a night nobody filled in
/// and a night the reader went to without applying for anything.
nonisolated struct EntryCount: ParseableFormatStyle {
    var parseStrategy: Strategy { Strategy() }

    func format(_ value: Int?) -> String {
        value.map { $0.formatted(.number) } ?? ""
    }

    nonisolated struct Strategy: ParseStrategy {
        /// Four digits is 9,999 applications for one night. Past that the
        /// reader is leaning on a key rather than recording a lottery.
        func parse(_ value: String) -> Int? {
            let digits = value.compactMap(\.wholeNumberValue).prefix(4)
            guard !digits.isEmpty else { return nil }
            return digits.reduce(0) { $0 * 10 + $1 }
        }
    }
}

nonisolated extension FormatStyle where Self == EntryCount {
    static var entries: EntryCount { EntryCount() }
}

/// The single badge shown on a row.
///
/// Read from where the event stands rather than from anything the reader filled
/// in: in the library or not, past or still to come, ticket in hand or not.
/// ``EventStore/status(for:)`` is the one place it is worked out, because it is
/// the only place that knows whether the event is in the library.
enum TrackingStatus: Hashable {
    case untracked, planned, ticketed, attended

    var label: LocalizedStringKey {
        switch self {
        case .untracked: "Untracked"
        case .planned: "Planning"
        case .ticketed: "Ticketed"
        case .attended: "Attended"
        }
    }

    var tint: Color {
        switch self {
        case .untracked: .secondary
        case .planned: .trackInterest
        case .ticketed: .trackTicket
        case .attended: .trackAttended
        }
    }
}
