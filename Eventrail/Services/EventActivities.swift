@preconcurrency import ActivityKit
import BackgroundTasks
import SwiftUI
import UIKit

/// The Live Activities the app has started or scheduled — at most one per
/// event — and what keeps each in step with its night.
///
/// **An activity is asked for from the event's sheet, and comes on two hours
/// before the doors** (``EventActivityStage/lead``). Asked for any earlier —
/// any day before the night, or that morning — it is scheduled with the
/// system, which starts it at that moment whether or not the app is running;
/// asked for inside the window it starts at once. Only for a night the reader
/// holds a ticket for, as the design has it, and only once the page has
/// published a start: without one there is nothing to count down to.
///
/// **The activity moves on through the night by itself.** It is drawn again
/// only when the app sends it something or its stale date passes, so the
/// extension draws every stage still to come at once and the system shows
/// each in its own stretch (see ``EventActivityAttributes/ContentState/phases(at:)``).
/// The app still catches it up whenever it runs — on launch, on coming back
/// to the foreground, while the event's sheet is open, at each change of stage
/// while the app is up, and in a background refresh asked for at the next one
/// — for a door time or a seat written since, and for the island's outline,
/// which only takes one colour. There is no server to push updates from, and
/// none is wanted.
@MainActor @Observable
final class EventActivities {
    static let shared = EventActivities()

    /// What an event's activity is doing, for the button that asks for it.
    enum Status: Equatable {
        /// Asked for ahead of its window, and waiting on the system to start it.
        case scheduled
        case running
    }

    /// The background refresh asked for at the next change of stage. Named in
    /// the app's Info.plist under `BGTaskSchedulerPermittedIdentifiers`.
    static let refreshTask = "moe.shawn.Eventrail.liveActivity"

    /// How long "That's a wrap" stays on the Lock Screen after the show.
    private static let lingering: TimeInterval = 30 * 60

    /// Whether this device shows Live Activities for the app at all — false on
    /// an iPad, and where the reader has turned them off in Settings, where the
    /// sheet offers none.
    private(set) var isEnabled: Bool

    /// Each event's activity, by event.
    private(set) var statuses: [Event.ID: Status] = [:]

    /// The store the last refresh was handed, so a refresh the app starts by
    /// itself can read the latest times and seat too.
    private weak var store: EventStore?
    /// The refresh at the next change of stage, while the app is running.
    private var wake: Task<Void, Never>?
    private var watched: Set<Activity<EventActivityAttributes>.ID> = []
    /// Events whose activity is being asked for — its flyer fetched, the
    /// request not yet made — so a second tap asks nothing and a refresh in
    /// between leaves the flyer alone.
    private var starting: Set<Event.ID> = []
    /// A refresh is running, and another was asked for meanwhile.
    private var isRefreshing = false
    private var refreshesAgain = false

    private init() {
        let authorization = ActivityAuthorizationInfo()
        isEnabled = authorization.areActivitiesEnabled
        Task {
            for await enabled in authorization.activityEnablementUpdates { isEnabled = enabled }
        }
        Task {
            for await activity in Activity<EventActivityAttributes>.activityUpdates { watch(activity) }
        }
        for activity in Activity<EventActivityAttributes>.activities { watch(activity) }
        read()
    }

    /// Whether the sheet offers one for `event`: kept, held a ticket for, with
    /// a start published, and not yet over.
    func canOffer(_ event: Event, tracking: Tracking, inLibrary: Bool, at now: Date = .now) -> Bool {
        guard isEnabled, inLibrary, tracking.ticket == .purchased, event.isUpcoming,
              let state = Self.state(for: event, seat: tracking.seat, at: now) else { return false }
        return now < state.runsTo
    }

    /// Starts the event's activity, or schedules it for the start of its
    /// window. Asks nothing where it already has one.
    func start(for event: Event, tracking: Tracking) async throws {
        guard !Self.live.contains(where: { $0.attributes.eventID == event.id }) else { return }
        try await request(for: event, tracking: tracking)
    }

    private func request(for event: Event, tracking: Tracking) async throws {
        let now = Date.now
        guard var state = Self.state(for: event, seat: tracking.seat, at: now),
              starting.insert(event.id).inserted else { return }
        defer { starting.remove(event.id) }
        let opens = Self.opening(of: state)
        // Before the request, so the first time it is drawn has the flyer.
        await Self.keepPoster(for: event)
        let attributes = EventActivityAttributes(
            eventID: event.id, title: event.title, venue: event.venue,
            link: event.sourceURL, opens: max(opens, now))
        if opens > now {
            state.stage = state.stage(at: opens)
            // The system says so as it starts one, and wants the words for it.
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: event.title),
                body: Self.alertBody(for: state),
                sound: .default)
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.nextChange),
                pushType: nil, style: .standard, alertConfiguration: alert, start: opens)
        } else {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.nextChange),
                pushType: nil)
        }
        read()
        scheduleWake()
    }

    /// Ends the event's activity, or calls off a scheduled one.
    func stop(for event: Event) async {
        for activity in Activity<EventActivityAttributes>.activities
        where activity.attributes.eventID == event.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        dropPosters()
        read()
        scheduleWake()
    }

    /// Brings every activity up to where its night now stands, and — where the
    /// library is at hand — to the event's latest times and the seat written
    /// since. Ends the ones that are over, and any whose event has left the
    /// library.
    ///
    /// One at a time: a refresh asked for while one runs — the sheet's, the
    /// app coming back, the wake — runs once more after it rather than beside
    /// it, where both would see a moved window and ask for it twice.
    func refresh(from store: EventStore? = nil) async {
        if let store { self.store = store }
        guard !isRefreshing else {
            refreshesAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshesAgain = false
            await catchUp()
        } while refreshesAgain
        read()
        scheduleWake()
    }

    private func catchUp() async {
        let store = self.store
        let now = Date.now
        for activity in Self.live {
            var state = activity.content.state
            if let store, let event = store.event(id: activity.attributes.eventID) {
                guard store.isInLibrary(event) else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    continue
                }
                let tracking = store.tracking(for: event)
                if let latest = Self.state(for: event, seat: tracking.seat, at: now) { state = latest }
                // A door time published since moves the window. One already on
                // stays on; one still waiting is asked for again at the new
                // time — which only the app in front of the reader may do.
                if activity.activityState == .pending,
                   Self.opening(of: state) != activity.attributes.opens,
                   UIApplication.shared.applicationState == .active {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    try? await request(for: event, tracking: tracking)
                    continue
                }
                if !Self.hasPoster(for: event.id) { await Self.keepPoster(for: event) }
            }
            state.stage = state.stage(at: activity.activityState == .pending
                                      ? max(now, activity.attributes.opens) : now)
            if state.stage == .wrapped {
                await activity.end(ActivityContent(state: state, staleDate: nil),
                                   dismissalPolicy: .after(state.runsTo.addingTimeInterval(Self.lingering)))
            } else if state != activity.content.state {
                await activity.update(ActivityContent(state: state, staleDate: state.nextChange))
            }
        }
        dropPosters()
    }

    // MARK: - Keeping track

    /// The activities still to come or still on — what a refresh looks after.
    private static var live: [Activity<EventActivityAttributes>] {
        Activity<EventActivityAttributes>.activities
            .filter { [.pending, .active, .stale].contains($0.activityState) }
    }

    private func watch(_ activity: Activity<EventActivityAttributes>) {
        guard watched.insert(activity.id).inserted else { return }
        read()
        Task {
            for await _ in activity.activityStateUpdates { read() }
            watched.remove(activity.id)
            read()
        }
    }

    private func read() {
        var statuses: [Event.ID: Status] = [:]
        for activity in Activity<EventActivityAttributes>.activities {
            switch activity.activityState {
            case .pending: statuses[activity.attributes.eventID] = .scheduled
            case .active, .stale: statuses[activity.attributes.eventID] = .running
            default: break
            }
        }
        if statuses != self.statuses { self.statuses = statuses }
    }

    /// Asks to run again at the next change of stage: in this process while
    /// it lasts, and as a background refresh for when it does not.
    private func scheduleWake() {
        wake?.cancel()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTask)
        let next = Self.live.compactMap(\.content.state.nextChange).min()
        guard let next else { return }
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTask)
        request.earliestBeginDate = next
        // Refused in the Simulator, which runs no background refresh.
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - What an activity says

    /// The night's times as the activity reads them — in the order the night
    /// runs (``Event/inOrder(_:_:_:)``), an end before the start dropped, and
    /// no end published running for ``Event/assumedLength`` — and where it
    /// stands at `now`. Nil without a start.
    static func state(for event: Event, seat: String, at now: Date) -> EventActivityAttributes.ContentState? {
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)
        guard let starts = times.starts else { return nil }
        let ends = times.ends.flatMap { $0 > starts ? $0 : nil }
        let doors = times.doors.flatMap { $0 < starts ? $0 : nil }
        let runsTo = ends ?? starts.addingTimeInterval(Event.assumedLength)
        let display = UserDefaults.standard.string(forKey: TimeDisplay.storageKey)
            .flatMap(TimeDisplay.init(rawValue:)) ?? .venue
        return .init(stage: .at(now, doors: doors, starts: starts, runsTo: runsTo),
                     doors: doors, starts: starts, ends: ends, runsTo: runsTo,
                     timeZone: event.shown(on: display).timeZone, seat: seat)
    }

    /// When the activity comes on: two hours before the doors, or before the
    /// start where the page published no doors.
    static func opening(of state: EventActivityAttributes.ContentState) -> Date {
        (state.doors ?? state.starts).addingTimeInterval(-EventActivityStage.lead)
    }

    private static func alertBody(for state: EventActivityAttributes.ContentState) -> LocalizedStringResource {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = state.timeZone
        if let doors = state.doors { return "Doors open at \(doors.formatted(style))" }
        return "Starts at \(state.starts.formatted(style))"
    }

    // MARK: - The flyer

    /// Leaves the event's flyer where the extension can read it, sized for the
    /// largest place the activity draws it (36 × 50 points, at 3×). The
    /// extension cannot download anything as it draws, and a picture larger
    /// than the presentation can stop the system starting the activity at all.
    private static func keepPoster(for event: Event) async {
        guard let url = event.imageURL,
              let file = EventActivityAttributes.posterFile(for: event.id) else { return }
        var image = await ImageCache.shared.storedImage(for: url)
        if image == nil { image = await ImageCache.shared.image(for: url) }
        guard let image, let data = downsized(image).jpegData(compressionQuality: 0.8) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func downsized(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 108, height: 150)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(origin: CGPoint(x: (size.width - drawn.width) / 2,
                                                  y: (size.height - drawn.height) / 2),
                                  size: drawn))
        }
    }

    private static func hasPoster(for eventID: String) -> Bool {
        guard let file = EventActivityAttributes.posterFile(for: eventID) else { return true }
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }

    /// Throws away the flyers of activities the system no longer shows —
    /// kept until then, since an ended one can stay on the Lock Screen — and
    /// of none being asked for.
    private func dropPosters() {
        let kept = Activity<EventActivityAttributes>.activities
            .filter { $0.activityState != .dismissed }
            .map(\.attributes.eventID)
        guard let folder = EventActivityAttributes.posterFile(for: "_")?.deletingLastPathComponent(),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            if !kept.contains(id), !starting.contains(id) { try? FileManager.default.removeItem(at: file) }
        }
    }
}
