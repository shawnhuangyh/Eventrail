import Foundation
import Observation
import OSLog
import UserNotifications

/// A notification when a read finds an event the reader keeps, still to come,
/// on another day, at another start or in another hall than the library held
/// — what decides whether they can still be there. Tapped, it opens the
/// event's sheet on its What Changed card (``ListingChangesCard``): what it
/// was and what it is now.
///
/// **Only what the app reads anyway** (``EventStore/onMoved``): the account's
/// history, read by itself once stale and by Refresh, and the pages Refresh
/// reads again. Not a read made by the event's own sheet, which the reader is
/// looking at, nor the first read of an event that has just arrived, nor a
/// copy another device read and iCloud brought — that device says it. Nothing
/// is read for it, so it reads nothing in the background, and is said on a
/// Mac as anywhere.
///
/// Said once the refresh that found it is over, so a day found moved by the
/// history and a start by the page after it are one alert. One for each
/// event, posted at once rather than scheduled — so it takes none of the 64
/// pending the reminders share — and filed under the event, so a second
/// change replaces the first. It says what moved since the copy the reader
/// last read, where this device holds it (``ReadCopies``), else since what an
/// alert still in Notification Center said, else since what the library held;
/// a change that brings the event back to that says nothing, and takes the
/// alert back. It leaves Notification Center once the event is read, taken
/// out or over (``tidy(from:)``).
///
/// **On until the reader turns it off**, per device, as the reminders are: a
/// kept event is the reader meaning to be there. Nothing asks the system
/// for it but the switch turned back on.
@MainActor
@Observable
final class ChangeAlerts {
    static let shared = ChangeAlerts()

    /// The per-device preference in `UserDefaults`.
    static let storageKey = "changeAlertsEnabled"

    /// How long after the last change found the alerts go out, a refresh
    /// still running waited for besides.
    static let settle: Duration = .seconds(2)

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "library")

    /// Whether this device says when a kept event moves. On until the reader
    /// turns it off.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
            if !isEnabled { waiting = [:] }
            guard isEnabled else { return }
            Task { await askIfNeeded() }
        }
    }

    /// The event a tapped alert named, and what the alert said it was, until
    /// ``RootView`` opens it. Handed over by ``LotteryReminders``, the app's
    /// one notification delegate.
    var opened: Opened?

    struct Opened: Equatable {
        let eventID: Event.ID
        /// The copy the alert said the event moved from, for the sheet's
        /// card where this device holds no copy the reader read.
        let before: ListingCopy?
    }

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private weak var store: EventStore?
    /// What was found and not yet said, by event: the first copy found moved
    /// from, which a later read in the same refresh does not replace.
    @ObservationIgnored private var waiting: [Event.ID: EventMove] = [:]
    @ObservationIgnored private var pendingPost: Task<Void, Never>?
    @ObservationIgnored private var pendingTidy: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.storageKey) as? Bool ?? true
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

    // MARK: - Saying it

    /// Takes in what a read found moved, to be said once the refresh is over.
    func noticed(_ move: EventMove, in store: EventStore) {
        guard isEnabled else { return }
        self.store = store
        if waiting[move.eventID] == nil { waiting[move.eventID] = move }
        postSoon()
    }

    /// Posts what is waiting ``settle`` after the last change found, and not
    /// while a refresh is still reading — each run waiting for the one before
    /// it, so two never read Notification Center over each other.
    private func postSoon() {
        let previous = pendingPost
        previous?.cancel()
        pendingPost = Task { [weak self] in
            await previous?.value
            try? await Task.sleep(for: ChangeAlerts.settle)
            while !Task.isCancelled, self?.store?.isRefreshing == true {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, let self else { return }
            await post()
        }
    }

    private func post() async {
        guard let store, !waiting.isEmpty else { return }
        let moves = Array(waiting.values)
        waiting = [:]
        guard isEnabled, await canNotify() else { return }
        let delivered = Dictionary(
            await center.deliveredNotifications()
                .map(\.request)
                .filter { $0.identifier.hasPrefix(ChangeAlert.prefix) }
                .map { ($0.identifier, $0.content.userInfo) }
        ) { first, _ in first }
        let clock = TimeDisplay.stored
        for move in moves {
            // As it stands now: the reader may have opened it, or taken it
            // out, while the refresh went on.
            guard let event = store.event(id: move.eventID), store.isInLibrary(event), event.isUpcoming,
                  store.isUnread(event)
            else { continue }
            let identifier = ChangeAlert.identifier(for: event.id)
            let told = delivered[identifier].flatMap(ChangeAlert.before(in:))
            let before = store.copyRead(of: event) ?? told ?? move.found
            guard let alert = ChangeAlert(from: before, to: event, clock: clock) else {
                // Back as the reader last knew it: nothing left to say.
                if delivered[identifier] != nil { center.removeDeliveredNotifications(withIdentifiers: [identifier]) }
                continue
            }
            do {
                try await center.add(alert.request)
            } catch {
                Self.log.error("A change could not be announced: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Tidying

    /// Takes out of Notification Center an alert whose event has since been
    /// read, taken out of the library or gone by — a second after the
    /// library last changed, as the reminders are scheduled.
    func tidy(from store: EventStore) {
        pendingTidy?.cancel()
        pendingTidy = Task { [weak self, weak store] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let store else { return }
            let delivered = await center.deliveredNotifications()
                .map(\.request)
                .filter { $0.identifier.hasPrefix(ChangeAlert.prefix) }
            guard !delivered.isEmpty else { return }
            let spent = delivered.filter { request in
                // An event this device holds nothing of — a store not open
                // yet — keeps its alert.
                guard let id = ChangeAlert.event(in: request.content.userInfo),
                      let event = store.event(id: id)
                else { return false }
                return !store.isInLibrary(event) || !event.isUpcoming || !store.isUnread(event)
            }
            .map(\.identifier)
            if !spent.isEmpty { center.removeDeliveredNotifications(withIdentifiers: spent) }
        }
    }
}

/// A kept event a read found moved: which, and the copy the library held
/// before the read — see ``ChangeAlerts``.
nonisolated struct EventMove: Hashable, Sendable {
    /// What moved, in the order an alert says it: the day, the start, the
    /// hall — what decides whether the reader can still be there.
    enum Kind: Hashable, Sendable, CaseIterable {
        case day, start, venue
    }

    let eventID: Event.ID
    /// The copy held before the read that found it moved.
    let found: ListingCopy

    /// What moved from `before` to `event`.
    static func kinds(from before: ListingCopy, to event: Event) -> [Kind] {
        ListingChanges(from: before, to: event).map { kinds(in: $0, from: before) } ?? []
    }

    /// Of `changes`, what moved. **A start printed for the first time is not
    /// a move**, nor a hall named where a placeholder stood (`!_…`): both are
    /// news of another kind, and every event announced without them would
    /// say so. Nor is a hall respelled — its width, case or spacing.
    static func kinds(in changes: ListingChanges, from before: ListingCopy) -> [Kind] {
        var kinds: [Kind] = []
        if changes.changed(.day) { kinds.append(.day) }
        if before.startsAt != nil, changes.changed(.time(.startsAt)) { kinds.append(.start) }
        for case let .venue(was, now) in changes.changes
        where Event.namesHall(was) && Event.namesHall(now) && !sameHall(was, now) {
            kinds.append(.venue)
        }
        return kinds
    }

    /// Whether two names are one hall's, written another way.
    static func sameHall(_ one: String, _ other: String) -> Bool {
        folded(one) == folded(other)
    }

    private static func folded(_ name: String) -> String {
        String(name.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }).lowercased()
    }
}

/// One notification that a kept event moved: what moved, on the event's
/// title, and each move from what it was to what it is now, on Settings'
/// clock.
nonisolated struct ChangeAlert: Hashable {
    static let prefix = "eventChange."
    static let eventKey = "event"
    static let beforeKey = "before"

    let identifier: String
    let eventID: Event.ID
    let title: String
    let subtitle: String
    let body: String
    let kinds: [EventMove.Kind]
    /// The copy it says the event moved from, which a tap hands the sheet.
    let before: ListingCopy

    /// The alert for `event` having moved from `before`, printed on `clock`,
    /// or nil where nothing has moved.
    init?(from before: ListingCopy, to event: Event, clock: TimeDisplay) {
        guard let changes = ListingChanges(from: before, to: event) else { return nil }
        let kinds = EventMove.kinds(in: changes, from: before)
        guard !kinds.isEmpty else { return nil }
        identifier = Self.identifier(for: event.id)
        eventID = event.id
        self.kinds = kinds
        self.before = before
        title = Self.title(for: kinds)
        subtitle = event.title

        let (was, now) = changes.shown(on: clock)
        let yearChanged = Calendar.gregorian(in: was.timeZone).component(.year, from: was.date)
            != Calendar.gregorian(in: now.timeZone).component(.year, from: now.date)
        body = kinds.map { kind in
            switch kind {
            case .day:
                Self.line(String(localized: "Date"),
                          was: Self.day(of: was, withYear: yearChanged),
                          now: Self.day(of: now, withYear: yearChanged))
            case .start:
                Self.line(String(localized: "Start"), was: was.timeLine ?? "—", now: now.timeLine ?? "—")
            case .venue:
                Self.line(String(localized: "changes.venue"), was: before.venue, now: event.venue)
            }
        }
        .joined(separator: "\n")
    }

    static func identifier(for event: Event.ID) -> String { prefix + event }

    var request: UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = "event-changes"
        var info: [AnyHashable: Any] = [Self.eventKey: eventID]
        if let copy = try? JSONEncoder().encode(before) { info[Self.beforeKey] = copy }
        content.userInfo = info
        // Now, rather than at a moment: nothing is held pending.
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    /// The event a delivered alert named.
    static func event(in userInfo: [AnyHashable: Any]) -> Event.ID? {
        userInfo[eventKey] as? String
    }

    /// The copy a delivered alert said the event moved from.
    static func before(in userInfo: [AnyHashable: Any]) -> ListingCopy? {
        (userInfo[beforeKey] as? Data).flatMap { try? JSONDecoder().decode(ListingCopy.self, from: $0) }
    }

    private static func title(for kinds: [EventMove.Kind]) -> String {
        switch Set(kinds) {
        case [.day]:
            String(localized: "Date changed", comment: "A notification's title: an event the reader keeps moved to another day.")
        case [.start]:
            String(localized: "Start time changed", comment: "A notification's title: an event the reader keeps starts at another time.")
        case [.venue]:
            String(localized: "Venue changed", comment: "A notification's title: an event the reader keeps moved to another hall.")
        case [.day, .start]:
            String(localized: "Date and start time changed", comment: "A notification's title: an event the reader keeps moved to another day and time.")
        case [.day, .venue]:
            String(localized: "Date and venue changed", comment: "A notification's title: an event the reader keeps moved to another day and hall.")
        case [.start, .venue]:
            String(localized: "Start time and venue changed", comment: "A notification's title: an event the reader keeps moved to another time and hall.")
        default:
            String(localized: "Date, start time and venue changed", comment: "A notification's title: an event the reader keeps moved to another day, time and hall.")
        }
    }

    private static func line(_ label: String, was: String, now: String) -> String {
        String(localized: "\(label): \(was) → \(now)",
               comment: "A line of a notification that an event moved: what moved, what it was and what it is now.")
    }

    /// "Sat, Nov 14", with the year only where the move crosses one.
    private static func day(of event: Event, withYear: Bool) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        if withYear { style = style.year() }
        style.timeZone = event.timeZone
        return event.date.formatted(style)
    }
}
