import AppIntents
import Observation

/// What Siri, Shortcuts or a Spotlight result asked the app to show, through
/// one of the intents below, until the window in front takes it.
///
/// Process-wide, as ``LotteryReminders/opened`` is: an intent is one for the
/// app, and on an iPad each window has a root of its own. So it waits here,
/// and the root of whichever window is active opens it there — over whatever
/// sheet is up, through ``OutsideOpens`` — as it comes forward or at once.
@Observable
final class IntentOpens {
    static let shared = IntentOpens()

    var waiting: IntentOpen?

    private init() {}
}

/// One thing an intent asked for.
nonisolated enum IntentOpen: Hashable {
    /// The event's sheet, by its id — found in the library or on a followed
    /// performer's listing as it is opened.
    case event(Event.ID)
    case performer(PerformerProfile)
    case venue(VenueLink)
    /// The Search tab, searching Eventernote for this.
    case search(String)
}

struct OpenEventIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Event"

    @Parameter(title: LocalizedStringResource("entity.event", defaultValue: "Event"))
    var target: EventEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentOpens.shared.waiting = .event(target.id)
        return .result()
    }
}

struct OpenPerformerIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Performer"

    @Parameter(title: LocalizedStringResource("entity.performer", defaultValue: "Performer"))
    var target: PerformerEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentOpens.shared.waiting = .performer(target.profile)
        return .result()
    }
}

struct OpenVenueIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Venue"

    @Parameter(title: LocalizedStringResource("entity.venue", defaultValue: "Venue"))
    var target: VenueEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentOpens.shared.waiting = .venue(target.link)
        return .result()
    }
}

/// The soonest event in the library, opened — what "my next event" means
/// everywhere else in the app: the Next Event widget and the watch count down
/// to the same one, ticket or not.
struct OpenNextEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Next Event"
    static let supportedModes: IntentModes = .foreground

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = Launch.shared.store.upcoming.first else {
            return .result(dialog: "There are no upcoming events in your library.")
        }
        IntentOpens.shared.waiting = .event(next.id)
        return .result(dialog: "\(next.title)")
    }
}

/// Eventernote's own search, from Siri or Shortcuts: the Search tab, with the
/// term typed in — as "Search in App" under Spotlight's results opens it.
struct SearchEventernoteIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Eventernote"
    static let searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: "Search")
    var criteria: StringSearchCriteria

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentOpens.shared.waiting = .search(criteria.term)
        return .result()
    }
}

/// What Siri answers to without the reader setting anything up. The phrases
/// are translated in AppShortcuts.xcstrings, which is where Siri reads them.
struct EventrailShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenNextEventIntent(),
            phrases: [
                "Show my next event in \(.applicationName)",
                "What's my next event in \(.applicationName)",
            ],
            shortTitle: "Next Event",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: OpenEventIntent(),
            phrases: ["Open an event in \(.applicationName)"],
            shortTitle: "Open Event",
            systemImageName: "music.microphone"
        )
        AppShortcut(
            intent: SearchEventernoteIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search events in \(.applicationName)",
            ],
            shortTitle: "Search Eventernote",
            systemImageName: "magnifyingglass"
        )
    }
}
