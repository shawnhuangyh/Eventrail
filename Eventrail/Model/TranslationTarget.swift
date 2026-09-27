import Foundation
import Translation

/// Which language an event's 概要 is translated into — see
/// ``EventDetailView``'s description card and ``LanguageSettingsView``.
///
/// Stored per device as a language identifier, empty for "the app's own
/// language", which is the default: most readers want the description in the
/// language the rest of the app is already speaking, and only a reader who
/// runs the app in one language and reads best in another needs to say more.
/// Per device for the reason Appearance is: it is how this reader reads on
/// this phone, not something about the library.
enum TranslationTarget {
    static let storageKey = "translationTarget"

    /// What every 概要 is written in. Named rather than detected: a line of
    /// kanji and a venue name reads as Chinese to a detector, and the site is
    /// Japanese end to end.
    static let source = Locale.Language(identifier: "ja")

    /// The language the app is showing itself in — iOS's per-app setting, so
    /// the bundle's answer rather than the system's.
    static var appLanguage: Locale.Language {
        Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The stored choice, or the app's language where there is none.
    static func resolved(_ stored: String) -> Locale.Language {
        stored.isEmpty ? appLanguage : Locale.Language(identifier: stored)
    }

    /// Whether translating into `target` means anything — not into the
    /// Japanese it is already in.
    static func isWorthOffering(_ target: Locale.Language) -> Bool {
        target.languageCode != source.languageCode
    }

    /// Every language the system translates into.
    ///
    /// Made and asked off the main actor in one place, because
    /// `LanguageAvailability` is not `Sendable`: one made on the main actor
    /// may not be handed to the nonisolated property that answers.
    @concurrent nonisolated static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    /// A language's name in the language the app is drawn in, so the list
    /// reads as one language rather than each entry in its own.
    static func name(of language: Locale.Language) -> String {
        let id = language.minimalIdentifier
        return Locale(identifier: appLanguage.minimalIdentifier).localizedString(forIdentifier: id) ?? id
    }
}
