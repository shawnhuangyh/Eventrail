import Foundation

/// What the home and Lock Screen widgets draw: the library's next few events,
/// the lottery rounds still waiting on a result, and every event the reader
/// went to — as the app last had them, and nothing they do not draw.
///
/// Written by the app (`WidgetLink`) into the App Group's container whenever
/// the library changes, and read by the widget extension as it draws. The
/// extension opens no store and reads nothing of iCloud or Eventernote; the
/// one thing it fetches is a flyer, from the host the app reads them from.
///
/// Everything that moves with the clock — how many days are left, whether a
/// round's results are out, which day's memories are today's, which event is
/// next once one is over — is worked out by the widget from the days and
/// times here, at the moment each entry of its timeline is drawn for. So a
/// copy written days ago still draws today right, and the app writes a new
/// one only when what is in it changes.
///
/// Compiled into the app and the widget extension, and kept out of the watch
/// app, which has no widgets.
nonisolated struct WidgetLibrary: Codable, Equatable, Sendable {
    /// The library's events still to come, soonest first — a few of them, so
    /// the Next Event widget can move on past one that is over before the app
    /// next runs.
    var upcoming: [WidgetEvent]
    /// Every lottery round waiting on its result for an event still ahead, by
    /// results day — the soonest first and no day last, as the Me card lists
    /// them.
    var rounds: [WidgetRound]
    /// Every event the reader went to (a ticket held, the day over), in no
    /// order: On This Day picks the day's from them as it draws.
    var memories: [WidgetMemory]

    static let upcomingLimit = 10
    static let roundLimit = 60

    static let empty = WidgetLibrary(upcoming: [], rounds: [], memories: [])
}

/// The widgets' kinds: how the extension names them, and how the app asks for
/// one to be drawn again.
nonisolated enum WidgetKind {
    static let nextEvent = "NextEvent"
    static let lotteries = "Lotteries"
    static let onThisDay = "OnThisDay"
}

/// One event still to come, as the Next Event widget draws it.
nonisolated struct WidgetEvent: Codable, Hashable, Identifiable, Sendable {
    /// The Eventernote event id.
    let id: String
    let title: String
    let venue: String
    /// The event's Eventernote page — what the app is opened on the event's
    /// sheet with, as from its Live Activity.
    let link: URL
    let flyer: URL?
    /// The day the hall says it falls on, which "today" and "in 4 days" are
    /// counted to — as `Event.daysAway` counts them.
    let day: CalendarDay
    /// The day as it is printed — on the hall's clock, or the reader's under
    /// Settings › Time Zone (`Event.shown(on:)`) — on ``timeZone``.
    let shownDay: Date
    /// The clock the day and the times are printed on.
    let timeZone: TimeZone
    /// Doors, start and end in the order the event runs (`Event.inOrder`),
    /// nil wherever the page has published none.
    let doors: Date?
    let starts: Date?
    let ends: Date?
    /// Where the show runs to: its published end, or the app's assumed
    /// length after its start (`Event.assumedLength`). Nil with no start.
    let runsTo: Date?
    /// When the widget moves on to the next: ``runsTo``, or with no start
    /// published, the end of its day on the hall's clock.
    let leaves: Date
    let hasTicket: Bool
    /// As the ticket prints it; empty where not written down.
    let seat: String
}

/// One lottery round waiting on its result, as the Lotteries widget draws it.
nonisolated struct WidgetRound: Codable, Hashable, Identifiable, Sendable {
    let eventID: String
    let entryID: UUID
    /// The event's.
    let title: String
    /// The event's Eventernote page.
    let link: URL
    /// The round in the reader's language — "Lottery" where none was named.
    let round: String
    /// How many times it was applied for; 0 is "not written down".
    let applications: Int
    /// The day the results come out, where it was written down.
    let day: CalendarDay?
    /// How many choices the round applied with. With more than one, a win is
    /// given in the app, where the reader says which.
    let choices: Int
    /// The one choice a win goes to, where the round applied with exactly one.
    let onlyChoice: UUID?
    /// The end of the event's day on its hall's clock, when the round leaves
    /// the list (`LotteryRow.isOver`).
    let eventEnds: Date

    var id: String { ResultsReminderID.of(event: eventID, entry: entryID) }

    /// Whether the results day has come — today included — as the Lotteries
    /// list reads it (`LotteryRow.isResultsOut(asOf:)`).
    func isOut(asOf now: Date) -> Bool {
        guard let day else { return false }
        return day.daysAway(from: now) <= 0
    }

    /// The event's page naming this round — what opens the round's own page
    /// of the ticket sheet, where its result is written down.
    var roundLink: URL { RoundLink.url(event: link, entry: entryID) }
}

/// One event the reader went to, for On This Day.
nonisolated struct WidgetMemory: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let venue: String
    let link: URL
    let flyer: URL?
    /// The day it fell on, on its hall's clock (`Event.localDay`).
    let day: CalendarDay
    /// Its start, or its day — two on one day in the order they ran.
    let sortDate: Date
    /// The first line of the reader's note; empty where there is none.
    let note: String
}

nonisolated extension WidgetLibrary {
    /// `Widgets` in the App Group's container, which the app writes and the
    /// extension reads.
    static var folder: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: EventActivityAttributes.appGroup)?
            .appending(path: "Widgets", directoryHint: .isDirectory)
    }

    static var file: URL? {
        folder?.appending(path: "library.json", directoryHint: .notDirectory)
    }

    /// The copy the app last wrote; nil where it has written none, or none
    /// this build can read.
    static func read() -> WidgetLibrary? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetLibrary.self, from: data)
    }

    /// Read one element at a time, as the watch's copy is: the copy outlives
    /// the build that wrote it until the app next runs — after an update, the
    /// extension reads what the last build left — and an event this build
    /// cannot read is left out rather than every list with it. A field added
    /// to any of these is an optional, so a copy without it still reads.
    init(from decoder: any Decoder) throws {
        let copy = try decoder.container(keyedBy: CodingKeys.self)
        upcoming = try copy.decodeIfPresent([Readable<WidgetEvent>].self, forKey: .upcoming)?
            .compactMap(\.value) ?? []
        rounds = try copy.decodeIfPresent([Readable<WidgetRound>].self, forKey: .rounds)?
            .compactMap(\.value) ?? []
        memories = try copy.decodeIfPresent([Readable<WidgetMemory>].self, forKey: .memories)?
            .compactMap(\.value) ?? []
    }
}

// MARK: - A result given from a widget

/// A lottery result given from the Lotteries widget's Won or Lost, for the
/// app to write down the next time it runs.
///
/// The widget's buttons run in the extension, which holds no store and must
/// not write to one: so each answer is left as a file of its own beside the
/// library's copy, the widget leaves the round out from then on, and the app
/// takes every answer in as it launches and comes back
/// (`WidgetLink.takeAnswers(into:)`) — only where the round is still waiting,
/// so a result given meanwhile on another device stands.
nonisolated struct WidgetAnswer: Codable, Hashable, Sendable {
    let eventID: String
    let entryID: UUID
    let won: Bool
    /// The choice won, where the round applied with one.
    let choiceID: UUID?
    let given: Date

    var roundID: String { ResultsReminderID.of(event: eventID, entry: entryID) }

    static var folder: URL? {
        WidgetLibrary.folder?.appending(path: "Answers", directoryHint: .isDirectory)
    }

    /// Leaves the answer for the app. One file per round, so a second answer
    /// to it replaces the first, and the app taking one in never loses one
    /// written while it read.
    func save() throws {
        guard let folder = Self.folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(eventID)-\(entryID.uuidString).json", directoryHint: .notDirectory)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    /// Every answer not yet taken in, with the file it is in.
    static func waiting() -> [(file: URL, answer: WidgetAnswer)] {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let answer = try? JSONDecoder().decode(WidgetAnswer.self, from: data)
            else { return nil }
            return (file, answer)
        }
    }
}

/// The name a round goes by outside the store: its results-day reminder's
/// identifier, and a widget's row for it.
nonisolated enum ResultsReminderID {
    static let prefix = "lottery-results/"

    static func of(event: String, entry: UUID) -> String {
        "\(prefix)\(event)/\(entry.uuidString)"
    }
}

/// A link to one lottery round: its event's Eventernote page with the round
/// named in the query. The page alone is how a Live Activity opens the
/// event's sheet; the round on it opens the ticket sheet on that round's page
/// instead, as its results-day reminder does.
nonisolated enum RoundLink {
    private static let name = "round"

    static func url(event page: URL, entry: UUID) -> URL {
        page.appending(queryItems: [URLQueryItem(name: name, value: entry.uuidString)])
    }

    /// The round a link names, where it names one.
    static func entry(in url: URL) -> UUID? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
            .flatMap(UUID.init(uuidString:))
    }
}
