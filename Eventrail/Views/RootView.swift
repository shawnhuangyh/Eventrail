import SwiftUI
import Playgrounds

enum AppTab: Hashable {
    case events, search, me
}

/// The three home tabs. On iOS 26 the tab bar is Liquid Glass over the wash,
/// and the search tab gets the system's dedicated search treatment.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var store = EventStore()
    @State private var selection: AppTab = .events

    var body: some View {
        TabView(selection: $selection) {
            Tab("My Events", systemImage: "calendar", value: AppTab.events) {
                EventsView()
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
