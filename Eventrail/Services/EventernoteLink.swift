import Foundation

/// A link to one of Eventernote's own pages — an event, a performer, a hall —
/// pasted into Search, which opens what it points at rather than searching
/// the site for the address as words.
///
/// Read off the path alone, so the event's guest list, a performer's listing
/// or a hall's are each taken for the page they hang off. The site's other
/// pages — its directories, a member's page — are not one of these, and are
/// searched for as anything typed is.
nonisolated enum EventernoteLink: Hashable, Sendable {
    /// `/events/{id}`.
    case event(Event.ID)
    /// `/actors/{slug}/{id}`, the slug kept escaped as the site escaped it —
    /// see ``EventernoteClient/events(forPerformer:page:)``.
    case performer(slug: String, id: Int)
    /// `/places/{id}`.
    case venue(id: Int)

    /// The link in what was typed or pasted: the whole of it, or the word in
    /// it that is an Eventernote address — a post shared from elsewhere
    /// carries its title in front. With or without `https://` and `www.`.
    init?(in text: String) {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard let word = words.first(where: { $0.localizedCaseInsensitiveContains("eventernote.com/") }) else {
            return nil
        }
        var address = String(word)
        if !address.localizedCaseInsensitiveContains("://") { address = "https://" + address }
        guard let components = URLComponents(string: address),
              let host = components.host?.lowercased(),
              host == "eventernote.com" || host == "www.eventernote.com"
        else { return nil }
        self.init(path: components.percentEncodedPath.split(separator: "/").map(String.init))
    }

    private init?(path: [String]) {
        guard path.count >= 2 else { return nil }
        switch path[0] {
        case "events":
            guard !path[1].isEmpty, path[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            self = .event(path[1])
        case "actors":
            guard path.count >= 3, let id = Int(path[2]), id > 0 else { return nil }
            self = .performer(slug: path[1], id: id)
        case "places":
            guard let id = Int(path[1]), id > 0 else { return nil }
            self = .venue(id: id)
        default:
            return nil
        }
    }
}
