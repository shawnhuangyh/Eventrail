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
        // Edits are written after a short pause; leaving the app cuts that
        // short, so the last one is flushed here rather than lost.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
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
