import Foundation
import os

/// Which part of the country each venue is in.
///
/// A listing row publishes the hall's name and nothing else — no address, no
/// place id — so the area a followed date is in is simply not on the page the
/// Following tab reads. It is two pages further on: the site's venue search
/// finds the hall by the exact name the row printed, and the hall's own page
/// publishes the address, which opens with the prefecture.
///
/// So this asks for those two pages once per hall and writes the answer down.
/// Per device rather than into the archive, the choice ``VenuePlaces`` makes
/// for the same reason: where a hall is, is a fact about the world rather than
/// a record the reader owns, every device can read it for itself, and a hall
/// does not move. What is kept is one short line per hall the reader follows
/// somebody into, which is a far smaller set than their events.
///
/// Nothing here is ever asked for on the way to the screen. The Following tab
/// draws its rows first and places their halls afterwards, so a filter that
/// has not finished reading narrows to less than it eventually will — which is
/// why the sheet says so rather than letting the reader think the rest is not
/// there.
@Observable
final class VenueRegions {
    /// The same category ``VenuePlaces`` logs under: both answer "where is
    /// this hall", and reading one without the other tells half the story.
    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "venues")

    /// Whether halls are being looked up at this moment.
    private(set) var isPlacing = false

    /// What each hall asked about turned out to be, keyed by the name the
    /// listing row printed. A nil region is an answer too: the site files no
    /// hall under that name, or the hall's page published no address.
    private var answers: [String: Answer] = [:]

    @ObservationIgnored private let client: EventernoteClient
    /// Previews are handed their answers, and neither read this device's cache
    /// nor write to it.
    @ObservationIgnored private let persists: Bool

    /// ``Region`` is kept as its raw value rather than as itself: what is
    /// written here has to survive a case being renamed, and an unknown string
    /// reads back as an unplaced hall rather than as a decoding failure that
    /// would take the whole cache with it.
    private struct Answer: Codable {
        var region: String?
        var asked: Date
    }

    private static let cacheKey = "venueRegions"

    /// How many halls one run may look up. Each is two requests — the venue
    /// search and then the hall's page — so a first run over a long Following
    /// list would otherwise fire off hundreds of them and be throttled for its
    /// trouble. What this run does not reach, the next one does.
    private static let lookupsPerRun = 20

    /// How long "the site files no such hall" is believed for. The month
    /// ``VenuePlaces`` gives Maps, for the reason it gives: a name that finds
    /// nothing today may be a hall the site has filed properly by next month,
    /// and a permanent no would leave that event out of every area for good.
    private static let patience: TimeInterval = 30 * 24 * 60 * 60

    init(client: EventernoteClient = .shared, placed: [String: Region]? = nil) {
        self.client = client
        if let placed {
            answers = placed.mapValues { Answer(region: $0.rawValue, asked: .now) }
            persists = false
        } else {
            answers = Self.stored
            persists = true
        }
    }

    // MARK: - What is already known

    /// Which part of the country an event is in, as far as anything can tell.
    ///
    /// An event imported from its own page carries the venue's address already,
    /// so it is placed for nothing and never costs a request. Everything else
    /// waits on ``place(_:)``, and is nowhere until that answers.
    func region(of event: Event) -> Region? {
        if let address = event.publishedAddress,
           let region = Region.containing(address: address) {
            return region
        }
        return answers[Self.key(event)]?.region.flatMap(Region.init(rawValue:))
    }

    /// How a list of events breaks down by area, with whatever nothing has
    /// placed yet counted under nil — what the filter sheet puts beside each
    /// area, and what it says about the rest.
    func tally(_ events: [Event]) -> [Region?: Int] {
        events.reduce(into: [:]) { tally, event in
            tally[region(of: event), default: 0] += 1
        }
    }

    /// How many of these halls are still to be looked up — what tells a screen
    /// whether waiting would change anything.
    func pendingCount(_ events: [Event]) -> Int { pending(in: events).count }

    /// Takes the addresses a library already holds as answers about the halls
    /// in it.
    ///
    /// An event imported from its own page carries its venue's address, and a
    /// hall is the same hall whichever list it turned up in — so a reader who
    /// has been somewhere before never pays to place it again.
    func learn(from events: [Event]) {
        var learned = false
        for event in events {
            let key = Self.key(event)
            guard !key.isEmpty, answers[key]?.region == nil,
                  let address = event.publishedAddress,
                  let region = Region.containing(address: address)
            else { continue }
            answers[key] = Answer(region: region.rawValue, asked: .now)
            learned = true
        }
        if learned { save() }
    }

    // MARK: - Asking

    /// Looks up whichever of these events' halls are not placed yet, as many as
    /// this run has room for.
    ///
    /// One hall at a time and each answer published as it arrives, the way
    /// ``FollowedDates`` reads its listings: the areas fill in rather than
    /// appearing all at once at the end, and the site is asked for one page at
    /// a time.
    func place(_ events: [Event]) async {
        guard !isPlacing else { return }
        let waiting = Array(pending(in: events).prefix(Self.lookupsPerRun))
        guard !waiting.isEmpty else { return }

        isPlacing = true
        defer { isPlacing = false }

        for venue in waiting {
            guard !Task.isCancelled else { return }
            do {
                let address = try await client.address(forVenue: venue)
                let region = address.flatMap(Region.containing(address:))
                answers[venue] = Answer(region: region?.rawValue, asked: .now)
                save()
                Self.log.info("venue \(venue, privacy: .public) → \(region?.rawValue ?? "nowhere the site names", privacy: .public)")
            } catch is CancellationError {
                return
            } catch {
                // Offline, or asked too often. Nothing is written down, so the
                // next run asks again — and nothing more is asked of the site
                // in this one.
                Self.log.error("venue \(venue, privacy: .public) → lookup failed: \(error, privacy: .public)")
                return
            }
        }
    }

    /// The halls in these events that are worth asking about, soonest first —
    /// the order the events arrive in — and each hall once.
    private func pending(in events: [Event]) -> [String] {
        var seen: Set<String> = []
        return events.compactMap { event in
            guard region(of: event) == nil else { return nil }
            let key = Self.key(event)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            guard let answer = answers[key] else { return key }
            // Asked, and the site had nothing to say. Left alone until the
            // month is up.
            return answer.asked.timeIntervalSinceNow < -Self.patience ? key : nil
        }
    }

    /// The name the listing row printed, which is the name the site's venue
    /// search files the hall under — the two are the same string, which is what
    /// makes an exact match the right test.
    private static func key(_ event: Event) -> String {
        event.venue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Where the answers are kept

    private static var stored: [String: Answer] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Answer].self, from: data)) ?? [:]
    }

    private func save() {
        guard persists else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(answers), forKey: Self.cacheKey)
    }
}
