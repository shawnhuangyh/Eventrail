import Foundation

/// What the phone tells the watch: the library's events still to come,
/// soonest first, each with the reader's ticket — everything the watch app
/// draws, and nothing it does not.
///
/// Sent whole as WatchConnectivity's application context (`WatchLink` on the
/// phone, `WatchLibraryStore` on the watch), which keeps only the latest and
/// hands it over whenever the watch app next runs. The watch reads nothing
/// else: no SwiftData, no iCloud, no Eventernote page — only the flyers, from
/// the host the phone already reads them from.
///
/// Compiled into the app, the watch app and — being in `Shared` — the widget
/// extension, which has no use for it.
nonisolated struct WatchLibrary: Codable, Equatable, Sendable {
    var events: [WatchEvent]
    /// Whether days and times are printed on the reader's own clock rather
    /// than each hall's — Settings › Time Zone, as the phone has it.
    var showsLocalTime: Bool

    /// The application context's one key.
    static let contextKey = "library"

    /// How many events are sent: the context has a ceiling, and the watch is
    /// for the next few rather than the season.
    static let limit = 60
}

/// One event in the library, as the watch draws it.
nonisolated struct WatchEvent: Codable, Hashable, Identifiable, Sendable {
    /// The Eventernote event id.
    let id: String
    let title: String
    let venue: String
    /// The event's Eventernote page — what the Live Activity opens the app
    /// with, and so what the watch app is opened with from the Smart Stack.
    let link: URL
    let flyer: URL?
    /// Midnight, on the hall's clock, of the day the event is published on.
    let day: Date
    /// Doors, start and end in the order the event runs (`Event.inOrder`).
    /// Nil wherever the page has published none.
    let doors: Date?
    let starts: Date?
    let ends: Date?
    /// The hall's clock.
    let timeZone: TimeZone

    let hasTicket: Bool
    /// As the ticket prints it — see `Tracking`. Empty where not written down.
    let seat: String
    let seatClass: String
    /// In ``currency``; nil is "not written down". A copy the watch kept
    /// from before costs had currencies holds whole yen, which reads the same.
    let cost: Decimal?
    /// The ISO 4217 code ``cost`` is in. Nil where no cost is written, and in
    /// a copy kept from before costs had currencies, which was yen.
    let currency: String?
    /// How many lotteries were entered; nil is "not written down".
    let lotteryEntries: Int?
    /// Where those lotteries stand, as ``LotteryStanding``'s raw value. Text
    /// rather than the case, so a standing a later phone sends reads as none
    /// rather than failing the whole library; nil where none is written down,
    /// and in a copy kept from before lotteries had results.
    let lottery: String?
}

/// Where the reader's lotteries for one event stand taken together — see
/// `Tracking.lotteryStanding`.
nonisolated enum LotteryStanding: String, Sendable {
    /// At least one was won.
    case won
    /// None was won, and at least one is still to be announced.
    case pending
    /// Every one was lost.
    case lost
}

// MARK: - Reading a copy from another build

/// Read one key at a time, for the reason `Tracking` is: the phone and the
/// watch app are updated apart — a TestFlight build can leave the watch on
/// the last one for days — and a synthesized decoder treats a key it lacks as
/// a corrupt copy, so a field a later phone adds, or one an earlier phone
/// never sent, would leave the watch on whatever it last read. Any field
/// added here is decoded with `decodeIfPresent`.
nonisolated extension WatchLibrary {
    init(from decoder: any Decoder) throws {
        let copy = try decoder.container(keyedBy: CodingKeys.self)
        // An event this build cannot read is left out rather than taking the
        // rest of the library with it.
        events = try copy.decodeIfPresent([Readable<WatchEvent>].self, forKey: .events)?
            .compactMap(\.value) ?? []
        showsLocalTime = try copy.decodeIfPresent(Bool.self, forKey: .showsLocalTime) ?? false
    }
}

nonisolated extension WatchEvent {
    /// Only what says which event it is and when is insisted on; everything
    /// else falls back to "not written down".
    init(from decoder: any Decoder) throws {
        let event = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try event.decode(String.self, forKey: .id),
            title: try event.decode(String.self, forKey: .title),
            venue: try event.decodeIfPresent(String.self, forKey: .venue) ?? "",
            link: try event.decode(URL.self, forKey: .link),
            flyer: try event.decodeIfPresent(URL.self, forKey: .flyer),
            day: try event.decode(Date.self, forKey: .day),
            doors: try event.decodeIfPresent(Date.self, forKey: .doors),
            starts: try event.decodeIfPresent(Date.self, forKey: .starts),
            ends: try event.decodeIfPresent(Date.self, forKey: .ends),
            // Where every import starts — see `Event.publishedZone`.
            timeZone: try event.decodeIfPresent(TimeZone.self, forKey: .timeZone)
                ?? TimeZone(identifier: "Asia/Tokyo")!,
            hasTicket: try event.decodeIfPresent(Bool.self, forKey: .hasTicket) ?? false,
            seat: try event.decodeIfPresent(String.self, forKey: .seat) ?? "",
            seatClass: try event.decodeIfPresent(String.self, forKey: .seatClass) ?? "",
            cost: try event.decodeIfPresent(Decimal.self, forKey: .cost),
            currency: try event.decodeIfPresent(String.self, forKey: .currency),
            lotteryEntries: try event.decodeIfPresent(Int.self, forKey: .lotteryEntries),
            lottery: try event.decodeIfPresent(String.self, forKey: .lottery)
        )
    }
}

/// One element of a list, or nil where it could not be read.
nonisolated private struct Readable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
