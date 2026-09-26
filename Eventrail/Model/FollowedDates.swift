import Foundation
import os

/// Every date Eventernote has published for the performers the reader follows.
///
/// Following is only a name in the archive; the dates behind it live on the
/// site and have to be read. This holds the result of that reading — in memory
/// while the app is open, so the Following tab and the Me card show the same
/// numbers without asking for the same pages twice, and on this device between
/// launches, so a reader who opens the app four times in an afternoon pays for
/// one read rather than four.
///
/// **Opening a screen reads a listing again only once it is stale; the reader
/// asking reads it regardless.** Every followed performer being read afresh on
/// every launch is a request per person before a single row is drawn, and a
/// reader following twenty people was asking Eventernote for twenty listings
/// every time they opened the app — which is what gets a site that publishes
/// no API to refuse this one. So an answer stands for ``freshness`` as far as
/// the app's own reading goes, and pulling the list down asks about everybody
/// on the spot, because that is the reader saying so.
///
/// **A read that fails never costs what was already held.** The cached dates
/// stay on screen, ``failure`` says why they were not replaced, and the
/// Following tab puts that under the list rather than instead of it.
///
/// Kept per device rather than in the archive, the choice ``VenuePlaces`` and
/// ``VenueRegions`` make for the same reason: these are Eventernote's facts
/// about who is playing where, not records the reader owns, so they have no
/// business travelling to their other devices, into a merge, or into a backup.
/// The file sits in Caches, where the system may throw it away when the device
/// is short of room — which is exactly the right thing to do to it.
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

    /// When each performer's listing was last read, which is what decides
    /// whether it is asked for again. Only a read that landed is written down:
    /// a listing that failed is stale, and the next screen that asks for it
    /// tries again.
    private var readAt: [PerformerProfile.ID: Date] = [:]

    /// Which generation of the cache the dates in hand were read under.
    ///
    /// Clearing the cache from Settings empties an object two live screens are
    /// watching, and neither would go back for what it lost — a `.task(id:)`
    /// keyed on who is followed has no reason to run again when nobody has
    /// been followed or unfollowed. So the identity a screen loads under
    /// carries this too: see ``loadKey(for:)``.
    private(set) var generation = 0

    @ObservationIgnored private let client: EventernoteClient

    /// Which clock a row's hall keeps, where anything has established it —
    /// Tokyo's for a hall in Japan, the hall's own for one abroad.
    ///
    /// A listing row is read on Tokyo time whatever its hall, the way every
    /// import starts (see ``Event/published(in:)``), and a listing says
    /// nothing about where the hall is: read as it came, a 21:00 finish in
    /// Taipei is an hour early and one in Los Angeles is the morning before
    /// the show. So a row whose hall's clock is known is re-read on it before
    /// it is shown or judged over — which also puts My Time right for it —
    /// and a row whose clock is not stays as it came and leaves only when its
    /// day is over everywhere (``Event/isUpcomingAnywhere``). Handed in by
    /// ``RootView``; nil until then, the safe answer.
    @ObservationIgnored var hallZone: (Event) -> TimeZone? = { _ in nil }
    /// Previews are handed their dates, and neither read this device's cache
    /// nor write to it.
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// The read going on now, so a second caller can wait for it rather than
    /// start another — see ``reload(for:)``.
    @ObservationIgnored private var running: Task<Outcome?, Never>?

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "following")

    /// A performer's listing runs from the furthest published date backwards,
    /// so the upcoming half sits at the front and is almost always the first
    /// page. This is the guard against the rare performer with hundreds of
    /// announced dates, not the usual path.
    private static let pageLimit = 10

    /// How old a listing may be before opening a screen reads it again by
    /// itself.
    ///
    /// Only the app's own reading is held to it. Long enough that switching to
    /// the Following tab repeatedly in a day asks Eventernote nothing, short
    /// enough that a date announced this morning is on the screen by this
    /// evening without the reader doing anything. Pulling the list down is
    /// never held to it.
    static let freshness = Freshness.window

    /// How long between one performer's listing and the next.
    ///
    /// The listings are read one at a time already; this is the gap between
    /// them. A first read of a long Following list is still a request per
    /// person, and firing them off as fast as they answer is the shape of
    /// traffic that gets refused — ``VenuePlaces`` paces its own run for the
    /// same reason, learned against Maps. It costs a fifth of a second per
    /// person on a read that only happens when something is actually stale.
    private static let pace: Duration = .milliseconds(200)

    /// Previews pass the dates in, exactly as they pass a library to
    /// ``EventStore``, so a preview neither reaches Eventernote nor sits
    /// spinning while it waits for something that will never answer. The
    /// default reads whatever this device already had.
    init(client: EventernoteClient = .shared, dates: [PerformerProfile.ID: [Event]]? = nil) {
        self.client = client
        if let dates {
            self.dates = dates
            persists = false
        } else {
            let cached = Self.stored
            // A listing holds what was upcoming when it was read, and a date
            // that has since passed is not a date the Following tab shows.
            // Over everywhere, since no hall's clock is known yet: the rest is
            // ``dropFinished()``'s, once it is.
            self.dates = cached.dates.mapValues { $0.filter(\.isUpcomingAnywhere) }
            readAt = cached.readAt
            persists = true
        }
    }

    deinit { pendingSave?.cancel() }

    /// How one read went: how many listings it asked for, how many came back,
    /// and why it fell short if it did — what the notice after a refresh says.
    struct Outcome {
        let asked: Int
        let read: Int
        let failure: String?
    }

    /// Reads whichever followed performers have nothing in hand or nothing
    /// recent, and forgets anyone no longer followed.
    ///
    /// Safe to call from more than one screen: the second caller returns while
    /// the first is still reading, and both are watching the same object, so
    /// the rows appear on both either way.
    ///
    /// Nil when nothing was read — everybody was fresh, another screen was
    /// already reading, or the screen went away first — so a notice is only
    /// ever posted about a read that happened.
    @discardableResult
    func load(for performers: [PerformerProfile]) async -> Outcome? {
        dropFinished()
        forget(everyoneBut: performers)
        let stale = performers.filter { !isFresh($0.id) }
        guard !stale.isEmpty, running == nil else { return nil }
        return await run(stale)
    }

    /// Re-reads every followed performer, however recently — what pulling the
    /// list down asks for.
    ///
    /// Over the top of what is held rather than after emptying it: each
    /// listing is replaced as its fresh copy lands, and one the site will not
    /// give back keeps the copy it had. A refresh that was refused should leave
    /// the reader looking at yesterday's dates and a line saying why, not at a
    /// blank tab.
    ///
    /// A pull that lands while a read is already going — the one opening the
    /// tab started, most often, since a long list takes several seconds —
    /// waits for that read and reports it, rather than returning at once with
    /// nothing to say. That read is already asking for everybody who was
    /// stale; starting a second beside it would ask the site for the same
    /// pages twice.
    @discardableResult
    func reload(for performers: [PerformerProfile]) async -> Outcome? {
        // First, and without asking anybody: the end times are already here.
        dropFinished()
        if let running { return await running.value }
        forget(everyoneBut: performers)
        return await run(performers)
    }

    /// Reads as a task of its own rather than as part of whichever screen
    /// asked, so a second caller can wait on it — and so leaving the tab
    /// halfway does not throw away a read the site has already been asked for.
    /// What it reads is cached either way; the screen that comes back finds it
    /// there.
    private func run(_ performers: [PerformerProfile]) async -> Outcome? {
        let task = Task { await self.read(performers) }
        running = task
        let outcome = await task.value
        // Only this run's own marker: a clear in the meantime lets the next
        // run start at once, and that one's is not this one's to drop.
        if running == task { running = nil }
        return outcome
    }

    /// Throws away what this device has read and holds, so the next screen
    /// that asks reads it from Eventernote again.
    ///
    /// The dates in memory go with the file. What is on screen is what was
    /// cached; leaving it there would be a cleared cache that still showed its
    /// contents, and the screens watching this go back for it themselves —
    /// see ``generation``.
    func clear() {
        // A read still going would write what it finds back into the cache
        // just emptied. Cancelled, it reports nothing, so no notice claims a
        // refresh the reader has just thrown away.
        // And let go of at once rather than when it winds down: the screens
        // go back for what they lost the moment ``generation`` moves, and
        // a marker still held would turn every one of them away.
        running?.cancel()
        running = nil
        isLoading = false
        dates = [:]
        readAt = [:]
        failure = nil
        generation += 1
        pendingSave?.cancel()
        pendingSave = nil
        guard persists else { return }
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    /// What a screen's read of these performers is identified by: who they
    /// are, and which generation of the cache they were read under.
    ///
    /// Handed to `.task(id:)`, so following somebody new re-reads — and so
    /// does clearing the cache out from under a screen that is already open.
    func loadKey(for performers: [PerformerProfile]) -> [String] {
        performers.map { String($0.id) } + ["generation \(generation)"]
    }

    /// Whether this performer's dates are in hand and recent enough to stand.
    private func isFresh(_ id: PerformerProfile.ID) -> Bool {
        guard dates[id] != nil, let read = readAt[id] else { return false }
        return read.timeIntervalSinceNow > -Self.freshness
    }

    /// Takes out of the cache every date that is over — its day gone, or its
    /// published end — before anything is asked of Eventernote.
    ///
    /// The end time is in the cache already, so there is nothing to wait for:
    /// a pull clears a finished night from the list the moment it starts, and
    /// the listing it then reads would leave it out only because its day had
    /// not finished. ``events(for:)`` checks the same thing as it is read, for
    /// the redraws in between.
    func dropFinished() {
        let kept = dates.mapValues { $0.filter { !isOver(onHallClock($0)) } }
        let dropped = dates.values.map(\.count).reduce(0, +) - kept.values.map(\.count).reduce(0, +)
        guard dropped > 0 else { return }
        dates = kept
        save()
    }

    /// The row re-read on its hall's clock, or as it came where that clock is
    /// not known — see ``hallZone``. What is shown and judged; the cache keeps
    /// the row as the listing printed it, so the next read replaces like with
    /// like.
    private func onHallClock(_ event: Event) -> Event {
        hallZone(event).map(event.published(in:)) ?? event
    }

    /// Whether a date is over: on a row whose hall's clock is known, its day
    /// gone or its published end gone by. A row on an assumed clock waits for
    /// its day to be over everywhere, since read on Tokyo time its end — and
    /// its day's — could be hours out either way: a Los Angeles night would
    /// go the morning it opens.
    private func isOver(_ event: Event) -> Bool {
        guard hallZone(event) != nil else { return !event.isUpcomingAnywhere }
        return !event.isUpcoming || event.hasEnded
    }

    /// Drops whoever is no longer followed, so their dates stop being counted
    /// and stop being kept.
    private func forget(everyoneBut performers: [PerformerProfile]) {
        let followed = Set(performers.map(\.id))
        guard dates.contains(where: { !followed.contains($0.key) }) else { return }
        dates = dates.filter { followed.contains($0.key) }
        readAt = readAt.filter { followed.contains($0.key) }
        save()
    }

    private func read(_ performers: [PerformerProfile]) async -> Outcome? {
        var landed = 0
        // A run the cache was cleared under writes nothing more, and leaves
        // the state alone for whichever run replaced it.
        let generation = generation
        isLoading = true
        failure = nil
        // Whatever the run got through is worth keeping, including when it was
        // cancelled partway or the site stopped answering.
        defer {
            if generation == self.generation {
                isLoading = false
                save()
            }
        }

        // One performer at a time, and each one published as it arrives: the
        // list fills from the top rather than staying blank until the slowest
        // listing answers, and the site is asked for one page at a time.
        for (index, performer) in performers.enumerated() {
            guard !Task.isCancelled else { return nil }
            if index > 0 {
                guard (try? await Task.sleep(for: Self.pace)) != nil else { return nil }
            }
            do {
                let upcoming = try await upcoming(for: performer)
                guard generation == self.generation else { return nil }
                dates[performer.id] = upcoming
                readAt[performer.id] = .now
                landed += 1
            } catch is CancellationError {
                return nil
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return nil }
                // Refused for asking too often: the rest of the list would be
                // refused too, and asking anyway only lengthens the refusal.
                // Everybody not reached keeps what was cached for them.
                if (error as? EventernoteClient.Failure)?.isRateLimited == true {
                    failure = error.localizedDescription
                    return Outcome(asked: performers.count, read: landed, failure: failure)
                }
                // Named, because "could not be reached" about a list of four
                // people does not say which four are missing.
                failure = "\(performer.name): \(error.localizedDescription)"
            }
        }
        return Outcome(asked: performers.count, read: landed, failure: failure)
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
            // Not a night already over, though the page lists it: its end is
            // published and gone by. Paging still stops on the day, below.
            for event in result.items where !isOver(onHallClock(event)) {
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
        dates[performer.id]?.count { !isOver(onHallClock($0)) }
    }

    /// Every date published for the given performers, soonest first and each
    /// event once however many of them share the bill.
    func events(for performers: [PerformerProfile]) -> [Event] {
        var merged: [Event] = []
        var known: Set<Event.ID> = []
        for performer in performers {
            // A night whose published end has gone by is over, though its day
            // is not: kept in the cache until the day ends, like every other
            // date, and left out of what the tab shows once it finishes.
            // Checked as the tab reads rather than when the listing was read,
            // so it goes at the tab's next redraw rather than its next read.
            for listed in dates[performer.id] ?? [] {
                let event = onHallClock(listed)
                guard !isOver(event), known.insert(event.id).inserted else { continue }
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

    // MARK: - Where the answers are kept

    /// One listing as it is written down: what was read, and when.
    ///
    /// `nonisolated`, because the encoding it is handed to happens off the
    /// main actor — a conformance isolated to this class could not be used
    /// there.
    private nonisolated struct Cache: Codable, Sendable {
        var dates: [PerformerProfile.ID: [Event]] = [:]
        var readAt: [PerformerProfile.ID: Date] = [:]
    }

    /// In Caches rather than Application Support, and rather than
    /// `UserDefaults` where the venue answers live: this is a few hundred
    /// events rather than a line per hall, it is all re-readable, and a device
    /// short of room is welcome to take it back.
    private static let cacheURL: URL = {
        let directory = URL.cachesDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "followedDates.json")
    }()

    private static var stored: Cache {
        guard let data = try? Data(contentsOf: cacheURL) else { return Cache() }
        return (try? JSONDecoder().decode(Cache.self, from: data)) ?? Cache()
    }

    /// Writes after a pause, and off the main actor.
    ///
    /// A run publishes each listing as it lands, so writing on every one of
    /// them would re-encode the whole cache once per performer. The pause
    /// coalesces those into one write, the way ``EventStore/persist()``
    /// coalesces a burst of edits.
    private func save() {
        guard persists else { return }
        pendingSave?.cancel()
        let cache = Cache(dates: dates, readAt: readAt)
        let url = Self.cacheURL
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try JSONEncoder().encode(cache).write(to: url, options: .atomic)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure {
                Self.log.error("Followed dates could not be cached: \(failure, privacy: .public)")
            }
        }
    }
}
