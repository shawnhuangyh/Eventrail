import Foundation
import Observation
import OSLog
import UserNotifications

/// A notification at eight in the evening of the day a lottery's results come
/// out, saying they are in and that how it went can be written down. Tapped,
/// it opens the ticket sheet on that round's own page.
///
/// One for every lottery round still waiting on a result (``LotteryList``,
/// ``LotteryEntry/isPending``) whose results day is written down — a
/// first-come round has nothing to announce, and a round with no day has no
/// evening to come on. A result written down before then takes it back; a day
/// moved moves it.
///
/// Eight on the reader's own clock, whatever the hall's: a results day is a
/// date with no clock (``CalendarDay``), and the trigger is left floating, so
/// it comes at eight wherever the phone is that evening. Results are usually
/// in by mid-afternoon in Japan, so eight in the evening anywhere east of
/// Hawaii is after them.
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
        super.init()
        center.delegate = self
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
    /// and `entry` is a lottery saved with a results day whose evening is
    /// still to come — the moment the reader shows they want to hear about
    /// it. Asks nothing with the switch off, or where the system has already
    /// been answered either way.
    func askIfNeeded(for entry: LotteryEntry) {
        guard isEnabled, entry.isLottery, entry.isPending,
              let day = entry.day, let evening = LotteryReminder.evening(of: day), evening > .now
        else { return }
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
        // The library may well have been written while the prompt was up.
        rescheduleSoon()
    }

    /// Reads again what the system says — for Settings, which shows a
    /// refusal under the switch.
    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// What is pending made to match what the library is waiting on, and the
    /// reminders already delivered for rounds that have since been answered
    /// taken out of Notification Center.
    private func reconcile() async {
        guard let store else { return }
        let list = LotteryList(events: store.upcoming) { store.tracking(for: $0) }
        await refreshAuthorization()

        let due = isEnabled && canNotify ? LotteryReminder.due(in: list) : []
        let wanted = Dictionary(due.map { ($0.identifier, $0) }) { first, _ in first }
        let scheduled = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(LotteryReminder.prefix) }

        let gone = scheduled.map(\.identifier).filter { wanted[$0] == nil }
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }

        let held = Dictionary(scheduled.map { ($0.identifier, $0) }) { first, _ in first }
        for reminder in due where !reminder.isScheduled(as: held[reminder.identifier]) {
            do {
                try await center.add(reminder.request)
            } catch {
                Self.log.error("A results-day reminder could not be scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }

        // A reminder already shown stays until its round has a result, or
        // has gone — then it has nothing left to ask.
        let waiting = LotteryReminder.waiting(in: list)
        let answered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(LotteryReminder.prefix) && !waiting.contains($0) }
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let event = info[LotteryReminder.eventKey] as? String,
              let entry = (info[LotteryReminder.entryKey] as? String).flatMap(UUID.init(uuidString:))
        else { return }
        await MainActor.run { self.opened = Opened(eventID: event, entryID: entry) }
    }
}

/// One results-day reminder: the round it is about, and when it comes.
nonisolated struct LotteryReminder: Hashable {
    let eventID: Event.ID
    let entryID: LotteryEntry.ID
    let eventTitle: String
    let round: String
    let day: CalendarDay

    /// The hour it comes at, on the reader's clock.
    static let hour = 20
    /// How many are scheduled at once, the soonest first. iOS keeps an app's
    /// 64 soonest and drops the rest without a word; the ones past these are
    /// scheduled as the earlier ones are delivered and the app next opens.
    static let limit = 60

    static let prefix = "lottery-results/"
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
    }

    var identifier: String { "\(Self.prefix)\(eventID)/\(entryID.uuidString)" }

    /// Eight in the evening of `day`, on `calendar`'s clock.
    static func evening(of day: CalendarDay, in calendar: Calendar = .current) -> Date? {
        calendar.date(from: components(of: day))
    }

    /// The trigger's date, with no zone: it comes at eight wherever the
    /// phone is that evening.
    private static func components(of day: CalendarDay) -> DateComponents {
        DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: 0)
    }

    /// The reminders owed: every round in `list` still waiting on a result
    /// with a results day whose evening has not yet come, the soonest first,
    /// up to ``limit``.
    static func due(in list: LotteryList, asOf now: Date = .now, calendar: Calendar = .current) -> [LotteryReminder] {
        let dated = list.rows.compactMap { row -> (evening: Date, row: LotteryRow, reminder: LotteryReminder)? in
            guard row.entry.isPending, let reminder = LotteryReminder(row),
                  let evening = evening(of: reminder.day, in: calendar), evening > now
            else { return nil }
            return (evening, row, reminder)
        }
        return dated
            .sorted { $0.evening != $1.evening ? $0.evening < $1.evening : LotteryRow.byResultsDay($0.row, $1.row) }
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
        let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(of: day), repeats: false)
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
    /// same evening and the same words, which change with the event's title
    /// or the app's language.
    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        guard let request,
              let trigger = request.trigger as? UNCalendarNotificationTrigger
        else { return false }
        let when = trigger.dateComponents
        return when.year == day.year && when.month == day.month && when.day == day.day
            && when.hour == Self.hour
            && request.content.title == title
            && request.content.subtitle == eventTitle
            && request.content.body == body
    }
}
