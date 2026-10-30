import SwiftData
import SwiftUI

/// What a performer's or a hall's page reads from Eventernote: who or what it
/// is about, and the front of its listing — shown from what this device last
/// read, read again once that is stale, and read by hand from Refresh. The
/// same for ``PerformerView`` and ``VenueView``, which differ only in what
/// they read: how the subject is found (`resolve`) and whose listing it is
/// (`listing`). See ``ListingCache``.
@Observable
final class ListingRead<Subject: Codable & Sendable> {
    /// Finding the page behind a name fails in two ways that read very
    /// differently to the reader, so they are kept apart.
    enum Lookup {
        case looking
        case found(Subject)
        /// The search ran and Eventernote files nothing under exactly this
        /// name.
        case unlisted
        case failed(String)
    }

    private(set) var lookup: Lookup = .looking
    let feed = Feed<Event>()
    /// Whether the listing has been asked for yet. The feed cannot say so
    /// itself — an untouched feed and one that answered with nothing look the
    /// same from outside — and the gap between the two is a frame of empty
    /// sections the reader should never see.
    private(set) var hasReadListing = false
    /// Why the last read did not replace what is on screen, if it did not.
    private(set) var refreshFailure: String?
    /// The read going on now, so a Refresh can wait for it — see
    /// ``refresh(byHand:store:notices:)``. It ends in what its notice would
    /// say, and each caller decides whether to say it.
    private var running: Task<RefreshNotice?, Never>?
    /// When what is on screen was read, so coming back to the app can tell
    /// whether it has gone stale meanwhile.
    private(set) var readAt: Date?

    @ObservationIgnored private let cacheKey: String
    /// The subject from the page's link, the one already found handed in —
    /// nil where the site files nothing under the name.
    @ObservationIgnored private let resolve: @Sendable (Subject?) async throws -> Subject?
    @ObservationIgnored private let listing: @Sendable (Subject, Int) async throws -> EventernotePage<Event>

    init(cacheKey: String,
         resolve: @escaping @Sendable (Subject?) async throws -> Subject?,
         listing: @escaping @Sendable (Subject, Int) async throws -> EventernotePage<Event>) {
        self.cacheKey = cacheKey
        self.resolve = resolve
        self.listing = listing
    }

    var subject: Subject? {
        if case .found(let subject) = lookup { subject } else { nil }
    }

    var isRefreshing: Bool { running != nil }

    /// Shows what this device last read of the page, and reads it again only
    /// when that is stale or there is none.
    func open(store: EventStore, notices: RefreshNotices?) async {
        if let cached = ListingCache.shared.entry(for: cacheKey, as: Subject.self) {
            show(cached, store: store)
            guard !cached.isFresh else { return }
        }
        // First visit or a stale copy: the app's own doing, so only a failure
        // is said.
        await refresh(byHand: false, store: store, notices: notices)
    }

    /// Reads the page again, whatever is held — what Refresh in its menu asks
    /// for, and what opening a stale one does by itself.
    ///
    /// A Refresh chosen while a read is already going waits for that one and
    /// ends with it, rather than returning at once with nothing to say — and
    /// says it as a Refresh would, since the reader asked.
    func refresh(byHand: Bool, store: EventStore, notices: RefreshNotices?) async {
        let task: Task<RefreshNotice?, Never>
        if let running {
            task = running
        } else {
            task = Task { await read(store: store) }
            running = task
        }
        let notice = await task.value
        if running == task { running = nil }
        if let notice { notices?.report(notice, byHand: byHand) }
    }

    /// The page's Try Again, from a failure that took the whole page.
    func retry(store: EventStore, notices: RefreshNotices?) async {
        lookup = .looking
        await refresh(byHand: true, store: store, notices: notices)
    }

    /// A page left open while the reader was away is owed the check it made
    /// as it opened: past the window, it reads again.
    func readAgainIfStale(store: EventStore, notices: RefreshNotices?) async {
        guard let readAt, readAt.timeIntervalSinceNow < -Freshness.window else { return }
        await refresh(byHand: false, store: store, notices: notices)
    }

    /// Keeps the pages the reader scrolled on to as well, so the next visit
    /// opens on them rather than on the front alone.
    func keepPagesRead() {
        ListingCache.shared.extend(cacheKey, as: Subject.self, with: feed)
    }

    /// Reads the page and puts what arrived on screen, answering what its
    /// notice would say — nil for a name the site files nothing under, which
    /// is said on the page itself.
    private func read(store: EventStore) async -> RefreshNotice? {
        let known = subject
        let resolve = resolve
        let read = await ListingCache.read(subject: { try await resolve(known) }, listing: listing)
        switch read {
        case .read(let entry):
            ListingCache.shared.store(entry, for: cacheKey)
            show(entry, store: store)
            refreshFailure = nil
            return .updated
        case .unlisted:
            lookup = .unlisted
            return nil
        case .failed(let reason):
            // What was on screen stays, with the reason under it; only a page
            // with nothing to fall back on gives the whole screen to the
            // failure.
            if hasReadListing { refreshFailure = reason } else { lookup = .failed(reason) }
            return .failed(reason)
        }
    }

    /// Puts a read — from the cache or just now — on screen, pointed at the
    /// listing it came from so scrolling pages on from where it stopped.
    private func show(_ entry: CachedListing<Subject>, store: EventStore) {
        lookup = .found(entry.subject)
        let subject = entry.subject
        let listing = listing
        feed.restore(entry.items, total: entry.total, pagesRead: entry.pagesRead,
                     hasMore: entry.hasMore) { page in try await listing(subject, page) }
        hasReadListing = true
        readAt = entry.readAt
        store.remember(feed.items)
    }
}

/// A performer's or a hall's page, around what each puts on it: the name and
/// what is known of it under the name, then — as the lookup stands — a
/// spinner, `found` (the hall's map and tips, the listing), the site filing
/// nothing under the name, or why it could not be read with a Try Again. In
/// the page's frame: its notices above its bar, the name as its title, the
/// tab bar stood down for the bar the page puts along its foot, an event
/// opened beside it or over it, and the reading itself — opened from what was
/// read last, read again once stale, and the pages scrolled on to kept.
struct ListingPage<Subject: Codable & Sendable, Subtitle: View, Found: View>: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.scenePhase) private var scenePhase

    let subject: ListingSubject
    let listing: ListingRead<Subject>
    @Binding var openEvent: Event?
    /// When the page was last refreshed by hand — see
    /// ``EnvironmentValues/imagesCheckedSince``.
    let imagesCheckedSince: Date?
    @ViewBuilder let subtitle: Subtitle
    @ViewBuilder let found: Found

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ListingPageHeader(name: subject.name) { subtitle }
                switch listing.lookup {
                case .looking:
                    SearchProgress()
                case .found:
                    found
                case .unlisted:
                    unlisted
                        .padding(.top, 24)
                case .failed(let message):
                    SearchFailure(message: message) { await listing.retry(store: store, notices: notices) }
                }
            }
            .padding(.bottom, 32)
        }
        .washBackground()
        // Inside the page, so the notice stands above its bar rather than
        // over it — see ``refreshNotices(aboveBar:showing:)``.
        .refreshNotices(aboveBar: true)
        // An imported name, shown in the language Eventernote published it in.
        .navigationTitle(Text(verbatim: subject.name))
        .navigationBarTitleDisplayMode(.inline)
        // The bar takes the foot of the screen over, as an event's sheet
        // has it: the tab bar stands down while the page is up.
        .toolbar(.hidden, for: .tabBar)
        .eventPane($openEvent)
        .task { await listing.open(store: store, notices: notices) }
        // A page left open while the reader was away is owed the check it
        // made as it opened: past the window, it reads again.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await listing.readAgainIfStale(store: store, notices: notices) }
        }
        .environment(\.imagesCheckedSince, imagesCheckedSince)
        .onChange(of: listing.feed.page) { listing.keepPagesRead() }
    }

    /// The site files nothing under the name the page was opened with.
    private var unlisted: some View {
        ContentUnavailableView {
            switch subject {
            case .performer: Label("Not on Eventernote", systemImage: "person.slash")
            case .venue: Label("Not on Eventernote", systemImage: "mappin.slash")
            }
        } description: {
            switch subject {
            case .performer:
                Text("Eventernote publishes no performer page under this name, so there is nothing to list.")
            case .venue:
                Text("Eventernote publishes no venue page under this name, so there is nothing to list.")
            }
        }
    }
}

/// The name a performer's or a hall's page opens on, and what is known of it
/// under the name.
struct ListingPageHeader<Subtitle: View>: View {
    let name: String
    @ViewBuilder let subtitle: Subtitle

    var body: some View {
        VStack(spacing: 5) {
            // An imported name, shown in the language Eventernote published it in.
            Text(verbatim: name)
                .scalingFont(size: 27, weight: .bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            subtitle
                .scalingFont(size: 13.5)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// The listing under a performer's or a hall's page: two counts the app can
/// stand behind and one the site publishes, the two halves a few rows each
/// with a way into the rest, who is billed there most often, and where it all
/// came from.
///
/// Appearances arrive newest date first — the site orders a performer's and a
/// hall's listing from the furthest published date backwards — so every
/// upcoming date sits at the front of it. That is what lets the page split
/// the listing in two and still count the upcoming half honestly while the
/// past half is still paging in.
struct ListingSections<Subject: Codable & Sendable>: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    /// The library, which "You attended" is counted over rather than over the
    /// listing read so far, so the number is the whole of it however little
    /// of the listing has been paged in.
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]

    let subject: ListingSubject
    let listing: ListingRead<Subject>
    @Binding var openEvent: Event?

    /// How much of each half a section shows before sending the rest to a
    /// screen of its own. Enough to say what is coming and what has just
    /// been, few enough that a performer or a hall with years behind them
    /// cannot bury the cards under the sections.
    private static var sectionLimit: Int { 5 }

    private var feed: Feed<Event> { listing.feed }

    private var upcoming: [Event] {
        ListingHalfView.Half.upcoming.rows(of: feed.items)
    }

    private var past: [Event] {
        ListingHalfView.Half.past.rows(of: feed.items)
    }

    /// True once a past row has been read, or the listing has run out —
    /// either way every upcoming one is in hand.
    private var hasEveryUpcoming: Bool {
        !feed.hasMore || feed.items.contains { !$0.isUpcoming }
    }

    /// Whether Upcoming has anything the section is not showing. The listing
    /// is read until a past row appears, so while that is still running there
    /// may be dates ahead of the ones in hand.
    private var hasMoreUpcoming: Bool {
        upcoming.count > Self.sectionLimit || (!hasEveryUpcoming && !upcoming.isEmpty)
    }

    /// The same for the past half, where `feed.hasMore` settles it: every
    /// page still unread is a past one once the upcoming half is whole.
    private var hasMorePast: Bool {
        past.count > Self.sectionLimit || feed.hasMore
    }

    var body: some View {
        if feed.isLoading || !listing.hasReadListing {
            SearchProgress()
        } else if let failure = feed.failure {
            SearchFailure(message: failure) {
                await listing.refresh(byHand: true, store: store, notices: notices)
            }
        } else if feed.isEmptyResult {
            ContentUnavailableView {
                Label("No Events Listed", systemImage: "calendar")
            } description: {
                switch subject {
                case .performer: Text("Eventernote lists no events for this performer.")
                case .venue: Text("Eventernote lists no events at this venue.")
                }
            }
            .padding(.top, 32)
        } else {
            statistics
            section(half: .upcoming, count: hasEveryUpcoming ? upcoming.count : nil,
                    events: upcoming, hasMore: hasMoreUpcoming)
            // The count is left off while pages are still coming: a heading
            // that said "12" beside a listing the reader can keep scrolling
            // would be counting the reading, not the performer or the hall.
            section(half: .past, count: feed.hasMore ? nil : past.count,
                    events: past, hasMore: hasMorePast)
            FeedFooter(feed: feed) { store.remember(feed.items) }
            if !billedMost.isEmpty { billedMostCard }
            if let refreshFailure = listing.refreshFailure {
                RefreshFailureNote(message: refreshFailure)
                    .padding(.horizontal, 18)
            }
            footnote
        }
    }

    // MARK: - The counts

    private var statistics: some View {
        HStack(spacing: 11) {
            StatTile(tint: .trackInterest,
                     value: hasEveryUpcoming ? upcoming.count.formatted() : "—",
                     label: "Upcoming dates")
            attendedTile
            StatTile(tint: .trackTicket, value: feed.total.formatted(),
                     label: subject.isVenue ? "Listed events" : "Listed appearances")
        }
        .padding(.horizontal, 18)
    }

    /// How many of the library's events the reader went to here — see
    /// ``ListingSubject/includes(_:)`` — opening what they were
    /// (``AttendedHistoryView``) where there are any. Not offering this page
    /// again from there, since it is the page underneath.
    @ViewBuilder
    private var attendedTile: some View {
        let count = store.events(of: kept, where: \.inLibrary).count {
            store.hasAttended($0) && subject.includes($0)
        }
        let tile = StatTile(tint: .trackAttended, value: count.formatted(), label: "You attended")
        if count > 0 {
            NavigationLink(value: AttendedLink(subject: subject, offersPage: false)) {
                tile.overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(14)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the events you went to")
        } else {
            tile
        }
    }

    // MARK: - The halves

    private func section(
        half: ListingHalfView.Half, count: Int?, events: [Event], hasMore: Bool
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            CardHeader(title: half.title(of: subject), count: count) {
                if hasMore { seeAll(half) }
            }
            .padding(.horizontal, 17)
            .padding(.top, 16)
            .padding(.bottom, events.isEmpty ? 0 : 5)

            if events.isEmpty {
                Text(half.emptyNote)
                    .scalingFont(size: 12)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 17)
                    .padding(.top, 8)
                    .padding(.bottom, 17)
            } else {
                ForEach(
                    Array(events.prefix(Self.sectionLimit).enumerated()), id: \.element.id
                ) { index, event in
                    if index > 0 { Divider().opacity(0.45).padding(.leading, 12) }
                    AppearanceRow(event: event, subject: subject) { openEvent = event }
                        .task { await store.pageOn(feed, after: event) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    /// The way into the whole of a half the section only samples.
    ///
    /// The destination is handed this page's feed rather than a query, so it
    /// opens on what is already read and pages on from there — and whatever it
    /// reads is here in the section when the reader comes back.
    private func seeAll(_ half: ListingHalfView.Half) -> some View {
        NavigationLink {
            ListingHalfView(subject: subject, half: half, feed: feed)
        } label: {
            SeeAllLabel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Who is billed there most

    /// The names billed most often in the listing — beside the performer on
    /// their page, on the stage on a hall's — over the rows read so far. A
    /// listing row prints the whole bill, so this needs no extra request; but
    /// it also only knows the pages in hand, which the card says out loud.
    private var billedMost: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in feed.items {
            for performer in event.performers where performer.name != subject.performerName {
                counts[performer.name, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map { (name: $0.key, count: $0.value) }
    }

    private var billedMostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch subject {
            case .performer:
                CardHeader(
                    title: "Often on the same bill",
                    caption: Text("^[Across the \(feed.items.count) appearance](inflect: true) read so far.")
                )
            case .venue:
                CardHeader(
                    title: "Often on this stage",
                    caption: Text("^[Across the \(feed.items.count) event](inflect: true) read so far.")
                )
            }

            VStack(spacing: 3) {
                ForEach(billedMost, id: \.name) { other in
                    NavigationLink(value: PerformerLink.billed(name: other.name)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: other.name)
                                    .scalingFont(size: 14, weight: .semibold)
                                    .lineLimit(1)
                                Group {
                                    switch subject {
                                    case .performer: Text("^[\(other.count) shared bill](inflect: true)")
                                    case .venue: Text("^[\(other.count) date](inflect: true) here")
                                    }
                                }
                                .scalingFont(size: 11.5)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .scalingFont(size: 11, weight: .semibold)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(17)
        .panel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    // MARK: - Provenance

    private var footnote: some View {
        Group {
            switch subject {
            case .performer:
                Footnote(Text("Appearances come from publicly accessible Eventernote pages. Following is kept in your own library — nothing is written back."),
                         updated: listing.readAt)
            case .venue:
                Footnote(Text("Venue details and events come from publicly accessible Eventernote pages. The map is drawn from the published address — nothing is written back."),
                         updated: listing.readAt)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
    }
}

nonisolated extension ListingSubject {
    var isVenue: Bool {
        if case .venue = self { true } else { false }
    }

    /// The performer whose listing this is, left off the names billed beside
    /// them; nil for a hall, where everyone billed counts.
    var performerName: String? {
        if case .performer(let name) = self { name } else { nil }
    }
}
