import Foundation

/// What a ``LibraryPlanItem`` row can hold: one thing the reader added to an
/// event's plan, kept whole as JSON under its own id.
nonisolated protocol PlanItem: Identifiable, Codable, Equatable where ID == UUID {
    /// What the row's ``LibraryPlanItem/kind`` says it holds. Written into
    /// every row and read back by every build, so it never changes.
    static var rowKind: String { get }
}

/// A time the reader wrote down for an event ahead, and how long before it
/// they want to hear about it: when the goods sale starts, when the random
/// queue tickets stop being handed out, when a payment is due.
///
/// A promoter prints these on the event's page and nowhere a reader of
/// Eventernote can see, and each promoter runs them differently, so nothing
/// here is read or worked out: the reader writes them, a day at a time, since
/// the second night of a run usually moves them all.
///
/// **A wall clock at the hall**, as every time Eventernote publishes is, and
/// as the promoter's notice prints it: a day and a minute, turned into an
/// instant only through the hall's zone (``date(in:)``). A hall whose clock
/// is settled later (``EventStore/retimeEvents()``) moves the instant and not
/// what was written.
nonisolated struct EventReminder: PlanItem, Hashable, Sendable {
    static let rowKind = "reminder"

    var id = UUID()
    /// One of ``ReminderKind`` as the promoter prints it, or what the reader
    /// typed. Shown through ``ReminderKind/label(of:)``.
    var title: String
    /// The day on the hall's calendar: usually the event's, and not for a
    /// payment due a month ahead.
    var day: CalendarDay
    /// Minutes past midnight on the hall's clock.
    var minute: Int
    /// How many minutes before the time the notification comes, 0 being at
    /// the time itself. Nil is a time written down to be read, with no
    /// notification at all.
    var lead: Int?

    /// The instant this falls on, on `zone`'s clock — the hall's.
    func date(in zone: TimeZone) -> Date {
        Calendar.gregorian(in: zone).date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                               hour: minute / 60, minute: minute % 60))
            ?? .distantPast
    }

    /// When the notification comes, where there is one.
    func alertDate(in zone: TimeZone) -> Date? {
        lead.map { date(in: zone).addingTimeInterval(-Double($0) * 60) }
    }

    /// Moves this to the day and minute `date` falls on, on `zone`'s clock.
    mutating func move(to date: Date, in zone: TimeZone) {
        let calendar = Calendar.gregorian(in: zone)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        day = CalendarDay(date, in: calendar)
        minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// As the reader reads a list of them, and as an event's rows hand them
    /// over: by when, the id settling a tie so every device reads one order.
    static func inOrder(_ reminders: [EventReminder]) -> [EventReminder] {
        reminders.sorted {
            ($0.day, $0.minute, $0.id.uuidString) < ($1.day, $1.minute, $1.id.uuidString)
        }
    }
}

nonisolated extension EventReminder {
    /// A new reminder for `event`, for the reader to set the time of: noon on
    /// the event's own day, or for what is done from home ahead of it, the end
    /// of today. Once the event's day is over it is a record: on that day, with
    /// no notification, since none would come.
    init(kind: ReminderKind?, for event: Event, at now: Date = .now) {
        let calendar = Calendar.gregorian(in: event.timeZone)
        let isOver = event.dayEnds <= now
        let isAhead = !isOver && (kind.map(ReminderKind.tickets.contains) ?? false)
        self.init(title: kind?.rawValue ?? "",
                  day: CalendarDay(isAhead ? now : event.date, in: calendar),
                  minute: kind == .applicationDeadline || kind == .paymentDeadline ? 23 * 60 + 59 : 12 * 60,
                  lead: isOver ? nil : kind?.defaultLead ?? 60)
    }
}

/// The times a promoter's notice usually prints, offered ready named — as
/// ``LotteryRound`` offers a sale's rounds. Stored as printed and kept as
/// text, so a name typed by hand or added by a later build reads back as
/// itself.
nonisolated enum ReminderKind: String, CaseIterable, Identifiable {
    /// Where a card holder gathers for the numbers called first, such as
    /// ブシロードカード会員様の優先案内.
    case priorityCheckIn = "優先案内 集合"
    /// The last moment to be given a number in the shuffle (ランダム整理券).
    case randomTicketsClose = "ランダム整理券 締切"
    /// From when late arrivals and second purchases are given the numbers
    /// called last (最後尾整理券).
    case lastTicketsOpen = "最後尾整理券 配布開始"
    case goodsSale = "物販開始"
    case applicationDeadline = "申込締切"
    case paymentDeadline = "入金締切"
    case ticketPickup = "発券開始"

    static let goods: [ReminderKind] = [.priorityCheckIn, .randomTicketsClose, .lastTicketsOpen, .goodsSale]
    static let tickets: [ReminderKind] = [.applicationDeadline, .paymentDeadline, .ticketPickup]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .priorityCheckIn:
            String(localized: "Priority Check-In",
                   comment: "A reminder's name: when holders of a promoter's card gather for the queue numbers called first, 優先案内 集合.")
        case .randomTicketsClose:
            String(localized: "Random Queue Tickets Close",
                   comment: "A reminder's name: the last moment to be given a shuffled queue number for the goods sale, ランダム整理券 締切.")
        case .lastTicketsOpen:
            String(localized: "Last-in-Line Tickets Open",
                   comment: "A reminder's name: from when queue numbers called last are given out at the goods sale, 最後尾整理券 配布開始.")
        case .goodsSale:
            String(localized: "Goods Sale Starts",
                   comment: "A reminder's name: when the goods sale at the venue opens, 物販開始.")
        case .applicationDeadline:
            String(localized: "Application Deadline",
                   comment: "A reminder's name: the last moment to apply for a ticket lottery, 申込締切.")
        case .paymentDeadline:
            String(localized: "Payment Deadline",
                   comment: "A reminder's name: the last moment to pay for a ticket won, 入金締切.")
        case .ticketPickup:
            String(localized: "Ticket Pickup Opens",
                   comment: "A reminder's name: from when a ticket can be issued or collected, 発券開始.")
        }
    }

    /// How far ahead a new reminder of this kind comes: long enough to get
    /// there for what closes, shorter for what only opens, and a day for
    /// what is done from home.
    var defaultLead: Int {
        switch self {
        case .priorityCheckIn, .randomTicketsClose: 60
        case .goodsSale: 30
        case .lastTicketsOpen: 15
        case .applicationDeadline, .paymentDeadline: 24 * 60
        case .ticketPickup: 0
        }
    }

    /// A reminder's name as the reader reads it: one of these in their
    /// language, and anything else as it was typed.
    static func label(of title: String) -> String {
        ReminderKind(rawValue: title)?.label ?? title
    }

    /// As long as a name is kept: a row has room for a line, and anything
    /// longer is a note.
    static let longestTyped = 40

    /// A name as it is kept: the ends trimmed, and one of these, by either of
    /// its names, as that one — so a name left as it was offered still reads
    /// in another language on another device.
    static func typed(_ text: String) -> String {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let listed = allCases.first(where: { $0.rawValue == typed || $0.label == typed }) {
            return listed.rawValue
        }
        return String(typed.prefix(longestTyped))
    }
}

/// How long before a reminder's time its notification comes.
nonisolated enum ReminderLead {
    /// In minutes, as a reminder keeps it.
    static let choices = [0, 15, 30, 60, 120, 180, 24 * 60]

    static func label(of lead: Int) -> String {
        switch lead {
        case 0: String(localized: "At the Time", comment: "When a reminder's notification comes: at the time written down.")
        case 15: String(localized: "15 Minutes Before", comment: "When a reminder's notification comes.")
        case 30: String(localized: "30 Minutes Before", comment: "When a reminder's notification comes.")
        case 60: String(localized: "1 Hour Before", comment: "When a reminder's notification comes.")
        case 120: String(localized: "2 Hours Before", comment: "When a reminder's notification comes.")
        case 180: String(localized: "3 Hours Before", comment: "When a reminder's notification comes.")
        case 24 * 60: String(localized: "1 Day Before", comment: "When a reminder's notification comes.")
        default: String(localized: "\(lead) Minutes Before",
                        comment: "When a reminder's notification comes, for a lead this build does not offer.")
        }
    }
}

/// A queue ticket for the goods sale, as the link in its QR code: the page
/// where the queue stands and where it says when to come.
///
/// Only the link is kept, never the picture, and the page is never read by
/// the app: it opens in the reader's browser, as every other link does. The
/// promoter's system answers for what it says, and one ticket is a person's
/// place in one queue, so several can stand on one event (a second purchase
/// takes a second ticket).
nonisolated struct QueueTicket: PlanItem, Hashable, Sendable {
    static let rowKind = "queueTicket"

    var id = UUID()
    var link: URL
    /// When it was added — what tells two tickets at one host apart, and the
    /// order they are listed in.
    var added: Date
    /// The number printed on it, as the reader wrote it down: what the queue's
    /// page is checked against. Nil where none was. Each promoter prints its
    /// own, so nothing here reads one off the ticket or the link.
    var number: String?

    /// As long as a number is kept: a row has room for one, and anything
    /// longer is a note.
    static let longestNumber = 20

    /// A number as it is kept: width folded, since a ticket's １２３ is the
    /// page's 123, and the ends trimmed. Nil where nothing is left.
    static func typedNumber(_ text: String) -> String? {
        let number = text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? nil : String(number.prefix(longestNumber))
    }

    /// The web page a QR code's text points at, or nil where it points at
    /// anything else: a code is whatever was printed, and is opened on a tap.
    static func link(inCode text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    /// Every web page `codes` point at, once each, as they were found.
    static func links(inCodes codes: [String]) -> [URL] {
        var seen = Set<URL>()
        return codes.compactMap(link(inCode:)).filter { seen.insert($0).inserted }
    }

    /// What tells `links` apart on a button, in their order. Two tickets of one
    /// queue differ only towards the end, which a long link on a button is cut
    /// off before, so where they share a host each is what follows the part
    /// they all open with; otherwise each is the link without its scheme, or
    /// with it where only the scheme differs.
    static func labels(tellingApart links: [URL]) -> [String] {
        let bare = links.map { link in
            let text = link.absoluteString
            return text.range(of: "://").map { String(text[$0.upperBound...]) } ?? text
        }
        guard Set(bare).count == links.count else { return links.map(\.absoluteString) }
        guard Set(links.map { $0.host()?.lowercased() }).count == 1, let first = bare.first else { return bare }

        let shared = bare.dropFirst().reduce(first) { $0.commonPrefix(with: $1) }
        // Back to a separator, so that nothing is cut in the middle of a word.
        guard let separator = shared.lastIndex(where: { "/?&=#".contains($0) }) else { return bare }
        let dropped = shared.distance(from: shared.startIndex, to: separator) + 1
        let rests = bare.map { $0.dropFirst(dropped) }
        return rests.contains(where: \.isEmpty) ? bare : rests.map { "…\($0)" }
    }

    /// As an event's rows hand them over: the first added first.
    static func inOrder(_ tickets: [QueueTicket]) -> [QueueTicket] {
        tickets.sorted { ($0.added, $0.id.uuidString) < ($1.added, $1.id.uuidString) }
    }
}
