import SwiftUI

@main struct MyApp: App {
    /// Applied to the window at launch; Settings applies a change as it is
    /// made — see ``Appearance/apply()``.
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { appearance.apply() }
        }
        // Asked for at a Live Activity's next change of stage, and run when
        // the system allows — see ``EventActivities``.
        .backgroundTask(.appRefresh(EventActivities.refreshTask)) {
            await EventActivities.shared.refresh()
        }
    }
}
