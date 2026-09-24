import SwiftUI

@main struct MyApp: App {
    /// Set here rather than on each screen, so every sheet and cover the app
    /// presents inherits it from the window.
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.automatic

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
