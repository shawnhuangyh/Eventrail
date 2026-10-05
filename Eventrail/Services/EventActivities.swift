@preconcurrency import ActivityKit
import BackgroundTasks
import SwiftUI
import UIKit

/// The Live Activities the app has started or scheduled — at most one per
/// event — and what keeps each in step with the event it is for.
///
/// **An activity is started from the event's sheet, at once, and never
/// scheduled** — and only once, started then, it will last until the event is
/// over: the system ends an activity eight hours after it starts (``longest``),
/// so the sheet refuses before ``earliestStart(of:)`` and says from when it can
/// be (``refusal(for:at:in:)``). Not scheduled ahead, though iOS 26 could:
/// **iOS ends every activity an app has, scheduled ones included, when the app
/// is updated** (`liveactivitiesd` logs "Stopping uninstalled activity" as the
/// new build is installed), and one scheduled weeks before was usually gone by
/// the day of the event. Only for an event the reader holds a ticket for, as
/// the design has it, and only once the page has published a start: without
/// one there is nothing to count down to.
///
/// **The activity moves on through the event by itself.** It is drawn again
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
        guard isEnabled, inLibrary, tracking.hasTicket, event.isUpcoming,
              let state = Self.state(for: event, seat: tracking.seat, at: now) else { return false }
        return now < state.runsTo
    }

    /// Why an activity was not started.
    enum Refusal: Error, Equatable {
        /// It could be from a day still to come — the event's own, as a rule.
        case beforeItsDay
        /// It can be later today, from `earliest` — see ``earliestStart(of:)``.
        case tooEarly(earliest: Date)
    }

    /// How long an activity stays on: the system ends one eight hours after
    /// it starts, and takes it out of the Dynamic Island.
    static let longest: TimeInterval = 8 * 60 * 60

    /// The earliest an activity can start and still be on until the event is
    /// over: ``longest`` before what it runs to. Started at ten for a show
    /// ending at eight, the system would end it at six, as the show began.
    static func earliestStart(of state: EventActivityAttributes.ContentState) -> Date {
        state.runsTo.addingTimeInterval(-longest)
    }

    /// Why an activity cannot be started for the event at `now`, or nil where
    /// it can: before ``earliestStart(of:)``, said as a time where that is
    /// later today on the reader's `calendar` and as the event's day where it
    /// is not.
    static func refusal(for event: Event, at now: Date = .now,
                        in calendar: Calendar = .current) -> Refusal? {
        guard let state = state(for: event, seat: "", at: now) else { return nil }
        let earliest = earliestStart(of: state)
        guard now < earliest else { return nil }
        return calendar.isDate(earliest, inSameDayAs: now) ? .tooEarly(earliest: earliest) : .beforeItsDay
    }

    /// Starts the event's activity, at once. Asks nothing where it already
    /// has one, and refuses where, started now, it would end before the event
    /// did — see ``refusal(for:at:in:)``.
    func start(for event: Event, tracking: Tracking) async throws {
        guard !Self.live.contains(where: { $0.attributes.eventID == event.id }) else { return }
        if let refusal = Self.refusal(for: event) { throw refusal }
        let now = Date.now
        guard let state = Self.state(for: event, seat: tracking.seat, at: now),
              starting.insert(event.id).inserted else { return }
        defer { starting.remove(event.id) }
        // Before the request, so the first time it is drawn has the flyer.
        await Self.keepPoster(for: event)
        let attributes = EventActivityAttributes(
            eventID: event.id, title: event.title, venue: event.venue,
            link: event.sourceURL, opens: now)
        _ = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: state.nextChange),
            pushType: nil)
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

    /// Brings every activity up to where its event now stands, and — where the
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
                if !Self.hasPoster(for: event.id) { await Self.keepPoster(for: event) }
            }
            // Pending is only ever one the debug bench scheduled, or an older
            // build: still waiting, it stands where the event will at its
            // start.
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

    /// The event's times as the activity reads them — in the order the event
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
