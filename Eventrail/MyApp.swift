import SwiftUI

@main struct MyApp: App {
    /// Applied to the window at launch; Settings applies a change as it is
    /// made — see ``Appearance/apply()``.
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    init() {
        // Made here so its delegate is in place before launch finishes: a
        // results-day reminder tapped to open the app is otherwise never heard.
        _ = LotteryReminders.shared
    }

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
