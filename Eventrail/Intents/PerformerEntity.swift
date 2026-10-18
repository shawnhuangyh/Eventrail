import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// A performer the reader follows, as Spotlight, Siri and Shortcuts know them:
/// who Eventernote says they are, and nothing more. Opens their page.
///
/// Only the followed: everyone billed on nine hundred events would bury the
/// people the reader actually looks for, and an event is found by every name
/// on its bill already (``EventEntity``).
nonisolated struct PerformerEntity: IndexedEntity, Codable, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("entity.performer", defaultValue: "Performer"))
    static let defaultQuery = PerformerQuery()

    /// Eventernote's actor id.
    let id: Int
    let name: String
    /// The kana reading the site prints beside the name.
    let reading: String?
    /// The already-escaped path segment the site addresses their pages by.
    let slug: String
    /// What Spotlight prints under the name to say why they are there —
    /// "Following", in the app's language.
    let caption: String

    var profile: PerformerProfile {
        PerformerProfile(id: id, name: name, reading: reading, fanCount: nil, slug: slug)
    }

    var displayRepresentation: DisplayRepresentation {
        if let reading {
            DisplayRepresentation(title: "\(name)", subtitle: "\(reading)", image: .init(systemName: "music.microphone"))
        } else {
            DisplayRepresentation(title: "\(name)", image: .init(systemName: "music.microphone"))
        }
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = name
        set.displayName = name
        set.contentDescription = [caption, reading ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        set.keywords = Self.soundings(of: reading)
        return set
    }

    func matches(_ text: String) -> Bool {
        ([name] + Self.soundings(of: reading)).contains { $0.localizedStandardContains(text) }
    }

    /// The ways a reading can be typed: as the site prints it, in the other
    /// kana, and in romaji — あいな, アイナ and aina.
    ///
    /// Only the reading is turned into romaji, never the name: the name is
    /// written in kanji, and the system's transliteration reads kanji as
    /// Mandarin.
    static func soundings(of reading: String?) -> [String] {
        guard let reading = reading?.trimmingCharacters(in: .whitespacesAndNewlines), !reading.isEmpty else {
            return []
        }
        let forms = [
            reading,
            reading.applyingTransform(.hiraganaToKatakana, reverse: false),
            reading.applyingTransform(.hiraganaToKatakana, reverse: true),
            reading.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false),
        ]
        var seen = Set<String>()
        return forms.compactMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

nonisolated extension PerformerEntity {
    init(_ profile: PerformerProfile) {
        self.init(id: profile.id, name: profile.name, reading: profile.reading, slug: profile.slug,
                  caption: String(localized: "Following"))
    }
}

@MainActor
extension PerformerEntity {
    static func all(in store: EventStore) -> [PerformerEntity] {
        store.followedProfiles.map(PerformerEntity.init)
    }
}

nonisolated struct PerformerQuery: EntityStringQuery {
    func entities(for identifiers: [PerformerEntity.ID]) async throws -> [PerformerEntity] {
        let wanted = Set(identifiers)
        return await PerformerEntity.all(in: Launch.shared.store).filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PerformerEntity] {
        await PerformerEntity.all(in: Launch.shared.store).filter { $0.matches(string) }
    }

    func suggestedEntities() async throws -> [PerformerEntity] {
        await PerformerEntity.all(in: Launch.shared.store)
    }
}
