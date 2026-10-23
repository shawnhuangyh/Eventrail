import Foundation

/// A forward-only cursor over one fetched HTML page.
///
/// Eventernote publishes no API and this target has no dependencies, so the
/// import walks the site's server-rendered templates with literal markers taken
/// from the markup. Every accessor is failable: a template that has changed
/// yields a nil field rather than a wrong one.
nonisolated struct HTMLCursor {
    private let html: Substring
    private var position: Substring.Index

    init(_ html: some StringProtocol) {
        self.html = Substring(html)
        position = self.html.startIndex
    }

    /// Where `marker` next occurs in `text`, matched byte for byte in place
    /// (`memmem`) — some thirty times faster than Foundation's `range(of:)`
    /// over a listing of a hundred rows, measured, and a page is walked with
    /// hundreds of these. (The standard library's own `firstRange(of:)` over
    /// the bytes was ten times slower than Foundation's.) The markers are the
    /// site's own markup, written as it writes it, so a match of bytes is the
    /// match that was meant; and UTF-8 matches only on a character's first
    /// byte. A page not stored as UTF-8 has no bytes to hand, and is searched
    /// by Foundation.
    static func find(_ marker: String, in text: Substring) -> Range<Substring.Index>? {
        var marker = marker
        let found = marker.withUTF8 { needle in
            text.utf8.withContiguousStorageIfAvailable { bytes -> Range<Substring.Index>? in
                guard let base = bytes.baseAddress, let wanted = needle.baseAddress, !needle.isEmpty,
                      let hit = memmem(base, bytes.count, wanted, needle.count)
                else { return nil }
                let lower = text.utf8.index(text.utf8.startIndex, offsetBy: UnsafeRawPointer(hit) - UnsafeRawPointer(base))
                return lower ..< text.utf8.index(lower, offsetBy: needle.count)
            }
        }
        if let found { return found }
        return text.range(of: marker)
    }

    /// Everything still ahead of the cursor.
    var rest: Substring { html[position...] }

    /// Moves the cursor past the next `marker`, or leaves it exactly where it
    /// was. Staying put matters: a block a page omits must not let the next
    /// field read out of a later record.
    @discardableResult
    mutating func advance(past marker: String) -> Bool {
        guard let range = Self.find(marker, in: rest) else { return false }
        position = range.upperBound
        return true
    }

    /// The markup between the cursor and the next `marker`, consuming both.
    mutating func take(upTo marker: String) -> Substring? {
        guard let range = Self.find(marker, in: rest) else { return nil }
        defer { position = range.upperBound }
        return html[position ..< range.lowerBound]
    }

    /// The readable text an element wraps — `advance(past:)` then
    /// `take(upTo:)`, which is the shape almost every imported field has.
    mutating func text(after opening: String, upTo closing: String) -> String? {
        guard advance(past: opening), let markup = take(upTo: closing) else { return nil }
        let text = markup.htmlText
        return text.isEmpty ? nil : text
    }

    /// Splits what is left into one slice per occurrence of `marker`, discarding
    /// anything before the first. List pages are divided this way so each row is
    /// scanned inside its own bounds.
    func slices(startingAt marker: String) -> [Substring] {
        var starts: [Substring.Index] = []
        var searchFrom = position
        while let range = Self.find(marker, in: html[searchFrom...]) {
            starts.append(range.lowerBound)
            searchFrom = range.upperBound
        }
        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : html.endIndex
            return html[starts[index] ..< end]
        }
    }
}

nonisolated extension StringProtocol {
    /// Tags removed, entities resolved and the edges trimmed — the form every
    /// imported field is stored in.
    var htmlText: String {
        var text = ""
        var insideTag = false
        for character in self {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { text.append(character) }
            }
        }
        return text.decodingHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var decodingHTMLEntities: String { HTMLEntities.decode(self) }
}

/// The named and numeric escapes Eventernote's templates emit.
nonisolated enum HTMLEntities {
    private static let named: [Substring: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hearts": "\u{2665}", "mdash": "—", "ndash": "–",
    ]

    static func decode(_ source: some StringProtocol) -> String {
        guard source.contains("&") else { return String(source) }

        var decoded = ""
        var rest = Substring(source)
        while let ampersand = rest.firstIndex(of: "&") {
            decoded += rest[..<ampersand]
            let body = rest[rest.index(after: ampersand)...]
            // A bare "&" is common in imported titles; only a short, closed run
            // after it is treated as an entity.
            guard let semicolon = body.firstIndex(of: ";"),
                  body.distance(from: body.startIndex, to: semicolon) <= 8,
                  let replacement = replacement(for: body[..<semicolon])
            else {
                decoded.append("&")
                rest = body
                continue
            }
            decoded += replacement
            rest = body[body.index(after: semicolon)...]
        }
        return decoded + rest
    }

    private static func replacement(for name: Substring) -> String? {
        guard name.first == "#" else { return named[name] }
        let digits = name.dropFirst()
        let scalar: Unicode.Scalar? = if digits.first == "x" || digits.first == "X" {
            UInt32(digits.dropFirst(), radix: 16).flatMap(Unicode.Scalar.init)
        } else {
            UInt32(digits).flatMap(Unicode.Scalar.init)
        }
        return scalar.map { String(Character($0)) }
    }
}
