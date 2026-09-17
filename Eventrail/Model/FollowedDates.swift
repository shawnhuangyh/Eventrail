import Foundation

/// Every date Eventernote has published for the performers the reader follows.
///
/// Following is only a name in the archive; the dates behind it live on the
/// site and have to be read. This holds the result of that reading for as long
/// as the app is open, so the Following tab and the Me card show the same
/// numbers without asking for the same pages twice.
///
/// Nothing here is written to the library. A followed performer's listing is
/// Eventernote's, not the reader's — an event only joins the library when the
/// reader adds it.
@Observable
final class FollowedDates {
    /// The upcoming dates read for each followed performer, keyed by actor id.
    /// A missing key has not been read yet; an empty one has, and the site
    /// published nothing.
    private(set) var dates: [PerformerProfile.ID: [Event]] = [:]
    private(set) var isLoading = false
    /// Why the last read stopped short, if it did. What was read before it
    /// stopped is kept: half a listing still tells the reader something.
    private(set) var failure: String?

    @ObservationIgnored private let client: EventernoteClient

    /// A performer's listing runs from the furthest published date backwards,
    /// so the upcoming half sits at the front and is almost always the first
    /// page. This is the guard against the rare performer with hundreds of
    /// announced dates, not the usual path.
    private static let pageLimit = 10

    /// Previews pass the dates in, exactly as they pass a library to
    /// ``EventStore``, so a preview neither reaches Eventernote nor sits
    /// spinning while it waits for something that will never answer.
    init(client: EventernoteClient = .shared, dates: [PerformerProfile.ID: [Event]] = [:]) {
        self.client = client
        self.dates = dates
    }

    /// Reads whichever followed performers have not been read yet, and forgets
    /// anyone no longer followed.
    ///
    /// Safe to call from more than one screen: the second caller returns while
    /// the first is still reading, and both are watching the same object, so
    /// the rows appear on both either way.
    func load(for performers: [PerformerProfile]) async {
        dates = dates.filter { id, _ in performers.contains { $0.id == id } }
        let missing = performers.filter { dates[$0.id] == nil }
        guard !missing.isEmpty, !isLoading else { return }
        await read(missing)
    }

    /// Re-reads every followed performer from scratch — what pulling the list
    /// down asks for.
    func reload(for performers: [PerformerProfile]) async {
        guard !isLoading else { return }
        dates = [:]
        await read(performers)
    }

    private func read(_ performers: [PerformerProfile]) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        // One performer at a time, and each one published as it arrives: the
        // list fills from the top rather than staying blank until the slowest
        // listing answers, and the site is asked for one page at a time.
        for performer in performers {
            guard !Task.isCancelled else { return }
            do {
                dates[performer.id] = try await upcoming(for: performer)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Named, because "could not be reached" about a list of four
                // people does not say which four are missing.
                failure = "\(performer.name): \(error.localizedDescription)"
            }
        }
    }

    /// Pages one performer's listing until the first past date shows up.
    ///
    /// The listing is ordered from the furthest published date backwards, so
    /// one past row proves every upcoming one is already in hand — the same
    /// thing ``PerformerView`` relies on for its Upcoming count.
    private func upcoming(for performer: PerformerProfile) async throws -> [Event] {
        var collected: [Event] = []
        var known: Set<Event.ID> = []

        for page in 1...Self.pageLimit {
            let result = try await client.events(forPerformer: performer, page: page)
            for event in result.items where event.isUpcoming {
                guard known.insert(event.id).inserted else { continue }
                collected.append(event)
            }
            if result.items.isEmpty || !result.hasMore { break }
            if result.items.contains(where: { !$0.isUpcoming }) { break }
        }

        return collected.sorted { $0.sortDate < $1.sortDate }
    }

    // MARK: - Reading what was read

    /// How many dates are published for one performer, or nil while their
    /// listing has not been read. Nil rather than zero: "none yet" and "not
    /// asked yet" are different things to say to the reader.
    func count(for performer: PerformerProfile) -> Int? {
        dates[performer.id]?.count
    }

    /// Every date published for the given performers, soonest first and each
    /// event once however many of them share the bill.
    func events(for performers: [PerformerProfile]) -> [Event] {
        var merged: [Event] = []
        var known: Set<Event.ID> = []
        for performer in performers {
            for event in dates[performer.id] ?? [] {
                guard known.insert(event.id).inserted else { continue }
                merged.append(event)
            }
        }
        return merged.sorted { $0.sortDate < $1.sortDate }
    }

    /// Which of the followed performers are billed on an event — what a row
    /// shows to say whose date it is.
    func billed(on event: Event, among performers: [PerformerProfile]) -> [PerformerProfile] {
        performers.filter { performer in
            dates[performer.id]?.contains { $0.id == event.id } ?? false
        }
    }
}
