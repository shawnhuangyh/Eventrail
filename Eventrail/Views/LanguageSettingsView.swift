import SwiftUI

/// The two languages the app speaks in, pushed from Settings: the one the
/// whole app is drawn in, and the one an event's description is translated
/// into.
///
/// One screen, and one card on it, because both answer "what language do I
/// read this in", and the second only makes sense beside the first — its
/// default is the first.
struct LanguageSettingsView: View {
    /// Per device — see ``TranslationTarget``.
    @AppStorage(TranslationTarget.storageKey) private var target = ""
    /// What the system can translate into, minus Japanese. Asked for as the
    /// screen opens; empty on a device with no translation at all.
    @State private var languages: [Locale.Language] = []

    var body: some View {
        ScrollView {
            // One card: both rows answer "what language do I read this in",
            // and the second's default is the first.
            VStack(spacing: 0) {
                appLanguageRow
                SettingRowDivider()
                translationRow
            }
            .glassPanel(interactive: true)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .washBackground()
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLanguages() }
    }

    /// iOS keeps an app's language on the app's own page in the Settings app,
    /// beside its calendar access, so this row goes there rather than
    /// building a second picker that would have to agree with the system's.
    private var appLanguageRow: some View {
        Link(destination: Self.systemSettings) {
            SettingRowLabel("globe", "App Language") {
                // The arrow is the system's own sign for leaving the app.
                SettingRowValue(
                    Text(verbatim: TranslationTarget.name(of: TranslationTarget.appLanguage)),
                    accessory: "arrow.up.right"
                )
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
    }

    private static let systemSettings = URL(string: UIApplication.openSettingsURLString)!

    /// The language descriptions are translated into, chosen from a menu
    /// on the row. The menu hangs off the value alone — never the whole row
    /// wrapped in a `Menu`: on iOS 26 a menu grows out of the glass holding
    /// its label, and that took the whole card away for as long as it was
    /// open (see Appearance). The value is drawn by ``SettingRowValue`` like
    /// every other answer on these screens, which the system's menu-style
    /// picker would not take a font from. "The app's own language" comes
    /// first, set off from the rest.
    private var translationRow: some View {
        SettingRowLabel("translate", "Translate Into") {
            Menu {
                Picker("Translate Into", selection: $target) {
                    Text("Same as App Language").tag("")
                    if !languages.isEmpty {
                        Divider()
                        ForEach(languages, id: \.minimalIdentifier) { language in
                            Text(verbatim: TranslationTarget.name(of: language))
                                .tag(language.minimalIdentifier)
                        }
                    }
                }
            } label: {
                SettingRowValue(targetName, accessory: "chevron.up.chevron.down")
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .settingRowPadding()
        .sensoryFeedback(.selection, trigger: target)
    }

    private var targetName: Text {
        target.isEmpty
            ? Text("Same as App Language")
            : Text(verbatim: TranslationTarget.name(of: Locale.Language(identifier: target)))
    }

    /// Every language the system translates into, named and sorted in the
    /// app's own language. A choice stored earlier that the list no longer
    /// carries is kept in it, so the checkmark is never lost off the screen.
    private func loadLanguages() async {
        var found = await TranslationTarget.supportedLanguages()
            .filter(TranslationTarget.isWorthOffering)
        if !target.isEmpty,
           !found.contains(where: { $0.minimalIdentifier == target }) {
            found.append(Locale.Language(identifier: target))
        }
        var seen = Set<String>()
        languages = found
            .filter { seen.insert($0.minimalIdentifier).inserted }
            .sorted {
                TranslationTarget.name(of: $0)
                    .localizedStandardCompare(TranslationTarget.name(of: $1)) == .orderedAscending
            }
    }
}
