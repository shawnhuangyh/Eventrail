import CoreSpotlight
import SwiftData
import SwiftUI
import Playgrounds

enum AppTab: Hashable {
    case events, following, search, me
}

/// The home tabs: what the reader has decided about, what is coming for the
/// people they follow, and themselves. On iOS 26 the tab bar is Liquid Glass
/// over the wash, and search stands beside it in the system's own detached
/// search treatment rather than taking a place in the row.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let store = Launch.shared.store
    /// Read from Eventernote rather than from the library, and shared by the
    /// two screens that show it — the Following tab and the Me card — so a
    /// followed performer's listing is asked for once per launch.
    private let followed = Launch.shared.followed
    /// Where each hall is, read from Eventernote's own venue pages and kept for
    /// the life of the launch beside the dates it places.
    private let venues = Launch.shared.venues
    /// What the last refresh said, wherever it was started from — see
    /// ``RefreshNotices``.
    @State private var notices = RefreshNotices()
    @State private var selection: AppTab = .events
    /// A backup the reader opened in Files and sent here. Received at the root
    /// rather than in Settings: the app can be opened from a file while any tab
    /// is showing, and from a cold launch with no Settings sheet at all.
    @State private var openedBackup: URL?
    /// An event opened from outside the app — its Live Activity, tapped, or
    /// another device's sheet, handed off — or a lottery round, from its
    /// results-day reminder (``LotteryReminders``): opened over whatever sheet
    /// is up — see ``OutsideOpens``.
    @State private var opens = OutsideOpens()
    /// The event in the frontmost sheet, offered to the reader's other
    /// devices — see ``EventHandoff``.
    @State private var handoff = EventHandoff()
    @Environment(\.openURL) private var openURL
    private let reminders = LotteryReminders.shared
    /// What Siri, Shortcuts or a Spotlight result asked for through an
    /// intent — see ``IntentOpens``.
    private let intentOpens = IntentOpens.shared
    /// A term handed to the Search tab from outside the app — Spotlight's
    /// Search in App, or Siri — which the tab types in and searches for.
    @State private var searchRequest: String?
    /// Whether this launch still owes the reader the welcome.
    ///
    /// Seeded once from the per-device flag ``WelcomeView`` writes for itself
    /// when the reader reaches the end of it. Deliberately not an `@AppStorage`
    /// binding the cover writes through: SwiftUI clears a presentation binding
    /// when the cover goes away for any reason, including the app being torn
    /// down around it, which would record a welcome the reader never answered.
    /// Closing it early costs them this launch's showing; it does not spend
    /// the only one they get.
    @State private var isWelcoming = !UserDefaults.standard.bool(forKey: WelcomeView.seenKey)
    /// Read only to send the watch and the widgets their copies again when it
    /// changes — see ``WatchLink`` and ``WidgetLink`` — and to print a Live
    /// Activity on the new clock.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    var body: some View {
        TabView(selection: $selection) {
            Tab("My Events", systemImage: "calendar", value: AppTab.events) {
                EventsView().refreshNotices()
            }

            Tab("Following", systemImage: "person.2", value: AppTab.following) {
                FollowingView().refreshNotices()
            }

            Tab("Me", systemImage: "person.crop.circle", value: AppTab.me) {
                MeView().refreshNotices()
            }

            Tab(value: AppTab.search, role: .search) {
                SearchView(request: $searchRequest).refreshNotices()
            }
        }
        // Selecting the search tab opens the field straight away, rather than
        // waiting for a second tap. visionOS has no equivalent.
        #if !os(visionOS)
        .tabViewSearchActivation(.searchTabSelection)
        #endif
        .onOpenURL { url in
            if let id = Self.eventID(in: url) {
                guard let event = store.event(id: id) else { return }
                // A widget's link to one round of the event's — see
                // ``RoundLink`` — opens the round's own page, where its
                // result is written down; one gone since opens the event.
                if let round = RoundLink.entry(in: url),
                   let entry = store.tracking(for: event).lotteries.first(where: { $0.id == round }) {
                    opens.open(.round(LotteryRow(event: event, entry: entry)))
                } else {
                    opens.open(.event(event))
                }
            } else {
                openedBackup = url
            }
        }
        // Offered while an event's sheet is up, and taken back as it closes.
        .userActivity(EventHandoff.activityType, element: handoff.shown) { event, activity in
            EventHandoff.fill(activity, with: event)
        }
        .onContinueUserActivity(EventHandoff.activityType) { activity in
            continueHandoff(activity)
        }
        // A result tapped in Spotlight — see ``SpotlightIndex``.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let request = SpotlightIndex.opening(identifier, in: store) else { return }
            open(request)
        }
        // Search in App, under Spotlight's results: Eventernote's own search,
        // with what was typed there.
        .onContinueUserActivity(CSQueryContinuationActionType) { activity in
            guard let term = activity.userInfo?[CSSearchQueryString] as? String else { return }
            search(for: term)
        }
        .onChange(of: intentOpens.waiting, initial: true) { takeIntentOpen() }
        // The ticket sheet on the round's own page, where its result is
        // written down — or the event, where the round has gone since.
        .onChange(of: reminders.opened, initial: true) { openReminder() }
        // Inside the environment lines below, for the store; over the tabs,
        // which stand a sheet deeper for it.
        .opensFromOutside()
        // Asked about first: tapping a file is not by itself a request to fold
        // its contents into the library.
        //
        // Above the two `.environment` lines on purpose. A modifier written
        // after them wraps around them, which puts it outside the environment
        // they set — and this one reads the store out of it.
        .restoringBackup($openedBackup, asking: true)
        // Above the `.environment` lines for the same reason, and over
        // everything: the first launch has no tab worth showing yet.
        .fullScreenCover(isPresented: $isWelcoming) {
            WelcomeView()
        }
        .library(store)
        .environment(followed)
        .environment(venues)
        .environment(notices)
        .environment(opens)
        .environment(handoff)
        .tint(.brandTint)
        // The reader's text size is followed up to xxxLarge and no further —
        // see ``SwiftUI/View/scalingFont(size:weight:design:)``. Past it, the
        // accessibility sizes would have rows laid out side by side stack.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // A cold launch is a change of scene phase to nobody: `onChange` only
        // hears the ones after the first. Without this the calendar would only
        // ever catch up after an edit or a trip to the background, so a library
        // imported on another device could sit unmirrored indefinitely.
        .task { await store.mirrorCalendar() }
        // Live Activities can have fallen behind their events while the app
        // was not running — see ``EventActivities``.
        .task { await EventActivities.shared.refresh(from: store) }
        // The watch draws the events still to come from a copy sent from here,
        // so the copy follows every write and the clock it is printed on.
        .task { WatchLink.shared.send(from: store) }
        // The widgets draw from a copy left beside them, which follows every
        // write the same way; a result given from one is written down first.
        .task {
            WidgetLink.shared.takeAnswers(into: store)
            WidgetLink.shared.send(from: store)
        }
        // Spotlight's copy follows the writes that can move what it holds —
        // public facts only, so not a note or a read — and the Following
        // dates by itself. See ``SpotlightIndex``.
        .task { SpotlightIndex.shared.update(from: store, followed: followed) }
        .onChange(of: store.factsRevision) { SpotlightIndex.shared.update(from: store, followed: followed) }
        .onChange(of: store.revision) {
            WatchLink.shared.send(from: store)
            WidgetLink.shared.send(from: store)
            reminders.schedule(from: store)
            EventActivities.shared.refreshSoon(from: store)
        }
        .onChange(of: timeDisplay) {
            WatchLink.shared.send(from: store)
            WidgetLink.shared.send(from: store)
            SpotlightIndex.shared.update(from: store, followed: followed)
            EventActivities.shared.refreshSoon(from: store)
        }
        // Each results day still waiting is a reminder that evening, and the
        // ones answered on another device meanwhile are taken back — followed
        // from here on with every write, as the watch's copy is.
        .task { reminders.schedule(from: store) }
        // Edits are written after a short pause; leaving the app cuts that
        // short, so the last one is flushed here rather than lost. Coming back
        // is the moment to pick up whatever another device wrote meanwhile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A reminder tapped, or an intent run, while this window was
                // on its way in.
                openReminder()
                takeIntentOpen()
                Task { await store.syncNow() }
                Task { await EventActivities.shared.refresh(from: store) }
                // An event whose day ended while the app was away leaves the
                // watch's list too.
                WatchLink.shared.send(from: store)
                // A Won or Lost tapped on the Lotteries widget while away.
                WidgetLink.shared.takeAnswers(into: store)
                WidgetLink.shared.send(from: store)
                // The flyers cached since the last pass, which no write marks.
                SpotlightIndex.shared.update(from: store, followed: followed)
                // Notifications may have been turned on or off in Settings.
                reminders.schedule(from: store)
            } else {
                store.saveNow()
            }
        }
    }

    /// Opens the round a results-day reminder was tapped for, in this window
    /// — only while it is the one in front. On an iPad each window has a root
    /// of its own and the reminder is one for the app, so whichever window's
    /// root heard it first used to take it, the one in the other half of the
    /// screen or behind as often as not. A tap brings forward the window it
    /// was meant for, and that window opens it as it comes in.
    private func openReminder() {
        guard scenePhase == .active, let opened = reminders.opened else { return }
        reminders.opened = nil
        guard let event = store.event(id: opened.eventID) else { return }
        if let entry = store.tracking(for: event).lotteries.first(where: { $0.id == opened.entryID }) {
            opens.open(.round(LotteryRow(event: event, entry: entry)))
        } else {
            opens.open(.event(event))
        }
    }

    /// Opens what an intent asked for, in this window — only while it is the
    /// one in front, for the reason a reminder waits for it (``openReminder()``).
    private func takeIntentOpen() {
        guard scenePhase == .active, let request = intentOpens.waiting else { return }
        intentOpens.waiting = nil
        open(request)
    }

    /// Opens what Spotlight, Siri or Shortcuts asked for, over whatever is up.
    /// An event this device no longer holds — removed, or a Following date
    /// gone from the listing — opens its page in the browser, as a handed-off
    /// event this device cannot read does.
    private func open(_ request: IntentOpen) {
        switch request {
        case .event(let id):
            if let event = store.event(id: id) ?? followed.event(id: id) {
                opens.open(.event(event))
            } else {
                openURL(EventernoteClient.site.appending(path: "events/\(id)"))
            }
        case .performer(let profile):
            opens.open(.performer(.profile(profile)))
        case .venue(let link):
            opens.open(.venue(link))
        case .search(let term):
            search(for: term)
        }
    }

    /// The Search tab, searching Eventernote for `term`. Under a sheet, if one
    /// is up: it is the reader's to put away.
    private func search(for term: String) {
        selection = .search
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { searchRequest = term }
    }

    /// Opens the event another device offered through Handoff: the copy it
    /// sent, which the sheet answers with this device's own where it holds
    /// one. A copy this build cannot read falls back to whatever this device
    /// holds under the page's address, and with nothing held, the page itself
    /// opens in the browser — where Handoff would have taken a device without
    /// the app.
    private func continueHandoff(_ activity: NSUserActivity) {
        if let event = EventHandoff.event(in: activity)
            ?? activity.webpageURL.flatMap(Self.eventID(in:)).flatMap(store.event(id:)) {
            opens.open(.event(event))
        } else if let page = activity.webpageURL {
            openURL(page)
        }
    }

    /// The event a link to its Eventernote page names — what a Live Activity
    /// and a widget open the app with, and the page a handed-off event points
    /// at.
    private static func eventID(in url: URL) -> Event.ID? {
        guard url.host() == "www.eventernote.com" else { return nil }
        let path = url.pathComponents
        guard path.count == 3, path[1] == "events", !path[2].isEmpty else { return nil }
        return path[2]
    }
}

#Preview {
    RootView()
}

/// What the app keeps for the life of the process: the library, the followed
/// performers' dates and where their halls are.
///
/// Made once, here, and never in a view's initializer. SwiftUI makes a view
/// value as often as it likes and keeps only the first `@State` it was given;
/// every other `EventStore` a `RootView()` made still opened the library —
/// with iCloud Sync on, a second CloudKit mirror of the same file, which Core
/// Data refuses and goes on retrying. That kept the app busy for as long as
/// syncing was on.
@MainActor
final class Launch {
    static let shared = Launch()

    let store: EventStore
    let followed: FollowedDates
    let venues: VenueRegions

    /// Made together, so the dates know which clock each hall keeps before
    /// any screen reads them — see ``FollowedDates/hallZone``. Four answers,
    /// none of them asked for here: a hall ``VenueRegions`` places in one of
    /// the site's areas is in Japan; the library's own copy of the event
    /// carries its hall's clock once a placing retimed it; a hall abroad
    /// whose clock ``VenueRegions/settleClocks(for:)`` settled from its
    /// address keeps that; and a hall placed under any address — the reader
    /// opening the event places it — answers by its name.
    private init() {
        let store = EventStore()
        let followed = FollowedDates()
        let venues = VenueRegions()
        followed.hallZone = { event in
            if venues.region(of: event) != nil { return Event.publishedZone }
            if let kept = store.event(id: event.id), kept.timeZone != Event.publishedZone {
                return kept.timeZone
            }
            if let zone = venues.timeZone(of: event) { return zone }
            return VenuePlaces.shared.timeZone(ofHallNamed: event.venue)
        }
        self.store = store
        self.followed = followed
        self.venues = venues
    }
}

extension View {
    /// The store, and the rows it writes for the screens to query — for the
    /// root of the app and for a preview.
    ///
    /// Handed the container as it stands: turning iCloud Sync opens the store
    /// again, and every `@Query` beneath follows the new one.
    func library(_ store: EventStore) -> some View {
        environment(store)
            .modelContainer(store.database.container)
    }
}

#Playground {
    _ = EventGroup.groups(of: PreviewData.events, filter: .upcoming, grouping: .date).map(\.label)
}
