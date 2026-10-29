import Foundation

/// What a search of the reader's own library looks for — My Events' search
/// field, which asks nothing of Eventernote.
///
/// Every word typed has to turn up somewhere in the event: its title, the
/// names billed on it, its hall, or the reader's own note. So 武道館 TrySail
/// finds TrySail at the Budokan, wherever each word is.
///
/// Read the way the site's own text is typed in, rather than letter for
/// letter: full- and half-width alike (ＴｒｙＳａｉｌ, ﾄﾗｲｾｲﾙ), either case,
/// and hiragana as katakana — a title spells a reading one way and the reader
/// the other. Voiced marks stay: ハル is not バル.
nonisolated struct LibrarySearch: Hashable, Sendable {
    let words: [String]

    init(_ query: String) {
        words = Self.folded(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether nothing is asked for, which is every event.
    var isEmpty: Bool { words.isEmpty }

    func matches(_ event: Event, note: String) -> Bool {
        guard !isEmpty else { return true }
        // A line apart, so no word is found straddling two of them.
        let fields = [event.title, event.artist, event.venue, note] + event.performers.map(\.name)
        let text = Self.folded(fields.joined(separator: "\n"))
        return words.allSatisfy(text.contains)
    }

    /// `text` as it is compared: compatibility-composed (full-width letters
    /// to plain ones, half-width kana to whole ones with their marks), in
    /// lower case, and with hiragana written as katakana.
    static func folded(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            // ぁ to ゖ and the iteration marks ゝゞ sit 0x60 below their katakana.
            if (0x3041...0x3096).contains(scalar.value) || (0x309D...0x309E).contains(scalar.value),
               let katakana = Unicode.Scalar(scalar.value + 0x60) {
                scalars.append(katakana)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
