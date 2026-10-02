import SwiftUI

/// Eventrail on Apple Watch, as `Eventrail Watch.dc.html` (1a) draws it: My
/// Events, then each night in three pages turned with the Crown — the
/// countdown, the seat, the times.
///
/// Read-only, and fed by the phone: the library comes over as a
/// ``WatchLibrary`` the iPhone app sends (`WatchLink`), so the watch keeps no
/// store, signs into nothing and asks Eventernote for nothing but flyers.
@main struct EventrailWatchApp: App {
    @State private var library = WatchLibraryStore()

    var body: some Scene {
        WindowGroup {
            MyEventsView()
                .environment(library)
        }
    }
}
