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
    }
}
