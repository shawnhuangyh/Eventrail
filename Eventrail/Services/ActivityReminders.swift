import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// A notification as an event's Live Activity can first be started, saying
/// so. Tapped, it opens the event's sheet and starts the activity.
///
/// An activity is started from the sheet and never scheduled ahead, and only
/// from ``EventActivities/earliestStart(of:)``, eight hours before the event
/// is over (see ``EventActivities``) — so a reader who meant to have one had
/// to come back to the app at the right moment, and the sheet turned them
/// away before it. This is that moment, said: one for every kept event ahead
/// with a ticket and a published start, where this device shows Live
/// Activities and none is on for the event yet. Not before eight in the
/// morning on the reader's clock unless the event starts before then — a
/// show ending at noon could start its activity at four.
///
/// Scheduled as ``LotteryReminders`` schedules: from ``RootView``, from the
/// library as it stands, adding only what differs and taking back what no
/// longer applies — an activity started from the sheet takes its reminder
/// back. The soonest ``ActivityReminder/limit`` only: iOS keeps an app's 64
/// soonest, and the results-day reminders take the rest.
///
/// **Asked for at the moment it is wanted**, as the results-day reminder is:
/// on the ticket sheet's checkmark, for an event ahead that now has a ticket
/// (``askIfNeeded(for:tracking:)``), or as the switch is turned on — never at
/// launch. The system's prompt is the one both share.
@MainActor
@Observable
final class ActivityReminders {
    static let shared = ActivityReminders()

    /// The per-device preference in `UserDefaults`, as the results-day
    /// reminders' is.
    static let storageKey = "activityRemindersEnabled"

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "reminders")

    /// Whether this device can show a Live Activity at all: an iPhone. An
    /// iPad and a Mac have none, and Settings offers them no switch.
    static var isOffered: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .phone
        #endif
    }

    /// Whether this device reminds the reader. On until they turn it off, for
    /// the reason ``LotteryReminders/isEnabled`` is.
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

    // MARK: - Scheduling

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
    /// and `event`, with the ticket now written down, is owed a reminder.
    func askIfNeeded(for event: Event, tracking: Tracking) {
        guard isEnabled, Self.isOffered, EventActivities.shared.isEnabled,
              ActivityReminder(event: event, tracking: tracking) != nil
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
        rescheduleSoon()
    }

    /// What is pending made to match the library, and a reminder already
    /// shown taken out of Notification Center once its activity is on or its
    /// event has gone.
    private func reconcile() async {
        guard let store else { return }
        let status = await center.notificationSettings().authorizationStatus
        let canNotify = status == .authorized || status == .provisional || status == .ephemeral
        let activities = EventActivities.shared
        let running = Set(activities.statuses.keys)

        let due = isEnabled && canNotify && Self.isOffered && activities.isEnabled
            ? ActivityReminder.due(in: store.upcoming, tracking: store.tracking(for:), running: running)
            : []
        let wanted = Dictionary(due.map { ($0.identifier, $0) }) { first, _ in first }
        let scheduled = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ActivityReminder.prefix) }

        let gone = scheduled.map(\.identifier).filter { wanted[$0] == nil }
        if !gone.isEmpty { center.removePendingNotificationRequests(withIdentifiers: gone) }

        let held = Dictionary(scheduled.map { ($0.identifier, $0) }) { first, _ in first }
        for reminder in due where !reminder.isScheduled(as: held[reminder.identifier]) {
            do {
                try await center.add(reminder.request)
            } catch {
                Self.log.error("A Live Activity reminder could not be scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }

        // One already shown stands while it can still be acted on: its
        // event kept, with a ticket, and no activity on for it yet.
        let actionable = Set(store.upcoming.filter {
            store.tracking(for: $0).hasTicket && !running.contains($0.id)
        }.map { ActivityReminder.identifier(of: $0.id) })
        let spent = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(ActivityReminder.prefix) && !actionable.contains($0) }
        if !spent.isEmpty { center.removeDeliveredNotifications(withIdentifiers: spent) }
    }
}

/// One Live Activity reminder: the event it is about, and when it comes.
struct ActivityReminder: Hashable {
    let eventID: Event.ID
    let eventTitle: String
    /// When the activity can first be started, moved to eight in the morning
    /// where that falls in the night — see ``fireDate(earliest:starts:calendar:)``.
    let date: Date

    /// How many are scheduled at once, the soonest first: what iOS's 64
    /// leaves beside ``LotteryReminder/limit``.
    static let limit = 4
    /// The hour before which a reminder waits, on the reader's clock.
    static let morning = 8

    nonisolated static let prefix = "liveActivity."
    nonisolated static let eventKey = "event"

    /// The reminder owed `event` at `now`: kept and ahead, with a ticket and
    /// a published start, and a moment to come when its activity can start.
    init?(event: Event, tracking: Tracking, at now: Date = .now, calendar: Calendar = .current) {
        guard tracking.hasTicket, event.isUpcoming,
              let state = EventActivities.state(for: event, seat: "", at: now), now < state.runsTo
        else { return nil }
        let date = Self.fireDate(earliest: EventActivities.earliestStart(of: state),
                                 starts: state.starts, calendar: calendar)
        guard date > now else { return nil }
        eventID = event.id
        eventTitle = event.title
        self.date = date
    }

    /// When the activity can first start — but not in the small hours on the
    /// reader's `calendar`: eight that morning instead, or the event's start
    /// where that is earlier still, and never before the activity can start.
    static func fireDate(earliest: Date, starts: Date, calendar: Calendar) -> Date {
        let calendar = calendar.asGregorian
        guard calendar.component(.hour, from: earliest) < morning,
              let eight = calendar.date(bySettingHour: morning, minute: 0, second: 0, of: earliest)
        else { return earliest }
        return max(earliest, min(eight, starts))
    }

    /// The reminders owed: every event in `events` with one to come and no
    /// activity `running`, the soonest first, up to ``limit``.
    static func due(in events: [Event], tracking: (Event) -> Tracking, running: Set<Event.ID>,
                    at now: Date = .now, calendar: Calendar = .current) -> [ActivityReminder] {
        events
            .filter { !running.contains($0.id) }
            .compactMap { ActivityReminder(event: $0, tracking: tracking($0), at: now, calendar: calendar) }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.eventID < $1.eventID }
            .prefix(limit)
            .map { $0 }
    }

    nonisolated static func identifier(of event: Event.ID) -> String { prefix + event }

    var identifier: String { Self.identifier(of: eventID) }

    /// A trigger by interval, since the moment is an instant — eight hours
    /// before the event ends, wherever the reader is — rather than an hour on
    /// whatever clock the phone keeps by then.
    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = eventTitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = "live-activity"
        content.userInfo = [Self.eventKey: eventID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    var title: String {
        String(localized: "Live Activity available",
               comment: "A notification's title, once an event's Live Activity can be started.")
    }

    var body: String {
        String(localized: "Tap to start the countdown on your Lock Screen.",
               comment: "A notification's text, once an event's Live Activity can be started.")
    }

    /// Whether `request` is this reminder as it would be scheduled now —
    /// within a minute of the same moment, and the same words.
    func isScheduled(as request: UNNotificationRequest?) -> Bool {
        guard let request,
              let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        else { return false }
        return abs(next.timeIntervalSince(date)) < 60
            && request.content.title == title
            && request.content.subtitle == eventTitle
            && request.content.body == body
    }
}
