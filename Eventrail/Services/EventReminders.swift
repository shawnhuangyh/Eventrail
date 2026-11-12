import Foundation
import Observation
import OSLog
import UserNotifications

/// A notification ahead of a time the reader wrote down for an event
/// (``EventReminder``). Tapped, it opens the event's sheet, where the queue
/// tickets are.
///
/// Scheduled as ``LotteryReminders`` schedules: from ``RootView``, from the
/// library as it stands, adding only what differs and taking back what no
/// longer applies. Local, so each device schedules its own, and a time written
/// on the phone comes to the iPad too unless its switch is off. The soonest
/// ``ReminderAlert/limit`` only: iOS keeps an app's 64 soonest, shared with the
/// results-day and Live Activity reminders.
///
/// **Asked for at the moment it is wanted**: on the checkmark that saves a
/// reminder with a notification to come (``askIfNeeded(for:at:)``), or as the
/// switch is turned back on — never at launch.
@MainActor
@Observable
final class EventReminders {
    static let shared = EventReminders()

    /// The per-device preference in `UserDefaults`, as the results-day
    /// reminders' is.
    static let storageKey = "eventRemindersEnabled"

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "reminders")

    /// Whether this device reminds the reader. On until they turn it off: a
    /// time saved with an alert is the reader asking to hear about it.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
            Task {
                if isEnabled, await center.notificationSettings().authorizationStatus == .notDetermined {
                    await requestAuthorization()
                } else {
                    rescheduleSoon()
                }
            }
        }
    }

    /// The event a tapped reminder named, until ``RootView`` opens it. Handed
    /// over by ``LotteryReminders``, the app's one notification delegate.
    var opened: Event.ID?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private weak var store: EventStore?
    @ObservationIgnored private var pending: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? true
    }

    /// Brings what is scheduled into line with `store` a second from now —
    /// once after a burst of edits rather than once for each — each run
    /// waiting for the one before it.
    func schedule(from store: EventStore) {
        self.store = store
        let previous = pending
        previous?.cancel()
        pending = Task { [weak self] in
            await previous?.value
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await reconcile()
        }
    }

    private func rescheduleSoon() {
        if let store { schedule(from: store) }
    }

    /// Asks the system for the right to notify, where nobody has answered yet
    /// and `reminder` has a notification to come.
    func askIfNeeded(for reminder: EventReminder, at event: Event) {
        guard isEnabled, ReminderAlert(reminder: reminder, event: event) != nil else { return }
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            await requestAuthorization()
        }
    }

    private func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("Notifications could not be asked for: \(error.localizedDescription, privacy: .public)")
        }
        rescheduleSoon()
    }

    /// Marks the step a notification was about as reached, from the button
    /// under it (``ReminderAlert/doneAction``) — as its to-do's own button
    /// does, where it is the step that to-do is waiting on. Written at once:
    /// the app may have been woken for this alone, and be put away again
    /// before a save a moment later would run.
    func markDone(_ reminder: EventReminder.ID, at eventID: Event.ID) {
        let store = store ?? Launch.shared.store
        guard let event = store.event(id: eventID) else { return }
        let record = store.tracking(for: event)
        let todo = TicketTodoList.todos(for: event, tracking: record).first { $0.current?.id == reminder }
        store.setTracking(todo?.advanced(in: record) ?? record.marking([reminder], done: .now), for: event)
        store.saveNow()
        schedule(from: store)
    }

    /// What is pending made to match the library, and a reminder already
    /// shown taken out of Notification Center once its time has been taken
    /// out or its event has gone.
    private func reconcile() async {
        guard let store else { return }
        let status = await center.notificationSettings().authorizationStatus
        let canNotify = status == .authorized || status == .provisional || status == .ephemeral
        let events = store.upcoming
        let clock = TimeDisplay.stored

        let due = isEnabled && canNotify
            ? ReminderAlert.due(in: events, tracking: store.tracking(for:), clock: clock)
            : []
        let wanted = Dictionary(due.map { ($0.identifier, $0) }) { first, _ in first }
        let scheduled = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderAlert.prefix) }

        let gone = scheduled.map(\.identifier).filter { wanted[$0] == nil }
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }

        let held = Dictionary(scheduled.map { ($0.identifier, $0) }) { first, _ in first }
        for alert in due where !alert.isScheduled(as: held[alert.identifier]) {
            do {
                try await center.add(alert.request)
            } catch {
                Self.log.error("A reminder could not be scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }

        // One dealt with from the list has nothing left to say either.
        let standing = Set(events.flatMap { event in
            let record = store.tracking(for: event)
            return record.reminders.filter(record.owes).map { ReminderAlert.identifier(of: $0.id, at: event.id) }
        })
        let spent = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(ReminderAlert.prefix) && !standing.contains($0) }
        if !spent.isEmpty { center.removeDeliveredNotifications(withIdentifiers: spent) }
    }
}

/// One notification for one reminder: what it is about, and when it comes.
struct ReminderAlert: Hashable {
    let eventID: Event.ID
    let reminderID: EventReminder.ID
    let eventTitle: String
    let title: String
    let body: String
    /// When it comes: the reminder's time, less its lead.
    let date: Date
    /// Whether it comes through a Focus and stays up: a deadline an hour away
    /// is missed for good if it waits for the Focus to end. One a day ahead
    /// (``calmLead``) can wait, and asking iOS to treat it as urgent is what
    /// leads iOS to suggest the reader turn the whole thing off.
    let isTimeSensitive: Bool
    /// Which buttons stand under it (``categories``): for a step of the ticket
    /// sale, the one that marks it reached. Nil for any other reminder.
    let category: String?
    /// The page it is done on, where the reader kept one, for the button that
    /// opens it.
    let link: URL?

    /// How many are scheduled at once, the soonest first: what iOS's 64
    /// leaves beside ``LotteryReminder/limit`` and ``ActivityReminder/limit``.
    /// The ones past these are scheduled as the earlier ones are delivered
    /// and the app next opens.
    static let limit = 20
    /// From how many minutes ahead a notification is no longer urgent.
    static let calmLead = 24 * 60

    nonisolated static let prefix = "eventReminder."
    nonisolated static let eventKey = "event"
    nonisolated static let reminderKey = "reminder"
    nonisolated static let linkKey = "link"
    /// The button that marks the step reached, without opening the app.
    nonisolated static let doneAction = "ticketTodo.done"
    /// The button that opens the page the reader kept for it.
    nonisolated static let openAction = "ticketTodo.open"

    /// The category of a notification for one of the ticket sale's steps:
    /// one for each, since each says what its button marks, and each again
    /// with the button for a page.
    nonisolated static func category(of kind: ReminderKind, linked: Bool) -> String {
        "ticketTodo.\(kind.rawValue)\(linked ? ".link" : "")"
    }

    /// Every category, for the system to be told of as the app launches.
    static var categories: Set<UNNotificationCategory> {
        Set(ReminderKind.tickets.flatMap { kind in
            let title = switch kind {
            case .applicationDeadline:
                String(localized: "Mark as Applied", comment: "A button: the reader has applied for the ticket lottery.")
            case .paymentDeadline:
                String(localized: "Mark as Paid", comment: "A button: the reader has paid for the ticket.")
            default:
                String(localized: "Mark as Issued", comment: "A button: the reader has had the ticket issued or picked it up.")
            }
            let done = UNNotificationAction(identifier: doneAction, title: title,
                                            icon: UNNotificationActionIcon(systemImageName: "checkmark"))
            let open = UNNotificationAction(identifier: openAction,
                                            title: String(localized: "Open Page",
                                                          comment: "A button under a notification: opens the web page the reader kept for paying or picking up a ticket."),
                                            options: .foreground,
                                            icon: UNNotificationActionIcon(systemImageName: "arrow.up.right.square"))
            return [UNNotificationCategory(identifier: category(of: kind, linked: false), actions: [done],
                                           intentIdentifiers: []),
                    UNNotificationCategory(identifier: category(of: kind, linked: true), actions: [done, open],
                                           intentIdentifiers: [])]
        })
    }

    /// The notification owed for `reminder` on `event` at `now`, printed on
    /// `clock`: nil where it asks for none, it is dealt with
    /// (``EventReminder/done``), its moment has been, or it falls
    /// past the event's day (``Event/holds(_:)``). So nothing comes for an event
    /// gone by, and nothing is left scheduled to come after an event moved to
    /// an earlier day is over, with no way for the app to take it back.
    init?(reminder: EventReminder, event: Event, clock: TimeDisplay = .venue, at now: Date = .now) {
        guard reminder.done == nil, event.holds(reminder),
              let date = reminder.alertDate(in: event.timeZone), date > now
        else { return nil }
        eventID = event.id
        reminderID = reminder.id
        eventTitle = event.title
        title = ReminderKind.label(of: reminder.title)
        let time = event.printedTime(of: reminder, on: clock)
        // What is to be paid and where, after when: what the reader needs in
        // hand to go and do it.
        var words: [String] = [time]
        if let lead = reminder.lead, lead > 0 { words.append(ReminderLead.label(of: lead)) }
        if reminder.ticketKind != nil {
            if let owed = reminder.owed { words.append(owed.formatted) }
            if let place = reminder.payAt { words.append(place) }
        }
        body = words.joined(separator: " · ")
        self.date = date
        isTimeSensitive = (reminder.lead ?? 0) < Self.calmLead
        link = reminder.ticketKind == nil ? nil : reminder.link
        category = reminder.ticketKind.map { Self.category(of: $0, linked: reminder.link != nil) }
    }

    /// The notifications owed: every reminder on `events` with one to come
    /// and something still to say (``Tracking/owes(_:)``), the soonest first,
    /// up to ``limit``.
    static func due(in events: [Event], tracking: (Event) -> Tracking, clock: TimeDisplay = .venue,
                    at now: Date = .now) -> [ReminderAlert] {
        var owed: [ReminderAlert] = []
        for event in events {
            let record = tracking(event)
            for reminder in record.reminders where record.owes(reminder) {
                if let alert = ReminderAlert(reminder: reminder, event: event, clock: clock, at: now) {
                    owed.append(alert)
                }
            }
        }
        owed.sort { $0.date != $1.date ? $0.date < $1.date : $0.identifier < $1.identifier }
        return Array(owed.prefix(limit))
    }

    nonisolated static func identifier(of reminder: EventReminder.ID, at event: Event.ID) -> String {
        "\(prefix)\(event).\(reminder.uuidString)"
    }

    var identifier: String { Self.identifier(of: reminderID, at: eventID) }

    private var interruptionLevel: UNNotificationInterruptionLevel {
        isTimeSensitive ? .timeSensitive : .active
    }

    /// A trigger by interval, since the moment is an instant at the hall
    /// rather than an hour on whatever clock the phone keeps by then.
    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = eventTitle
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel
        // One event's stack together, however many times its day has.
        content.threadIdentifier = "event-reminders-\(eventID)"
        var info = [Self.eventKey: eventID, Self.reminderKey: reminderID.uuidString]
        if let link { info[Self.linkKey] = link.absoluteString }
        content.userInfo = info
        if let category { content.categoryIdentifier = category }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// Whether `request` is this notification as it would be scheduled now —
    /// within a minute of the same moment, the same words and just as urgent.
    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        guard let request,
              let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return false }
        return abs(next.timeIntervalSince(date)) < 60
            && request.content.title == title
            && request.content.subtitle == eventTitle
            && request.content.body == body
            && request.content.interruptionLevel == interruptionLevel
            && request.content.categoryIdentifier == (category ?? "")
            && request.content.userInfo[Self.linkKey] as? String == link?.absoluteString
    }
}

extension Event {
    /// Whether `reminder` falls by the end of this event's day: as late as one
    /// can be written (``EventReminderView``). An event moved to an earlier day
    /// leaves its reminders where they were written, and they stay to be read.
    func holds(_ reminder: EventReminder) -> Bool {
        reminder.date(in: timeZone) < dayEnds
    }

    /// When `reminder` falls, as it is printed on `clock`: the time alone on
    /// the day the event is printed on, and with its date on any other.
    func printedTime(of reminder: EventReminder, on clock: TimeDisplay) -> String {
        let date = reminder.date(in: timeZone)
        // The reader's clock whether or not the event has a time to move onto
        // it: this one has.
        let zone = clock == .local ? TimeZone.current : timeZone
        let shown = shown(on: clock)
        let eventDay = CalendarDay(shown.date, in: .gregorian(in: shown.timeZone))
        guard CalendarDay(date, in: .gregorian(in: zone)) == eventDay else {
            return date.formatted(.gregorian(in: zone).month().day().hour().minute())
        }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }
}
