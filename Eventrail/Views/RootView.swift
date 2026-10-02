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
    /// An event opened from outside the app — its Live Activity, tapped.
    @State private var openedEvent: Event?
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
    /// Read only to send the watch its copy again when it changes — see
    /// ``WatchLink``.
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
                SearchView().refreshNotices()
            }
        }
        // Selecting the search tab opens the field straight away, rather than
        // waiting for a second tap. visionOS has no equivalent.
        #if !os(visionOS)
        .tabViewSearchActivation(.searchTabSelection)
        #endif
        .onOpenURL { url in
            if let id = Self.eventID(in: url) {
                openedEvent = store.event(id: id)
            } else {
                openedBackup = url
            }
        }
        .eventSheet($openedEvent)
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
        .tint(.brandTint)
        // A cold launch is a change of scene phase to nobody: `onChange` only
        // hears the ones after the first. Without this the calendar would only
        // ever catch up after an edit or a trip to the background, so a library
        // imported on another device could sit unmirrored indefinitely.
        .task { await store.mirrorCalendar() }
        // Live Activities can have fallen behind their nights while the app
        // was not running — see ``EventActivities``.
        .task { await EventActivities.shared.refresh(from: store) }
        // The watch draws the nights still to come from a copy sent from here,
        // so the copy follows every write and the clock it is printed on.
        .task { WatchLink.shared.send(from: store) }
        .onChange(of: store.revision) { WatchLink.shared.send(from: store) }
        .onChange(of: timeDisplay) { WatchLink.shared.send(from: store) }
        // Edits are written after a short pause; leaving the app cuts that
        // short, so the last one is flushed here rather than lost. Coming back
        // is the moment to pick up whatever another device wrote meanwhile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.syncNow() }
                Task { await EventActivities.shared.refresh(from: store) }
                // A night whose day ended while the app was away leaves the
                // watch's list too.
                WatchLink.shared.send(from: store)
            } else {
                store.saveNow()
            }
        }
    }

    /// The event a link to its Eventernote page names — what a Live Activity
    /// opens the app with.
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
    /// the site's areas is in Japan; the library's own copy of the night
    /// carries its hall's clock once a placing retimed it; a hall abroad
    /// whose clock ``VenueRegions/settleClocks(for:)`` settled from its
    /// address keeps that; and a hall placed under any address — the reader
    /// opening the night places it — answers by its name.
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
