import SwiftUI
import Playgrounds

enum AppTab: Hashable {
    case events, search, me
}

/// The three home tabs. On iOS 26 the tab bar is Liquid Glass over the wash,
/// and the search tab gets the system's dedicated search treatment.
struct RootView: View {
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
    }
}

#Preview {
    RootView()
}

#Playground {
    let store = EventStore()
    _ = store.groups(filter: .upcoming, grouping: .month).map(\.label)
}
