import SwiftUI
import UIKit

/// Whether the app follows the system's light or dark mode, or keeps one of
/// them regardless.
///
/// Per-device, in `UserDefaults` and deliberately not synced, like
/// ``EventStore/iCloudSyncEnabled``: a reader who keeps the iPad dark on the
/// nightstand has not asked for the phone to go dark too.
enum Appearance: String, CaseIterable, Identifiable {
    /// Raw value kept from when this was called "automatic", so a choice
    /// already stored reads back as the same choice.
    case system = "automatic"
    case light, dark

    /// The `UserDefaults` key, read through `@AppStorage` by the root of the
    /// app and by Settings.
    static let storageKey = "appearance"

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `.unspecified` hands the choice back to the system.
    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Sets this on every window the app has open, and so on every sheet and
    /// cover presented in them.
    ///
    /// On the window rather than through `preferredColorScheme`, which does
    /// not undo itself: going from Light back to nil left the window and the
    /// Settings sheet light on a dark phone, because nil is read as "no
    /// preference from me" rather than as "clear the one I set". A window's
    /// `.unspecified` is the system's answer again, at once.
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
                // And on every controller presented over it, so the Settings
                // sheet the choice is made on changes with the window rather
                // than relying on SwiftUI to pass the change down to it.
                var presented = window.rootViewController?.presentedViewController
                while let controller = presented {
                    controller.overrideUserInterfaceStyle = interfaceStyle
                    presented = controller.presentedViewController
                }
            }
        }
    }
}
