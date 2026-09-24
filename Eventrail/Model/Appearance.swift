import SwiftUI

/// Whether the app follows the system's light or dark mode, or keeps one of
/// them regardless.
///
/// Per-device, in `UserDefaults` and deliberately not synced, like
/// ``EventStore/iCloudSyncEnabled``: a reader who keeps the iPad dark on the
/// nightstand has not asked for the phone to go dark too.
enum Appearance: String, CaseIterable, Identifiable {
    case automatic, light, dark

    /// The `UserDefaults` key, read through `@AppStorage` by the root of the
    /// app and by Settings.
    static let storageKey = "appearance"

    var id: Self { self }

    /// Nil hands the choice back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
