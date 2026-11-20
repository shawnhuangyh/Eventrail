import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// A notification as a lottery's results come out, saying they are in and
/// that how it went can be written down; one ahead of the moment a round
/// stops taking applications (``LotteryDeadlineAlert``), as long ahead as
/// Settings says for every round (``deadlineLead``); and for a round won, one
/// ahead of its payment deadline, as long ahead, and one as its ticket can be
/// issued (``TicketStageAlert``). Tapped, each opens the ticket sheet on that
/// round's own page.
///
/// One for every lottery round still waiting on a result (``LotteryList``,
/// ``LotteryEntry/isPending``) whose results day is written down — a
/// first-come round has nothing to announce, and a round with no day has no
/// evening to come on. A result written down before then takes it back; a day
/// moved moves it.
///
/// At the time the results come out where one is written beside the day — a
/// wall clock at the hall (``LotteryEntry/resultsDate(in:)``), so an instant.
/// Otherwise at eight on the reader's own clock, whatever the hall's: a day
/// alone is a date with no clock (``CalendarDay``), and the trigger is left
/// floating, so it comes at eight wherever the phone is that evening. Results
/// are usually in by mid-afternoon in Japan, so eight in the evening anywhere
/// east of Hawaii is after them.
///
/// Scheduled the way ``WatchLink`` sends: from ``RootView``, a second after
/// the library last changed, as the app opens and as it comes back — always
/// from the library as it stands, adding only what differs from what is
/// already scheduled and taking back what no longer waits. Local
/// notifications, so nothing leaves the phone: each device that holds the
/// library schedules its own.
///
/// **Asked for at the moment it is wanted.** The switch is on until the
/// reader turns it off (``isEnabled``), but nothing is asked of the system
/// until a lottery round is saved with a results day still to come
/// (``askIfNeeded(for:)``) or the switch is turned on — so the system's prompt
/// comes as the reader writes the day down, not on a launch, and a library
/// synced in from another device never prompts on its own.
@MainActor
@Observable
final class LotteryReminders: NSObject {
    static let shared = LotteryReminders()

    /// The per-device preference in `UserDefaults`. Not synced, like the
    /// calendar's: the permission behind it was granted on this device alone.
    static let storageKey = "lotteryRemindersEnabled"

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "reminders")

    /// Whether this device reminds the reader on a results day. On until they
    /// turn it off: a results day written down is the reader asking to hear
    /// about it, and the system's own prompt is still the answer that counts.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
            Task {
                // The switch thrown on is the reader asking, as a day written
                // down is.
                if isEnabled, await center.notificationSettings().authorizationStatus == .notDetermined {
                    await requestAuthorization()
                } else {
                    rescheduleSoon()
                }
            }
        }
    }

    /// How many minutes before a round's application deadline its alert
    /// comes, and a won round's payment deadline — one answer for every
    /// round, a day until the reader picks another; nil for none. Per device,
    /// as the switch is (``deadlineLeadKey``), and governed by it.
    var deadlineLead: Int? {
        didSet {
            guard deadlineLead != oldValue else { return }
            UserDefaults.standard.set(deadlineLead ?? Self.noLead, forKey: Self.deadlineLeadKey)
            rescheduleSoon()
        }
    }

    static let deadlineLeadKey = "lotteryDeadlineLead"
    /// A day: applying and paying are done from home, with a day to find
    /// the time.
    static let defaultDeadlineLead = 24 * 60
    /// What Settings offers: an event reminder's leads, less At the Time —
    /// the moment it closes is too late to apply.
    static let deadlineLeads = ReminderLead.choices.filter { $0 > 0 }
    /// How "none" is written down, apart from nothing written yet, which is
    /// the default.
    private static let noLead = -1

    /// What the system last said about notifications from this app — read
    /// with every schedule, and as Settings opens. Nil until first read.
    private(set) var authorization: UNAuthorizationStatus?

    /// The round a tapped reminder named, until ``RootView`` opens it.
    var opened: Opened?

    struct Opened: Equatable {
        let eventID: Event.ID
        let entryID: LotteryEntry.ID
    }

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    /// The library the last schedule read, read again after the reader
    /// answers the system's prompt.
    @ObservationIgnored private weak var store: EventStore?
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// Made as the app launches (``MyApp``): the delegate has to be in place
    /// before launch finishes, or a reminder tapped to open the app is never
    /// heard.
    private override init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? true
        let lead = UserDefaults.standard.object(forKey: Self.deadlineLeadKey) as? Int ?? Self.defaultDeadlineLead
        deadlineLead = lead < 0 ? nil : lead
        super.init()
        center.delegate = self
        // The buttons under a ticket to-do's notification, which the system
        // has to know of before one of them is pressed.
        center.setNotificationCategories(TicketStageAlert.categories)
    }

    /// Whether the system lets a reminder be shown at all.
    var canNotify: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    // MARK: - Scheduling

    /// Brings what is scheduled into line with `store` a second from now —
    /// once after a burst of edits rather than once for each.
    ///
    /// Each run waits for the one before it, so two never interleave their
    /// reads and writes of what is pending.
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
    /// and one of `entries` is a lottery saved with a results day whose
    /// moment is still to come, or a deadline whose alert is — the moment the
    /// reader shows they want to hear about it. `zone` is the hall's, which
    /// both are written on. Asks nothing with the switch off, or where the
    /// system has already been answered either way.
    func askIfNeeded(for entries: some Sequence<LotteryEntry>, in zone: TimeZone) {
        guard isEnabled,
              entries.contains(where: { Self.wantsReminding($0, in: zone, deadlineLead: deadlineLead) })
        else { return }
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            await requestAuthorization()
        }
    }

    /// A lottery still waiting, with a results day whose moment is to come,
    /// or a deadline whose alert, `deadlineLead` ahead of it, is — or a round
    /// won with a payment or a pickup still to come.
    private static func wantsReminding(_ entry: LotteryEntry, in zone: TimeZone, deadlineLead: Int?) -> Bool {
        if entry.isWon {
            return TicketStage.allCases.contains { stage in
                entry[stage]?.done == nil && (entry.date(of: stage, in: zone) ?? .distantPast) > .now
            }
        }
        guard entry.isLottery, entry.isPending else { return false }
        if let deadline = entry.deadline, let deadlineLead,
           deadline.alertDate(in: zone, lead: deadlineLead) > .now { return true }
        guard let day = entry.day,
              let moment = entry.resultsDate(in: zone) ?? LotteryReminder.evening(of: day)
        else { return false }
        return moment > .now
    }

    private func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("Notifications could not be asked for: \(error.localizedDescription, privacy: .public)")
        }
        // The library may well have been written while the prompt was up.
        rescheduleSoon()
    }

    /// Reads again what the system says — for Settings, which shows a
    /// refusal under the switch.
    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Marks the step a notification was about as reached, from the button
    /// under it (``TicketStageAlert/doneAction``), with every step before it
    /// (``LotteryEntry/reach(_:at:)``): Mark as Issued on a ticket whose
    /// payment was never marked marks it paid too, as its to-do's own button
    /// and Ticket Details would leave it. Written at once: the app may have
    /// been woken for this alone, and be put away again before a save a
    /// moment later would run.
    func markDone(_ stage: TicketStage, of entryID: LotteryEntry.ID, at eventID: Event.ID) {
        let store = store ?? Launch.shared.store
        guard let event = store.event(id: eventID) else { return }
        let record = store.tracking(for: event)
        store.setTracking(record.updatingLottery(entryID) { $0.reach(stage) }, for: event)
        store.saveNow()
        schedule(from: store)
    }

    /// What is pending made to match what the library is waiting on, and the
    /// reminders already delivered for rounds that have since been answered
    /// taken out of Notification Center.
    private func reconcile() async {
        guard let store else { return }
        let list = LotteryList(events: store.upcoming) { store.tracking(for: $0) }
        let won = TicketStageAlert.rows(in: store.upcoming) { store.tracking(for: $0) }
        await refreshAuthorization()

        // A deadline's words print its time, on Settings' clock.
        let due = isEnabled && canNotify
            ? LotteryAlert.due(in: list, won: won, deadlineLead: deadlineLead, clock: TimeDisplay.stored)
            : []
        let wanted = Dictionary(due.map { ($0.identifier, $0) }) { first, _ in first }
        let scheduled = await center.pendingNotificationRequests()
            .filter { LotteryAlert.isOwn($0.identifier) }

        let gone = scheduled.map(\.identifier).filter { wanted[$0] == nil }
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }

        let held = Dictionary(scheduled.map { ($0.identifier, $0) }) { first, _ in first }
        for reminder in due where !reminder.isScheduled(as: held[reminder.identifier]) {
            do {
                try await center.add(reminder.request)
            } catch {
                Self.log.error("A lottery reminder could not be scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }

        // A reminder already shown stays until its round has a result, or
        // has gone — then it has nothing left to ask — a deadline's until
        // the deadline has passed too, and a payment's or a pickup's until it
        // is marked.
        let waiting = LotteryReminder.waiting(in: list)
            .union(LotteryDeadlineAlert.standing(in: list))
            .union(TicketStageAlert.standing(in: won))
        let answered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { LotteryAlert.isOwn($0) && !waiting.contains($0) }
        if !answered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: answered) }
    }
}

extension LotteryReminders: UNUserNotificationCenterDelegate {
    /// Shown even with the app open: eight in the evening is as likely a time
    /// as any to be in it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// The app's one delegate, so a Live Activity reminder tapped is handed
    /// to ``ActivityReminders`` from here, an event's own to
    /// ``EventReminders``, a new date's to ``NewDateAlerts``, and a moved
    /// event's to ``ChangeAlerts``.
    ///
    /// **The completion handler, called on the main thread, and not this
    /// method's `async` form**: where a tap brings the app back, the system's
    /// handler updates its snapshot, which UIKit asserts is on the main thread,
    /// and the `async` form calls it wherever the task ended. Every such tap
    /// killed the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        #if DEBUG
        let identifier = TestNotification.routed(request.identifier)
        #else
        let identifier = request.identifier
        #endif
        let info = request.content.userInfo
        let take: @MainActor @Sendable () -> Void
        if identifier.hasPrefix(ActivityReminder.prefix) {
            let event = info[ActivityReminder.eventKey] as? String
            take = { ActivityReminders.shared.opened = event }
        } else if identifier.hasPrefix(ReminderAlert.prefix) {
            let event = info[ReminderAlert.eventKey] as? String
            take = { EventReminders.shared.opened = event }
        } else if identifier.hasPrefix(TicketStageAlert.prefix),
                  let event = info[LotteryReminder.eventKey] as? String,
                  let entry = (info[LotteryReminder.entryKey] as? String).flatMap(UUID.init(uuidString:)) {
            let stage = (info[TicketStageAlert.stageKey] as? String).flatMap(TicketStage.init(rawValue:))
            let link = (info[TicketStageAlert.linkKey] as? String).flatMap(QRCodeLink.link(inCode:))
            // One of the buttons under it, or the notification itself, which
            // opens the round's page as a results-day reminder does.
            switch response.actionIdentifier {
            case TicketStageAlert.doneAction:
                take = { if let stage { self.markDone(stage, of: entry, at: event) } }
            case TicketStageAlert.openAction:
                take = { if let link { UIApplication.shared.open(link) } }
            default:
                take = { self.opened = Opened(eventID: event, entryID: entry) }
            }
        } else if identifier.hasPrefix(NewDateAlert.prefix) {
            let events = NewDateAlert.events(in: info)
            take = { NewDateAlerts.shared.opened = events }
        } else if identifier.hasPrefix(ChangeAlert.prefix) {
            let event = ChangeAlert.event(in: info)
            let before = ChangeAlert.before(in: info)
            take = {
                if let event { ChangeAlerts.shared.opened = ChangeAlerts.Opened(eventID: event, before: before) }
            }
        } else if let event = info[LotteryReminder.eventKey] as? String,
                  // A results-day reminder, or a deadline's alert, which
                  // names its round the same way.
                  let entry = (info[LotteryReminder.entryKey] as? String).flatMap(UUID.init(uuidString:)) {
            take = { self.opened = Opened(eventID: event, entryID: entry) }
        } else {
            take = {}
        }
        // Not Sendable as UserNotifications declares it, and called only on the
        // main thread here, as it has to be.
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            take()
            done()
        }
    }
}

/// One results-day reminder: the round it is about, and when it comes.
nonisolated struct LotteryReminder: Hashable {
    let eventID: Event.ID
    let entryID: LotteryEntry.ID
    let eventTitle: String
    let round: String
    let day: CalendarDay
    /// The moment the results come out, where a time is written beside the
    /// day (``LotteryEntry/resultsDate(in:)``); nil comes at ``hour``.
    let announced: Date?

    /// The hour it comes at, on the reader's clock, where no time is written.
    static let hour = 20
    /// How many are scheduled at once, the soonest first — these and the
    /// deadlines' together (``LotteryAlert``). iOS keeps an app's 64 soonest
    /// and drops the rest without a word, and the Live Activity reminders and
    /// an event's own take the others (``ActivityReminder/limit``,
    /// ``ReminderAlert/limit``); the ones past these are scheduled as the
    /// earlier ones are delivered and the app next opens.
    static let limit = 40

    /// Shared with the Lotteries widget, which takes back the reminder for a
    /// round it was given a result from — see ``ResultsReminderID``.
    static let prefix = ResultsReminderID.prefix
    static let eventKey = "event"
    static let entryKey = "entry"

    /// The reminder for `row`'s round, where it has a results day to come on.
    init?(_ row: LotteryRow) {
        guard let day = row.entry.day else { return nil }
        eventID = row.event.id
        entryID = row.entry.id
        eventTitle = row.event.title
        round = row.entry.round
        self.day = day
        announced = row.entry.resultsDate(in: row.event.timeZone)
    }

    var identifier: String { ResultsReminderID.of(event: eventID, entry: entryID) }

    /// Eight in the evening of `day`, on `calendar`'s clock. The day is a
    /// Gregorian one whatever `calendar` counts in — see ``CalendarDay``.
    static func evening(of day: CalendarDay, in calendar: Calendar = .current) -> Date? {
        calendar.asGregorian
            .date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: 0))
    }

    /// The trigger's date, with no zone: it comes at eight wherever the
    /// phone is that evening.
    ///
    /// Written in `calendar`'s own terms — the phone's, which is what the
    /// system matches a trigger with no calendar against — era and all. The
    /// Gregorian year handed over as it stands was the year 2026 of Reiwa on
    /// a phone set to the Japanese calendar, which no evening ever reaches.
    static func components(of day: CalendarDay, in calendar: Calendar = .current) -> DateComponents {
        guard let evening = evening(of: day, in: calendar) else {
            return DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: 0)
        }
        return calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: evening)
    }

    /// When it comes: as the results come out, or at eight that evening on
    /// `calendar`'s clock.
    func fires(in calendar: Calendar = .current) -> Date? {
        announced ?? Self.evening(of: day, in: calendar)
    }

    /// The reminders owed: every round in `list` still waiting on a result
    /// with a results day whose moment has not yet come, the soonest first,
    /// up to ``limit``.
    static func due(in list: LotteryList, asOf now: Date = .now, calendar: Calendar = .current) -> [LotteryReminder] {
        let dated = list.rows.compactMap { row -> (fires: Date, row: LotteryRow, reminder: LotteryReminder)? in
            guard row.entry.isPending, let reminder = LotteryReminder(row),
                  let fires = reminder.fires(in: calendar), fires > now
            else { return nil }
            return (fires, row, reminder)
        }
        return dated
            .sorted { $0.fires != $1.fires ? $0.fires < $1.fires : LotteryRow.byResultsDay($0.row, $1.row) }
            .prefix(limit)
            .map(\.reminder)
    }

    /// Every round in `list` a reminder could still be standing for: waiting
    /// on a result, with a results day — come or not.
    static func waiting(in list: LotteryList) -> Set<String> {
        Set(list.rows.filter(\.entry.isPending).compactMap { LotteryReminder($0)?.identifier })
    }

    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = eventTitle
        content.body = body
        content.sound = .default
        // Several rounds out on one evening stack as one.
        content.threadIdentifier = "lottery-results"
        content.userInfo = [Self.eventKey: eventID, Self.entryKey: entryID.uuidString]
        // An instant at the hall where a time is written, so a trigger by
        // interval, as an event's own reminder has.
        let trigger: UNNotificationTrigger = if let announced {
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, announced.timeIntervalSinceNow), repeats: false)
        } else {
            UNCalendarNotificationTrigger(dateMatching: Self.components(of: day), repeats: false)
        }
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    var title: String {
        String(localized: "Lottery results are out",
               comment: "A notification's title, at 8 PM on the day a lottery round's results come out.")
    }

    var body: String {
        guard !round.isEmpty else {
            return String(localized: "Tap to record whether you won.",
                          comment: "A results-day notification's text, for a lottery round with no round name.")
        }
        return String(localized: "\(LotteryRound.label(of: round)) · Tap to record whether you won.",
                      comment: "A results-day notification's text. The argument is the round, such as Earliest Presale Lottery.")
    }

    /// Whether `request` is this reminder as it would be scheduled now — the
    /// same moment (within a minute) or evening, and the same words, which
    /// change with the event's title or the app's language.
    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        guard let request,
              request.content.title == title,
              request.content.subtitle == eventTitle,
              request.content.body == body
        else { return false }
        if let announced {
            guard let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            else { return false }
            return abs(next.timeIntervalSince(announced)) < 60
        }
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        let when = trigger.dateComponents, wanted = Self.components(of: day)
        return when.era == wanted.era && when.year == wanted.year && when.month == wanted.month
            && when.day == wanted.day && when.hour == wanted.hour
    }
}

/// A notification ahead of the moment a lottery round stops taking
/// applications (``LotteryDeadline``), saying it is about to close: the last
/// chance to put another 申込券 in. Tapped, it opens the ticket sheet on that
/// round, as a results-day reminder does — the same keys in its `userInfo`, so
/// the delegate reads the two alike.
///
/// Owed while the round is still waiting on a result and its alert is still
/// to come, as long before the deadline as Settings says for every round
/// (``LotteryReminders/deadlineLead``). Its moment is an instant at the hall,
/// so a trigger by interval; its words print the deadline on Settings' clock
/// — the day alone where no time was written — so a change of Time Zone
/// reschedules it. **Time Sensitive under a day's lead**, as an event's own
/// reminder is (``ReminderAlert/calmLead``): an hour before closing can't wait
/// for a Focus to end, and a day before can.
nonisolated struct LotteryDeadlineAlert: Hashable {
    let eventID: Event.ID
    let entryID: LotteryEntry.ID
    let eventTitle: String
    let body: String
    /// When it comes: the deadline less the lead.
    let date: Date
    let isTimeSensitive: Bool

    static let prefix = "lottery-deadline/"

    /// The alert owed for `row`'s round at `now`, `lead` minutes ahead of
    /// its deadline and printed on `clock`: nil where it has no deadline, is
    /// no lottery waiting on a result, falls past the event's day, or its
    /// moment has been. Past the event's day only where the event moved to an
    /// earlier one, leaving the deadline where it was written (the calendar
    /// offers none later): scheduled, it would come after the event is over,
    /// with no way for the app to take it back — as a goods sale's time
    /// (``Event/holds(_:)``).
    init?(_ row: LotteryRow, lead: Int, clock: TimeDisplay = .venue, at now: Date = .now) {
        let entry = row.entry
        guard entry.isLottery, entry.isPending, let deadline = entry.deadline,
              deadline.date(in: row.event.timeZone) < row.event.dayEnds
        else { return nil }
        let date = deadline.alertDate(in: row.event.timeZone, lead: lead)
        guard date > now else { return nil }
        self.init(event: row.event, entry: entry, deadline: deadline, lead: lead, comingAt: date, clock: clock)
    }

    /// The alert for `deadline` on `entry`, `lead` minutes ahead, coming at
    /// `date` whatever that says — what ``init(_:lead:clock:at:)`` makes once
    /// it is owed.
    init(event: Event, entry: LotteryEntry, deadline: LotteryDeadline, lead: Int, comingAt date: Date,
         clock: TimeDisplay) {
        eventID = event.id
        entryID = entry.id
        eventTitle = event.title
        let closes = event.printedClosing(of: deadline, on: clock)
        let when = String(localized: "Closes \(closes)",
                          comment: "When a lottery round stops taking applications. The argument is a date, with a time where one was written, such as Nov 20, 23:59.")
        body = entry.round.isEmpty ? when : "\(LotteryRound.label(of: entry.round)) · \(when)"
        self.date = date
        isTimeSensitive = lead < ReminderAlert.calmLead
    }

    static func identifier(of entry: LotteryEntry.ID, at event: Event.ID) -> String {
        "\(prefix)\(event)/\(entry.uuidString)"
    }

    var identifier: String { Self.identifier(of: entryID, at: eventID) }

    var title: String {
        String(localized: "Lottery applications close soon",
               comment: "A notification's title, ahead of the moment a lottery round stops taking applications.")
    }

    /// The alerts owed for `list`'s rounds, `lead` minutes ahead of each
    /// deadline, the soonest first.
    static func due(in list: LotteryList, lead: Int, clock: TimeDisplay = .venue,
                    at now: Date = .now) -> [LotteryDeadlineAlert] {
        list.rows.compactMap { LotteryDeadlineAlert($0, lead: lead, clock: clock, at: now) }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.identifier < $1.identifier }
    }

    /// Every round in `list` an alert already shown could still be standing
    /// for: waiting on a result, with a deadline not yet passed.
    static func standing(in list: LotteryList, at now: Date = .now) -> Set<String> {
        Set(list.rows.compactMap { row in
            guard row.entry.isLottery, row.entry.isPending,
                  let deadline = row.entry.deadline, deadline.date(in: row.event.timeZone) > now
            else { return nil }
            return identifier(of: row.entry.id, at: row.event.id)
        })
    }

    private var interruptionLevel: UNNotificationInterruptionLevel {
        isTimeSensitive ? .timeSensitive : .active
    }

    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = eventTitle
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel
        // Several closing on one night stack as one.
        content.threadIdentifier = "lottery-deadlines"
        content.userInfo = [LotteryReminder.eventKey: eventID, LotteryReminder.entryKey: entryID.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// Whether `request` is this alert as it would be scheduled now — within
    /// a minute of the same moment, the same words and just as urgent.
    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        guard let request,
              let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return false }
        return abs(next.timeIntervalSince(date)) < 60
            && request.content.title == title
            && request.content.subtitle == eventTitle
            && request.content.body == body
            && request.content.interruptionLevel == interruptionLevel
    }
}

/// What ``LotteryReminders`` schedules: a results-day reminder or a deadline's
/// alert, taken together so they share one limit (``LotteryReminder/limit``).
nonisolated enum LotteryAlert: Hashable {
    case results(LotteryReminder)
    case deadline(LotteryDeadlineAlert)
    case ticket(TicketStageAlert)

    var identifier: String {
        switch self {
        case .results(let reminder): reminder.identifier
        case .deadline(let alert): alert.identifier
        case .ticket(let alert): alert.identifier
        }
    }

    var request: UNNotificationRequest {
        switch self {
        case .results(let reminder): reminder.request
        case .deadline(let alert): alert.request
        case .ticket(let alert): alert.request
        }
    }

    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        switch self {
        case .results(let reminder): reminder.isScheduled(as: request)
        case .deadline(let alert): alert.isScheduled(as: request)
        case .ticket(let alert): alert.isScheduled(as: request)
        }
    }

    /// Whether a notification of this name is one of these.
    static func isOwn(_ identifier: String) -> Bool {
        identifier.hasPrefix(LotteryReminder.prefix) || identifier.hasPrefix(LotteryDeadlineAlert.prefix)
            || identifier.hasPrefix(TicketStageAlert.prefix)
    }

    /// Every one owed for `list` and the rounds `won`
    /// (``TicketStageAlert/rows(in:tracking:)``), the soonest first, up to
    /// ``LotteryReminder/limit`` between them — the deadlines and the
    /// payments `deadlineLead` minutes ahead, or none where that is nil.
    static func due(in list: LotteryList, won: [LotteryRow] = [], deadlineLead: Int?, clock: TimeDisplay = .venue,
                    asOf now: Date = .now, calendar: Calendar = .current) -> [LotteryAlert] {
        let results = LotteryReminder.due(in: list, asOf: now, calendar: calendar)
            .compactMap { reminder in reminder.fires(in: calendar).map { ($0, LotteryAlert.results(reminder)) } }
        let deadlines = deadlineLead.map { lead in
            LotteryDeadlineAlert.due(in: list, lead: lead, clock: clock, at: now).map { ($0.date, LotteryAlert.deadline($0)) }
        } ?? []
        let tickets = TicketStageAlert.due(in: won, paymentLead: deadlineLead, clock: clock, at: now)
            .map { ($0.date, LotteryAlert.ticket($0)) }
        return (results + deadlines + tickets)
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.identifier < $1.1.identifier }
            .prefix(LotteryReminder.limit)
            .map(\.1)
    }
}

/// A notification for a step of a won round: ahead of its payment deadline,
/// as long ahead as an application deadline's (``LotteryReminders/deadlineLead``),
/// or as its ticket can be issued. Its body says what is owed and where; its
/// buttons mark the step reached without opening the app, and open the page
/// the reader kept for it. Tapped, it opens the round's page, the same keys
/// in its `userInfo` as a results-day reminder's.
///
/// Owed while the round is won, the step not yet reached, and its moment
/// ahead. **Time Sensitive only for a payment under a day's lead**
/// (``ReminderAlert/calmLead``): a pickup only opens.
nonisolated struct TicketStageAlert: Hashable {
    let eventID: Event.ID
    let entryID: LotteryEntry.ID
    let stage: TicketStage
    let eventTitle: String
    let body: String
    /// When it comes: the moment less the lead.
    let date: Date
    let isTimeSensitive: Bool
    let link: URL?

    static let prefix = "lottery-ticket/"
    static let stageKey = "stage"
    static let linkKey = "link"
    /// The button that marks the step reached, without opening the app.
    static let doneAction = "ticketTodo.done"
    /// The button that opens the page the reader kept for it.
    static let openAction = "ticketTodo.open"

    /// The category of a notification for `stage`: each says what its button
    /// marks, and each again with the button for a page.
    static func category(of stage: TicketStage, linked: Bool) -> String {
        "ticketTodo.\(stage.rawValue)\(linked ? ".link" : "")"
    }

    /// Every category, for the system to be told of as the app launches.
    static var categories: Set<UNNotificationCategory> {
        Set(TicketStage.allCases.flatMap { stage in
            let title = switch stage {
            case .payment:
                String(localized: "Mark as Paid", comment: "A button: the reader has paid for the ticket.")
            case .pickup:
                String(localized: "Mark as Issued", comment: "A button: the reader has had the ticket issued or picked it up.")
            }
            let done = UNNotificationAction(identifier: doneAction, title: title,
                                            icon: UNNotificationActionIcon(systemImageName: "checkmark"))
            let open = UNNotificationAction(identifier: openAction,
                                            title: String(localized: "Open Page",
                                                          comment: "A button under a notification: opens the web page the reader kept for paying or picking up a ticket."),
                                            options: .foreground,
                                            icon: UNNotificationActionIcon(systemImageName: "arrow.up.right.square"))
            return [UNNotificationCategory(identifier: category(of: stage, linked: false), actions: [done],
                                           intentIdentifiers: []),
                    UNNotificationCategory(identifier: category(of: stage, linked: true), actions: [done, open],
                                           intentIdentifiers: [])]
        })
    }

    /// How far ahead of `stage` it comes: a payment as an application
    /// deadline does, or not at all where that is nil; a pickup as it opens.
    static func lead(of stage: TicketStage, paymentLead: Int?) -> Int? {
        switch stage {
        case .payment: paymentLead
        case .pickup: 0
        }
    }

    /// The alert owed for `stage` of `row`'s round at `now`, `lead` minutes
    /// ahead and printed on `clock`: nil where the round is not won, the step
    /// is not written or is reached, falls past the event's day, or its
    /// moment has been. Past the event's day only where the event moved to an
    /// earlier one, for the reason a deadline's alert isn't owed there
    /// (``LotteryDeadlineAlert/init(_:lead:clock:at:)``).
    init?(_ row: LotteryRow, stage: TicketStage, lead: Int, clock: TimeDisplay = .venue, at now: Date = .now) {
        let entry = row.entry
        guard entry.isWon, let moment = entry[stage], moment.done == nil,
              let due = entry.date(of: stage, in: row.event.timeZone), due < row.event.dayEnds
        else { return nil }
        let date = due.addingTimeInterval(-Double(lead) * 60)
        guard date > now else { return nil }
        self.init(event: row.event, entry: entry, stage: stage, lead: lead, comingAt: date, clock: clock)
    }

    /// The alert for `stage` of `entry`, `lead` minutes ahead, coming at
    /// `date` whatever that says — what ``init(_:stage:lead:clock:at:)``
    /// makes once it is owed.
    init(event: Event, entry: LotteryEntry, stage: TicketStage, lead: Int, comingAt date: Date, clock: TimeDisplay) {
        eventID = event.id
        entryID = entry.id
        self.stage = stage
        eventTitle = event.title
        let moment = entry[stage]
        // When, then what is to be paid and where: what the reader needs in
        // hand to go and do it.
        var words: [String] = []
        if !entry.round.isEmpty { words.append(LotteryRound.label(of: entry.round)) }
        if let due = entry.date(of: stage, in: event.timeZone) {
            words.append(moment?.minute == nil
                         ? due.formatted(.gregorian(in: event.timeZone).month().day())
                         : event.printedMoment(due, on: clock))
        }
        if lead > 0 { words.append(ReminderLead.label(of: lead)) }
        if stage == .payment, let owed = moment?.owed { words.append(owed.formatted) }
        if let place = moment?.payAt { words.append(place) }
        body = words.joined(separator: " · ")
        self.date = date
        isTimeSensitive = stage == .payment && lead < ReminderAlert.calmLead
        link = moment?.link
    }

    static func identifier(of stage: TicketStage, of entry: LotteryEntry.ID, at event: Event.ID) -> String {
        "\(prefix)\(event)/\(entry.uuidString)/\(stage.rawValue)"
    }

    var identifier: String { Self.identifier(of: stage, of: entryID, at: eventID) }

    var title: String {
        switch stage {
        case .payment:
            String(localized: "Payment Deadline",
                   comment: "A notification's title, and a section of a won lottery round: the last moment to pay for the ticket, 入金締切.")
        case .pickup:
            String(localized: "Ticket Pickup Opens",
                   comment: "A notification's title: from when a ticket won can be issued or collected, 発券開始.")
        }
    }

    /// Every round won on `events`, a first-come round's included — which a
    /// ``LotteryList`` leaves out.
    static func rows(in events: some Sequence<Event>, tracking: (Event) -> Tracking) -> [LotteryRow] {
        events.flatMap { event in
            tracking(event).lotteries.filter(\.isWon).map { LotteryRow(event: event, entry: $0) }
        }
    }

    /// The alerts owed for `rows`' rounds: payments `paymentLead` minutes
    /// ahead, or none where that is nil, and pickups as they open.
    static func due(in rows: [LotteryRow], paymentLead: Int?, clock: TimeDisplay = .venue,
                    at now: Date = .now) -> [TicketStageAlert] {
        var owed: [TicketStageAlert] = []
        for row in rows {
            for stage in TicketStage.allCases {
                guard let lead = lead(of: stage, paymentLead: paymentLead),
                      let alert = TicketStageAlert(row, stage: stage, lead: lead, clock: clock, at: now)
                else { continue }
                owed.append(alert)
            }
        }
        return owed.sorted { $0.date != $1.date ? $0.date < $1.date : $0.identifier < $1.identifier }
    }

    /// Every step of `rows` an alert already shown could still be standing
    /// for: of a round won, and not yet reached.
    static func standing(in rows: [LotteryRow]) -> Set<String> {
        var standing: Set<String> = []
        for row in rows where row.entry.isWon {
            for stage in TicketStage.allCases where row.entry[stage].map({ $0.done == nil }) == true {
                standing.insert(identifier(of: stage, of: row.entry.id, at: row.event.id))
            }
        }
        return standing
    }

    private var interruptionLevel: UNNotificationInterruptionLevel {
        isTimeSensitive ? .timeSensitive : .active
    }

    private var category: String { Self.category(of: stage, linked: link != nil) }

    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = eventTitle
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel
        content.threadIdentifier = "lottery-tickets"
        var info = [LotteryReminder.eventKey: eventID, LotteryReminder.entryKey: entryID.uuidString,
                    Self.stageKey: stage.rawValue]
        if let link { info[Self.linkKey] = link.absoluteString }
        content.userInfo = info
        content.categoryIdentifier = category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// Whether `request` is this alert as it would be scheduled now — within
    /// a minute of the same moment, the same words, buttons and page, and
    /// just as urgent.
    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        guard let request,
              let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return false }
        return abs(next.timeIntervalSince(date)) < 60
            && request.content.title == title
            && request.content.subtitle == eventTitle
            && request.content.body == body
            && request.content.interruptionLevel == interruptionLevel
            && request.content.categoryIdentifier == category
            && request.content.userInfo[Self.linkKey] as? String == link?.absoluteString
    }
}

nonisolated extension Event {
    /// "Nov 20, 23:59": `date`, as an event's other times are printed on
    /// `clock` — the hall's, or the reader's.
    func printedMoment(_ date: Date, on clock: TimeDisplay) -> String {
        let zone = clock == .local ? TimeZone.current : timeZone
        return date.formatted(.gregorian(in: zone).month().day().hour().minute())
    }

    /// When `deadline` closes: the moment on `clock` where a time was
    /// written, else "Nov 20" — a day alone is the hall's day whatever the
    /// clock, as a results day is.
    func printedClosing(of deadline: LotteryDeadline, on clock: TimeDisplay) -> String {
        guard deadline.minute != nil else {
            return deadline.day.date(in: .gregorian()).formatted(.gregorian().month().day())
        }
        return printedMoment(deadline.date(in: timeZone), on: clock)
    }
}
