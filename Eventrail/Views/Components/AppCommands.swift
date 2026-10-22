import SwiftUI

extension FocusedValues {
    /// The tab the window in front is showing, for the menu bar to change.
    @Entry var appTab: Binding<AppTab>?
    /// What the window in front opens over whatever it has up — Settings, for
    /// the menu bar (``OutsideOpens/openSettings()``).
    @Entry var outsideOpens: OutsideOpens?
}

/// The menu bar's own items: Settings, and a way to each tab from the
/// keyboard — on a Mac, and in the menu bar an iPad shows with a keyboard
/// attached. Each acts on the window in front (``RootView``), which hands
/// them its tab and its ``OutsideOpens`` through `focusedSceneValue`.
struct AppCommands: Commands {
    @FocusedValue(\.appTab) private var tab
    @FocusedValue(\.outsideOpens) private var opens

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { opens?.openSettings() }
                .keyboardShortcut(",")
                .disabled(opens == nil)
        }
        CommandGroup(before: .toolbar) {
            tabButton("My Events", .events, key: "1")
            tabButton("Following", .following, key: "2")
            tabButton("Me", .me, key: "3")
            tabButton("Search", .search, key: "4")
            Divider()
        }
    }

    private func tabButton(_ title: LocalizedStringKey, _ value: AppTab, key: KeyEquivalent) -> some View {
        Button(title) { tab?.wrappedValue = value }
            .keyboardShortcut(key)
            .disabled(tab == nil)
    }
}
