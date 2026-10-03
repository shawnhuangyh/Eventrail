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
    /// hall under that name, the hall's page published no address, or the
    /// address is abroad.
    private var answers: [String: Answer] = [:]

    /// Whether the clocks of halls abroad are being settled at this moment.
    private var isSettlingClocks = false

    @ObservationIgnored private let client: EventernoteClient
    /// In Caches, and emptied by Clear Cache: every answer can be read from
    /// Eventernote again. Nil in previews, which are handed their answers and
    /// neither read this device's cache nor write to it.
    @ObservationIgnored private let file: KeptFile<String, Answer>?

    /// ``Region`` is kept as its raw value rather than as itself: what is
    /// written here has to survive a case being renamed, and an unknown string
    /// reads back as an unplaced hall rather than as a decoding failure that
    /// would take the whole cache with it.
    private nonisolated struct Answer: Codable, Sendable {
        var region: String?
        /// The address the hall's page published, kept so a hall is never
        /// looked up twice. Empty where the site files no hall under the name
        /// or its page published none; nil on an answer written before the
        /// address was kept, which is what sends a hall abroad back once.
        var address: String?
        /// The clock a hall abroad keeps, once ``VenueRegions/settleClocks(for:)``
        /// has settled it — an identifier, for the reason ``region`` is a raw
        /// value. Nil in Japan, where the region already answers it.
        var timeZone: String?
        var asked: Date

        /// An address that is somewhere, and somewhere outside the site's
        /// five areas.
        var abroadAddress: String? {
            guard region == nil, let address, !address.isEmpty else { return nil }
            return address
        }
    }

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
            file = nil
        } else {
            let file = KeptFile<String, Answer>(named: "venueRegions.json", in: .caches, formerKey: "venueRegions")
            self.file = file
            answers = file.read()
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

    /// Which clock a hall outside Japan keeps, where ``settleClocks(for:)``
    /// has settled it. Nil in Japan — ``region(of:)`` answers that — and
    /// wherever nothing has.
    func timeZone(of event: Event) -> TimeZone? {
        answers[Self.key(event)]?.timeZone.flatMap(TimeZone.init(identifier:))
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
    /// has been somewhere before never pays to place it again. A hall abroad
    /// that a placing has already retimed brings its clock along.
    func learn(from events: [Event]) {
        var learned = false
        for event in events {
            let key = Self.key(event)
            guard !key.isEmpty, let address = event.publishedAddress, !address.isEmpty else { continue }
            let region = Region.containing(address: address)
            let zone = region == nil && event.timeZone != Event.publishedZone
                ? event.timeZone.identifier : nil
            let known = answers[key]
            guard known?.region == nil,
                  known?.address?.isEmpty != false || (zone != nil && known?.timeZone == nil)
            else { continue }
            answers[key] = Answer(region: region?.rawValue, address: address,
                                  timeZone: zone ?? known?.timeZone, asked: .now)
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
                answers[venue] = Answer(region: region?.rawValue, address: address ?? "", asked: .now)
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

    /// A ration of halls looked up, and then the clocks of whichever of them
    /// are abroad — what the Following tab and the Me card run as they load.
    func settle(_ events: [Event]) async {
        await place(events)
        await settleClocks(for: events)
    }

    /// Settles which clock each hall abroad in these events keeps, from the
    /// address ``place(_:)`` kept for it — what lets the Following tab show
    /// and end an event abroad on its hall's own time.
    ///
    /// ``VenuePlaces`` is asked first, on the terms an import's arrivals are
    /// (``VenuePlaces/placeUnplaced(_:onProgress:)``: only halls it has no
    /// answer for, paced, never narrowed to a building), so a hall already
    /// placed costs nothing and a new one is placed once for good. Where that
    /// settles no clock — no answer, or the phone's Maps may not be asked — the
    /// address is read for a country that keeps one clock. A hall neither can
    /// date keeps no clock, and ``FollowedDates`` then waits for its day to be
    /// over everywhere rather than guessing.
    ///
    /// A settled clock is written down with the hall, since a hall does not
    /// move: the next run asks nothing about it.
    func settleClocks(for events: [Event]) async {
        guard file != nil, !isSettlingClocks else { return }
        var seen: Set<String> = []
        let halls: [(key: String, event: Event)] = events.compactMap { event in
            let key = Self.key(event)
            guard seen.insert(key).inserted, let answer = answers[key],
                  answer.timeZone == nil, let address = answer.abroadAddress
            else { return nil }
            var event = event
            event.venueAddress = address
            return (key, event)
        }
        guard !halls.isEmpty else { return }

        isSettlingClocks = true
        defer { isSettlingClocks = false }

        let places = VenuePlaces.shared
        _ = await places.placeUnplaced(halls.map(\.event)) { _ in }
        let placed = places.timeZones(for: halls.map(\.event))

        var settled = false
        for hall in halls {
            guard let address = hall.event.venueAddress,
                  let zone = placed[hall.event.id] ?? Self.clock(readingAddress: address)
            else { continue }
            answers[hall.key]?.timeZone = zone.identifier
            settled = true
            Self.log.info("venue \(hall.key, privacy: .public) keeps \(zone.identifier, privacy: .public)")
        }
        if settled { save() }
    }

    /// The clock an address abroad plainly names a country for, where that
    /// country keeps one — the reading ``VenueCountries`` makes for a hall
    /// OpenStreetMap placed, made here without anybody placing it.
    private static func clock(readingAddress address: String) -> TimeZone? {
        if let country = VenueCountries.country(of: address) {
            return VenueCountries.timeZone(forCountry: country)
        }
        return VenueCountries.isMainlandChina(address) ? VenueCountries.timeZone(forCountry: "cn") : nil
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
            // Asked before the address was kept: once more, for the address.
            guard let address = answer.address else { return key }
            // An address abroad is an answer for good — a hall does not move.
            guard address.isEmpty else { return nil }
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

    /// Throws away every answer this device has written down, so each hall is
    /// looked up again the next time a screen asks which area it is in.
    ///
    /// Two requests a hall to rebuild and twenty halls a run — see
    /// ``place(_:)`` — so this is the reader asking rather than anything the
    /// app ever does on its own.
    func clear() {
        guard !answers.isEmpty else { return }
        answers = [:]
        file?.remove()
    }

    private func save() {
        file?.write(&answers)
    }
}
