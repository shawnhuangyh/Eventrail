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

    @State private var store = EventStore()
    /// Read from Eventernote rather than from the library, and shared by the
    /// two screens that show it — the Following tab and the Me card — so a
    /// followed performer's listing is asked for once per launch.
    @State private var followed = FollowedDates()
    @State private var selection: AppTab = .events

    var body: some View {
        TabView(selection: $selection) {
            Tab("My Events", systemImage: "calendar", value: AppTab.events) {
                EventsView()
            }

            Tab("Following", systemImage: "person.2", value: AppTab.following) {
                FollowingView()
            }

            Tab("Me", systemImage: "person.crop.circle", value: AppTab.me) {
                MeView()
            }

            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        // Selecting the search tab opens the field straight away, rather than
        // waiting for a second tap. visionOS has no equivalent.
        #if !os(visionOS)
        .tabViewSearchActivation(.searchTabSelection)
        #endif
        .environment(store)
        .environment(followed)
        .tint(.brandTint)
        // A cold launch is a change of scene phase to nobody: `onChange` only
        // hears the ones after the first. Without this the calendar would only
        // ever catch up after an edit or a trip to the background, so a library
        // imported on another device could sit unmirrored indefinitely.
        .task { await store.mirrorCalendar() }
        // Edits are written after a short pause; leaving the app cuts that
        // short, so the last one is flushed here rather than lost. Coming back
        // is the moment to pick up whatever another device wrote meanwhile.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.syncNow() }
            } else {
                store.saveNow()
            }
        }
    }
}

#Preview {
    RootView()
}

#Playground {
    let store = EventStore.preview
    _ = store.groups(filter: .upcoming, grouping: .month).map(\.label)
}
