import Foundation

/// What a ``LibraryPlanItem`` row can hold: one thing the reader added to an
/// event's plan, kept whole as JSON under its own id.
nonisolated protocol PlanItem: Identifiable, Codable, Equatable where ID == UUID {
    /// What the row's ``LibraryPlanItem/kind`` says it holds. Written into
    /// every row and read back by every build, so it never changes.
    static var rowKind: String { get }
}

/// A time of the goods sale at the hall the reader wrote down for an event:
/// when the queue tickets are handed out (``ReminderKind/goods``) — the
/// 会場物販 card on the event's sheet.
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
///
/// How long before it the notification comes is one answer in Settings for
/// every time (``EventReminders/goodsLead``). A reminder written by an older
/// build — a time of the ticket sale, which a won round now keeps
/// (``LotteryEntry/payment``), the sale's opening (物販開始), or one the
/// reader named — is kept as it was and neither shown nor notified.
nonisolated struct EventReminder: PlanItem, Hashable, Sendable {
    static let rowKind = "reminder"

    var id = UUID()
    /// One of ``ReminderKind`` as the promoter prints it, or what an older
    /// build let the reader type. Shown through ``ReminderKind/label(of:)``.
    var title: String
    /// The day on the hall's calendar: usually the event's, and the day
    /// before for a sale held the night before (前日物販).
    var day: CalendarDay
    /// Minutes past midnight on the hall's clock.
    var minute: Int
    /// How many minutes before the time an older build's notification came.
    /// Kept as it was written, and read by nothing: Settings says now.
    var lead: Int?

    /// The instant this falls on, on `zone`'s clock — the hall's.
    func date(in zone: TimeZone) -> Date {
        Calendar.gregorian(in: zone).date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                               hour: minute / 60, minute: minute % 60))
            ?? .distantPast
    }

    /// Which of the goods sale's times this is — the three queue times an
    /// older build named apart read as the one they are (``ReminderKind/goodsTime``)
    /// — or nil for anything else.
    var goodsKind: ReminderKind? { ReminderKind(rawValue: title)?.goodsTime }

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
    /// A new time of `kind` for `event`, for the reader to set: on the event's
    /// own day, at the hour the kind usually falls at.
    init(kind: ReminderKind, for event: Event) {
        self.init(title: kind.rawValue,
                  day: CalendarDay(event.date, in: .gregorian(in: event.timeZone)),
                  minute: kind.usualMinute)
    }
}

nonisolated extension Tracking {
    /// The time written for `kind` of the goods sale: the earliest, where an
    /// older build left several — its three queue times are the one time
    /// they almost always were.
    func goodsReminder(_ kind: ReminderKind) -> EventReminder? {
        EventReminder.inOrder(reminders.filter { $0.goodsKind == kind }).first
    }

    /// This, with `reminder` as the one time of its kind — in its place where
    /// it is already here — and every other written for that kind taken out.
    func settingGoodsReminder(_ reminder: EventReminder) -> Tracking {
        var record = self
        guard let kind = reminder.goodsKind else { return record }
        var reminder = reminder
        reminder.title = kind.rawValue
        record.reminders.removeAll { $0.goodsKind == kind && $0.id != reminder.id }
        if let index = record.reminders.firstIndex(where: { $0.id == reminder.id }) {
            record.reminders[index] = reminder
        } else {
            record.reminders.append(reminder)
        }
        return record
    }

    /// This, with every time written for `kind` taken out.
    func removingGoodsReminder(_ kind: ReminderKind) -> Tracking {
        var record = self
        record.reminders.removeAll { $0.goodsKind == kind }
        return record
    }
}

/// The times a promoter's notice prints for the goods sale, offered ready
/// named — as ``LotteryRound`` offers a sale's rounds. Stored as printed and
/// kept as text, so a name a later build adds reads back as itself.
///
/// One is asked: when the queue tickets are handed out. The sale's opening
/// (物販開始) an older build offered is no longer one (Shawn); what else the
/// notice says is read on the notice itself (``GoodsNotice``).
nonisolated enum ReminderKind: String, CaseIterable, Identifiable {
    /// When the queue tickets are handed out (整理券配布): the priority
    /// queue's gathering, the random tickets' close and the last-in-line
    /// tickets' opening, which a notice nearly always sets at one time.
    case queueTime = "整理券配布"
    /// What older builds wrote for the queue time, three ways: read as
    /// ``queueTime`` (``goodsTime``).
    case priorityCheckIn = "優先案内 集合"
    case randomTicketsClose = "ランダム整理券 締切"
    case lastTicketsOpen = "最後尾整理券 配布開始"

    /// The times the 会場物販 card asks, in the order they fall.
    static let goods: [ReminderKind] = [.queueTime]

    var id: String { rawValue }

    /// The one of ``goods`` this is.
    var goodsTime: ReminderKind { .queueTime }

    var label: String {
        String(localized: "Queue Tickets Out",
               comment: "A time of the goods sale at the venue: when the queue tickets are handed out, 整理券配布.")
    }

    /// Where a new time of this kind opens: mid-morning. The reader moves it
    /// to what the notice says.
    var usualMinute: Int { 10 * 60 }

    /// A reminder's name as the reader reads it: one of these in their
    /// language, and anything else as it was typed.
    static func label(of title: String) -> String {
        ReminderKind(rawValue: title)?.label ?? title
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

    /// As an event's rows hand them over: the first added first.
    static func inOrder(_ tickets: [QueueTicket]) -> [QueueTicket] {
        tickets.sorted { ($0.added, $0.id.uuidString) < ($1.added, $1.id.uuidString) }
    }
}

/// A set list as the link in its QR code: what was played, as a promoter hands
/// it out once the show is over, on a poster at the doors or on the hall's
/// screen.
///
/// Kept as a ``QueueTicket`` is, and for the same reasons: only the link, never
/// the picture, and the page opens in the reader's browser, never read by the
/// app. Usually one to an event, though nothing insists: a run's poster can
/// print one for each night, and a playlist can stand beside the page.
nonisolated struct SetList: PlanItem, Hashable, Sendable {
    static let rowKind = "setList"

    var id = UUID()
    var link: URL
    /// When it was added, and the order they are listed in.
    var added: Date

    /// As an event's rows hand them over: the first added first.
    static func inOrder(_ setLists: [SetList]) -> [SetList] {
        setLists.sorted { ($0.added, $0.id.uuidString) < ($1.added, $1.id.uuidString) }
    }
}

/// Where the goods sale is told of — usually the promoter's post on X, which
/// prints the line-up, the prices, the queue's rules and its times — as the
/// link the reader pasted: the 会場物販 card's Sale Info.
///
/// Kept as a ``QueueTicket`` is, and for the same reasons: only the link, and
/// the page opens in the reader's browser — or the app that takes its links,
/// X's among them — never read by the app. **One to an event**
/// (``Tracking/goodsNotice``): written again, it takes the place of the one
/// before. A list in the record all the same, as every part of the plan is,
/// so two devices writing one each between syncs keep both, and the later
/// is shown.
nonisolated struct GoodsNotice: PlanItem, Hashable, Sendable {
    static let rowKind = "goodsNotice"

    var id = UUID()
    var link: URL
    /// When it was written, which settles the one shown.
    var added: Date

    /// As an event's rows hand them over: the first added first.
    static func inOrder(_ notices: [GoodsNotice]) -> [GoodsNotice] {
        notices.sorted { ($0.added, $0.id.uuidString) < ($1.added, $1.id.uuidString) }
    }
}

nonisolated extension Tracking {
    /// The goods sale's notice: the one written last, where two devices
    /// wrote one each.
    var goodsNotice: GoodsNotice? { GoodsNotice.inOrder(goodsNotices).last }

    /// This, with `link` as the goods sale's notice — in the place of the one
    /// shown, where there is one, and every other taken out.
    func settingGoodsNotice(_ link: URL, at now: Date = .now) -> Tracking {
        var record = self
        if let shown = goodsNotice, shown.link == link, goodsNotices.count == 1 { return record }
        record.goodsNotices = [GoodsNotice(id: goodsNotice?.id ?? UUID(), link: link, added: now)]
        return record
    }
}

/// The web page a printed QR code holds, which is what a ``QueueTicket`` and a
/// ``SetList`` are each kept as.
nonisolated enum QRCodeLink {
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

    /// The web page a link typed or pasted points at: as a code's, or with
    /// `https://` put before it where it was left off (`x.com/…`). Nil where
    /// it is not a web page — anything with a space in it, another scheme
    /// (`mailto:`), or a host with no dot.
    static func link(typed text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let link = link(inCode: trimmed) { return link }
        let head = trimmed.prefix { $0 != "/" }
        guard !trimmed.contains(where: \.isWhitespace), !head.contains(":"), !head.contains("@"),
              let link = link(inCode: "https://" + trimmed),
              let host = link.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        return link
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
}
