#if !targetEnvironment(macCatalyst)
import BackgroundTasks
#endif
import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// A notification when somebody the reader follows has a date published that
/// was not there before: the Following tab's New, said without the tab being
/// opened.
///
/// Read by a background refresh (``refreshInBackground()``), and only what is
/// stale — the listings the app would read by itself on opening the tab
/// (``FollowedDates/freshness``) — one at a time and stopping at a refusal, as
/// every read of them does: the one read longest ago first, for ``budget`` at
/// most. A date is news only against a listing this device already held. A
/// performer read for the first time — just followed, or after Clear Cache —
/// brings every date at once, and none of it is news; nor is a date the
/// reader has read, on any device (the mark syncs), or one already in their
/// library, which they put there. A read the app makes in the foreground, as
/// the tab or the Me card opens, announces nothing: the reader is looking.
///
/// One notification a read, however many dates it found, posted at once
/// rather than scheduled — so it takes none of the 64 pending the reminders
/// share. Tapped, it opens the date, or the Following tab for several, and it
/// leaves Notification Center once every date it named is read
/// (``tidy(from:followed:)``).
///
/// **Off until the reader turns it on**, per device: it is the app asking
/// Eventernote for pages while nobody is looking. Turned on, it asks for
/// notifications where nobody has answered yet. Not on a Mac, which runs no
/// background refresh.
@MainActor
@Observable
final class NewDateAlerts {
    static let shared = NewDateAlerts()

    /// The per-device preference in `UserDefaults`.
    static let storageKey = "newDateAlertsEnabled"

    /// The background refresh, named in the app's Info.plist under
    /// `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated static let refreshTask = "moe.shawn.Eventrail.followedDates"

    /// How long a background read may go on. iOS allows an app refresh about
    /// thirty seconds, and the write and the notification come after it.
    static let budget: Duration = .seconds(20)

    /// The soonest a background read is asked for, however stale a listing
    /// already is.
    static let soonest: TimeInterval = 15 * 60

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "following")

    /// Where there is a background refresh to read by: not a Mac.
    static var isOffered: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }

    /// Whether this device reads the followed listings in the background and
    /// says what is new. Off until the reader turns it on.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
            scheduleRefresh()
            guard isEnabled else { return }
            Task { await askIfNeeded() }
        }
    }

    /// Whether the system lets the app refresh in the background at all —
    /// for Settings, which says so where it does not.
    private(set) var backgroundRefresh: UIBackgroundRefreshStatus

    /// The dates a tapped alert named, until ``RootView`` opens them. Handed
    /// over by ``LotteryReminders``, the app's one notification delegate.
    var opened: [Event.ID]?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var pendingTidy: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.storageKey)
        backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
        NotificationCenter.default.addObserver(
            forName: UIApplication.backgroundRefreshStatusDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NewDateAlerts.shared.backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
            }
        }
    }

    /// Asks the system for the right to notify, where nobody has answered yet
    /// — the switch thrown on is the reader asking.
    private func askIfNeeded() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("Notifications could not be asked for: \(error.localizedDescription, privacy: .public)")
        }
        // Settings reads every switch's refusal off the results-day reminders'.
        await LotteryReminders.shared.refreshAuthorization()
    }

    private func canNotify() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    // MARK: - Reading in the background

    /// Asks for the next background read: once the first followed listing
    /// goes stale, and no sooner than ``soonest``. Taken back with the switch
    /// off, or nobody followed. Each ask replaces the one before.
    func scheduleRefresh() {
        #if !targetEnvironment(macCatalyst)
        let launch = Launch.shared
        guard isEnabled, let stale = launch.followed.staleAt(for: launch.store.followedProfiles) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTask)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTask)
        request.earliestBeginDate = max(stale, Date.now.addingTimeInterval(Self.soonest))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Refused in the Simulator, which runs no background refresh.
            Self.log.notice("The background read could not be asked for: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// The background refresh: the stale listings read, and what they brought
    /// said. Asks for the next one either way.
    func refreshInBackground() async {
        defer { scheduleRefresh() }
        guard Self.isOffered, isEnabled, await canNotify() else { return }
        let launch = Launch.shared
        let store = launch.store
        let followed = launch.followed
        // Nobody, where the store would not open yet: nothing is read, and no
        // listing forgotten for want of a follow it could not see.
        let performers = store.followedProfiles
        guard !performers.isEmpty else { return }
        let before = followed.dates
        await followed.loadInBackground(for: performers, within: Self.budget)
        let arrived = Self.arrivals(from: before, to: followed.dates)
        guard !arrived.isEmpty else { return }
        await announce(arrived, store: store, followed: followed, performers: performers)
    }

    /// The dates `after` holds that `before` held nowhere, among the
    /// performers whose listing `before` held: a performer read for the first
    /// time brings every date at once, and none of it is news.
    nonisolated static func arrivals(from before: [PerformerProfile.ID: [Event]],
                                     to after: [PerformerProfile.ID: [Event]]) -> Set<Event.ID> {
        let held = Set(before.values.joined().map(\.id))
        var arrived = Set<Event.ID>()
        for (performer, listing) in after where before[performer] != nil {
            for event in listing where !held.contains(event.id) { arrived.insert(event.id) }
        }
        return arrived
    }

    /// Posts one notification for the dates among `arrived` still worth
    /// saying: listed, unread and not already kept — and not named by an
    /// alert still in Notification Center, which a read whose write never
    /// landed would find again.
    private func announce(_ arrived: Set<Event.ID>, store: EventStore, followed: FollowedDates,
                          performers: [PerformerProfile]) async {
        let told = Set(await center.deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(NewDateAlert.prefix) }
            .flatMap { NewDateAlert.events(in: $0.request.content.userInfo) })
        let dates = followed.events(for: performers).filter { event in
            arrived.contains(event.id) && !told.contains(event.id)
                && !store.isInLibrary(event) && store.unread(event) == .new
        }
        guard let alert = NewDateAlert(dates: dates, names: { event in
            followed.billed(on: event, among: performers).map(\.name)
        }, clock: TimeDisplay.stored) else { return }
        do {
            try await center.add(alert.request)
        } catch {
            Self.log.error("New dates could not be announced: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Tidying

    /// Takes out of Notification Center an alert every date of which has
    /// since been read, or has gone — a second after the library last
    /// changed, as the reminders are scheduled.
    func tidy(from store: EventStore, followed: FollowedDates) {
        pendingTidy?.cancel()
        pendingTidy = Task { [weak self, weak store, weak followed] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let store, let followed else { return }
            let delivered = await center.deliveredNotifications()
                .filter { $0.request.identifier.hasPrefix(NewDateAlert.prefix) }
            guard !delivered.isEmpty else { return }
            let unread = Set(followed.events(for: store.followedProfiles)
                .filter { store.unread($0) == .new }
                .map(\.id))
            let spent = delivered
                .filter { !NewDateAlert.events(in: $0.request.content.userInfo).contains(where: unread.contains) }
                .map(\.request.identifier)
            if !spent.isEmpty { center.removeDeliveredNotifications(withIdentifiers: spent) }
        }
    }
}

/// One notification of dates new on the Following tab: the date itself where
/// there is one, and how many, by whom, where there are several.
struct NewDateAlert: Hashable {
    nonisolated static let prefix = "newDates."
    nonisolated static let eventsKey = "events"

    /// How many dates the body names one by one, soonest first; past them it
    /// says how many more.
    static let listed = 3
    /// How many performers the subtitle names.
    static let named = 3

    let identifier: String
    let title: String
    let subtitle: String
    let body: String
    /// The dates it is about, soonest first — what a tap opens.
    let events: [Event.ID]

    /// The alert for `dates`, soonest first, each billing whoever `names`
    /// says of the people followed, printed on `clock`. Nil for none.
    init?(dates: [Event], names: (Event) -> [String], clock: TimeDisplay, id: UUID = UUID()) {
        guard let first = dates.first else { return nil }
        identifier = Self.prefix + id.uuidString
        events = dates.map(\.id)
        // Each once, in the order the dates bill them.
        var seen = Set<String>()
        let people = dates.flatMap(names).filter { seen.insert($0).inserted }
        if dates.count == 1 {
            title = people.isEmpty
                ? String(localized: "New date",
                         comment: "A notification's title: a date newly published for somebody followed.")
                : String(localized: "New date for \(people.formatted(.list(type: .and)))",
                         comment: "A notification's title. The argument names who is billed among the people followed.")
            subtitle = first.title
            let shown = first.shown(on: clock)
            let when = [shown.dayLine, shown.timeLine].compactMap(\.self).joined(separator: " ")
            body = first.isAtHall ? "\(when) · \(first.venue)" : when
        } else {
            title = String(localized: "\(dates.count) new dates",
                           comment: "A notification's title: how many dates were newly published for the people followed.")
            subtitle = Self.list(people)
            var lines = dates.prefix(Self.listed).map { "\(Self.shortDay(of: $0.shown(on: clock))) \($0.title)" }
            if dates.count > Self.listed {
                lines.append(String(localized: "and \(dates.count - Self.listed) more",
                                    comment: "The last line of a new-dates notification: how many dates it did not list."))
            }
            body = lines.joined(separator: "\n")
        }
    }

    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        // Each read's alert stacked with the last.
        content.threadIdentifier = "new-dates"
        content.userInfo = [Self.eventsKey: events]
        // Now, rather than at a moment: nothing is held pending.
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    /// The dates a delivered alert named.
    nonisolated static func events(in userInfo: [AnyHashable: Any]) -> [Event.ID] {
        userInfo[eventsKey] as? [String] ?? []
    }

    /// Up to ``named`` people, and how many more.
    private static func list(_ people: [String]) -> String {
        guard people.count > named else { return people.formatted(.list(type: .and)) }
        let others = String(localized: "\(people.count - named) others",
                            comment: "The end of a list of performers in a notification: how many it did not name.")
        return (people.prefix(named) + [others]).formatted(.list(type: .and))
    }

    /// "Nov 14", on the clock the event is printed on.
    private static func shortDay(of event: Event) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = event.timeZone
        return event.date.formatted(style)
    }
}
