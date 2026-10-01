import SwiftData
import SwiftUI

/// How a performer page was reached, and so how much the app already knows
/// about who it is opening.
///
/// The two entry points publish different amounts: the Performers scope of
/// Search hands over the whole profile, while an event's billing prints names
/// and nothing else.
nonisolated enum PerformerLink: Hashable {
    /// From performer search, which carries the actor id and the already-escaped
    /// slug the site addresses their pages by.
    case profile(PerformerProfile)
    /// From an event's billing, or from another performer's same-bill list.
    /// The profile behind the name has to be found first.
    case billed(name: String)

    var name: String {
        switch self {
        case .profile(let profile): profile.name
        case .billed(let name): name
        }
    }
}

/// One performer: who Eventernote says they are, everything they are billed on,
/// and how much of it the reader has been to.
///
/// Appearances arrive newest date first — the site orders its listing from the
/// furthest published date backwards — so every upcoming date sits at the front
/// of it. That is what lets the page split the listing in two and still count
/// the upcoming half honestly while the past half is still paging in.
///
/// There is deliberately no picture at the top. Eventernote publishes no
/// portrait of a performer, and the flyer for what they are billed on is the
/// artwork for an event rather than a likeness of them — so the page opens on
/// the name instead of dressing one up as the other.
struct PerformerView: View {
    @Environment(EventStore.self) private var store
    /// The library, which "You attended" is counted over rather than over the
    /// appearances this page has read so far, so the number is the whole of
    /// it however little of the listing has been paged in.
    @Query(LibraryEntry.library) private var kept: [LibraryEntry]
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.scenePhase) private var scenePhase

    let link: PerformerLink

    @State private var lookup: Lookup = .looking
    @State private var feed = Feed<Event>()
    /// Whether the listing has been asked for yet. The feed cannot say so
    /// itself — an untouched feed and one that answered with nothing look the
    /// same from outside — and the gap between the two is a frame of empty
    /// sections the reader should never see.
    @State private var hasReadListing = false
    @State private var openEvent: Event?
    /// Why the last read did not replace what is on screen, if it did not.
    @State private var refreshFailure: String?
    /// The read going on now, so a pull can wait for it — see
    /// ``refresh(byHand:)``. It ends in what its notice would say, and each
    /// caller decides whether to say it.
    @State private var running: Task<RefreshNotice?, Never>?
    /// When what is on screen was read, so coming back to the app can tell
    /// whether it has gone stale meanwhile.
    @State private var readAt: Date?
    /// When the page was last pulled down, so the flyers on it are asked about
    /// again with the rows — see ``EnvironmentValues/imagesCheckedSince``.
    @State private var imagesCheckedSince: Date?

    /// Finding the page behind a billed name fails in two ways that read very
    /// differently to the reader, so they are kept apart.
    private enum Lookup {
        case looking
        case found(PerformerProfile)
        /// The search ran and Eventernote lists nobody under exactly this name.
        case unlisted
        case failed(String)
    }

    private var profile: PerformerProfile? {
        if case .found(let profile) = lookup { return profile } else { return nil }
    }

    /// Whose listing this is, for the screens and headings that are shared with
    /// a hall's page.
    private var subject: ListingSubject { .performer(link.name) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                switch lookup {
                case .looking:
                    SearchProgress()
                case .found:
                    appearances
                case .unlisted:
                    ContentUnavailableView {
                        Label("Not on Eventernote", systemImage: "person.slash")
                    } description: {
                        Text("Eventernote publishes no performer page under this name, so there is nothing to list.")
                    }
                    .padding(.top, 24)
                case .failed(let message):
                    SearchFailure(message: message) { await retry() }
                }
            }
            .padding(.bottom, 32)
        }
        .washBackground()
        // Inside the page, so the notice stands above its bar rather than
        // over it — see ``refreshNotices(aboveBar:showing:)``.
        .refreshNotices(aboveBar: true)
        // An imported name, shown in the language Eventernote published it in.
        .navigationTitle(Text(verbatim: link.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { actionBar }
        // The bar takes the foot of the screen over, as an event's sheet
        // has it: the tab bar stands down while the page is up.
        .toolbar(.hidden, for: .tabBar)
        .eventSheet($openEvent)
        .task { await open() }
        // The page's own, so a performer reached from the Following tab does
        // not answer a pull by re-reading every followed listing — the tab's
        // `.refreshable` is carried down the stack otherwise.
        .refreshable {
            imagesCheckedSince = .now
            await refresh(byHand: true)
        }
        // A page left open while the reader was away is owed the check it
        // made as it opened: past the window, it reads again.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let readAt,
                  readAt.timeIntervalSinceNow < -Freshness.window else { return }
            Task { await refresh(byHand: false) }
        }
        .environment(\.imagesCheckedSince, imagesCheckedSince)
        // Pages the reader scrolls on to are kept too, so the next visit opens
        // on them rather than on the front alone.
        .onChange(of: feed.page) {
            ListingCache.shared.extend(link.cacheKey, as: PerformerProfile.self, with: feed)
        }
    }

    // MARK: - Loading

    /// Shows what this device last read of the page, and reads it again only
    /// when that is stale or there is none — see ``ListingCache``.
    private func open() async {
        if let cached = ListingCache.shared.entry(for: link.cacheKey, as: PerformerProfile.self) {
            show(cached)
            guard !cached.isFresh else { return }
        }
        // First visit or a stale copy: the app's own doing, so only a failure
        // is said.
        await refresh(byHand: false)
    }

    /// Reads the page again, whatever is held — what pulling it down asks for,
    /// and what opening a stale one does by itself.
    ///
    /// A pull that lands while a read is already going waits for that one and
    /// ends with it, rather than returning at once with nothing to say — and
    /// says it as a pull would, since the reader asked.
    private func refresh(byHand: Bool) async {
        let task: Task<RefreshNotice?, Never>
        if let running {
            task = running
        } else {
            task = Task { await read() }
            running = task
        }
        let notice = await task.value
        if running == task { running = nil }
        if let notice { notices?.report(notice, byHand: byHand) }
    }

    /// Reads the page and puts what arrived on screen, answering what its
    /// notice would say — nil for a name the site files nothing under, which
    /// is said on the page itself.
    private func read() async -> RefreshNotice? {
        let known = profile
        let link = link
        let read = await ListingCache.read(
            subject: {
                if let known { return known }
                return try await Self.resolve(link)
            },
            listing: { profile, page in
                try await EventernoteClient.shared.events(forPerformer: profile, page: page)
            })
        switch read {
        case .read(let entry):
            ListingCache.shared.store(entry, for: link.cacheKey)
            show(entry)
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

    private func retry() async {
        lookup = .looking
        await refresh(byHand: true)
    }

    /// Puts a read — from the cache or just now — on screen, pointed at the
    /// listing it came from so scrolling pages on from where it stopped.
    private func show(_ entry: CachedListing<PerformerProfile>) {
        lookup = .found(entry.subject)
        let profile = entry.subject
        feed.restore(entry.items, total: entry.total, pagesRead: entry.pagesRead,
                     hasMore: entry.hasMore) { page in
            try await EventernoteClient.shared.events(forPerformer: profile, page: page)
        }
        hasReadListing = true
        readAt = entry.readAt
        store.remember(feed.items)
    }

    /// Turns whatever the page was opened with into a profile: nil where the
    /// site lists nobody under exactly the billed name.
    nonisolated private static func resolve(_ link: PerformerLink) async throws -> PerformerProfile? {
        switch link {
        case .profile(let profile): profile
        case .billed(let name): try await EventernoteClient.shared.performer(named: name)
        }
    }

    // MARK: - Who they are

    private var header: some View {
        VStack(spacing: 11) {
            VStack(spacing: 5) {
                Text(verbatim: link.name)
                    .font(.system(size: 27, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                subtitle
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch lookup {
        case .looking:
            Text("Looking this performer up on Eventernote…")
        case .unlisted, .failed:
            // What went wrong is said under the header, where it can be acted on.
            EmptyView()
        case .found(let profile):
            HStack(spacing: 7) {
                if let reading = profile.reading {
                    Text(verbatim: reading)
                }
                if profile.reading != nil, profile.fanCount != nil {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 3, height: 3)
                }
                if let fans = profile.fanCount {
                    // The site's count of the people who favourited them, which
                    // is not a count of their events.
                    Text("^[\(fans) fan](inflect: true) on Eventernote")
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Actions

    /// What the reader can do with the performer, in a bar along the bottom
    /// of the page as an event's sheet has one: follow them, share the page,
    /// and open it on Eventernote. One capsule at the leading edge, with the
    /// space beside it left empty for the page to show through.
    ///
    /// Only once the page behind the name is found: a name the site files
    /// nobody under has nothing to follow, share or open.
    @ToolbarContentBuilder
    private var actionBar: some ToolbarContent {
        if let profile {
            let isFollowing = store.isFollowing(profile)
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation(.snappy) { store.toggleFollow(profile) }
                } label: {
                    Label(isFollowing ? "Unfollow" : "Follow",
                          systemImage: isFollowing ? "checkmark" : "plus")
                        .contentTransition(.symbolEffect(.replace))
                }
                .tint(isFollowing ? .trackAttended : .brandTint)

                ShareLink(item: profile.pageURL)
                    .tint(.brandTint)

                Link(destination: profile.pageURL) {
                    Label("Open in Eventernote", systemImage: "safari")
                }
                .tint(.brandTint)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
    }

    // MARK: - What they are billed on

    /// How much of each half a section shows before sending the rest to a
    /// screen of its own. Enough to say what the performer has coming and what
    /// they have just done, few enough that a performer with years behind them
    /// cannot bury the cards under the sections.
    private static let sectionLimit = 5

    private var upcoming: [Event] {
        ListingHalfView.Half.upcoming.rows(of: feed.items)
    }

    private var past: [Event] {
        ListingHalfView.Half.past.rows(of: feed.items)
    }

    /// True once a past appearance has been read, or the listing has run out —
    /// either way every upcoming one is in hand.
    private var hasEveryUpcoming: Bool {
        !feed.hasMore || feed.items.contains { !$0.isUpcoming }
    }

    /// Whether Upcoming has anything the section is not showing. The listing is
    /// read until a past row appears, so while that is still running there may
    /// be dates ahead of the ones in hand.
    private var hasMoreUpcoming: Bool {
        upcoming.count > Self.sectionLimit || (!hasEveryUpcoming && !upcoming.isEmpty)
    }

    /// The same for Past appearances, where `feed.hasMore` settles it: every
    /// page still unread is a past one once the upcoming half is whole.
    private var hasMorePast: Bool {
        past.count > Self.sectionLimit || feed.hasMore
    }

    @ViewBuilder
    private var appearances: some View {
        if feed.isLoading || !hasReadListing {
            SearchProgress()
        } else if let failure = feed.failure {
            SearchFailure(message: failure) { await refresh(byHand: true) }
        } else if feed.isEmptyResult {
            ContentUnavailableView {
                Label("No Events Listed", systemImage: "calendar")
            } description: {
                Text("Eventernote lists no events for this performer.")
            }
            .padding(.top, 32)
        } else {
            statistics
            section(half: .upcoming, count: hasEveryUpcoming ? upcoming.count : nil,
                    events: upcoming, hasMore: hasMoreUpcoming)
            // The count is left off while pages are still coming: a heading
            // that said "12" beside a listing the reader can keep scrolling
            // would be counting the reading, not the performer.
            section(half: .past, count: feed.hasMore ? nil : past.count,
                    events: past, hasMore: hasMorePast)
            FeedFooter(feed: feed) { store.remember(feed.items) }
            if !sameBill.isEmpty { sameBillCard }
            if let refreshFailure {
                RefreshFailureNote(message: refreshFailure)
                    .padding(.horizontal, 18)
            }
            footnote
        }
    }

    /// Two counts the app can stand behind and one the site publishes itself.
    private var statistics: some View {
        HStack(spacing: 11) {
            StatTile(tint: .trackInterest,
                     value: hasEveryUpcoming ? upcoming.count.formatted() : "—",
                     label: "Upcoming dates")
            StatTile(tint: .trackAttended,
                     value: store.events(of: kept, where: \.inLibrary).attended.count { event in
                         event.performers.contains { $0.name == link.name }
                     }.formatted(),
                     label: "You attended")
            StatTile(tint: .trackTicket, value: feed.total.formatted(),
                     label: "Listed appearances")
        }
        .padding(.horizontal, 18)
    }

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
                    .font(.system(size: 12))
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
        .glassPanel(cornerRadius: 28)
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

    // MARK: - Who they share a bill with

    /// The names billed most often alongside this performer, over the
    /// appearances read so far. A listing row prints the whole bill, so this
    /// needs no extra request — but it also only knows the pages in hand,
    /// which the card says out loud.
    private var sameBill: [(name: String, shared: Int)] {
        var counts: [String: Int] = [:]
        for event in feed.items {
            for performer in event.performers where performer.name != link.name {
                counts[performer.name, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map { (name: $0.key, shared: $0.value) }
    }

    private var sameBillCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: "Often on the same bill",
                caption: Text("^[Across the \(feed.items.count) appearance](inflect: true) read so far.")
            )

            VStack(spacing: 3) {
                ForEach(sameBill, id: \.name) { other in
                    NavigationLink(value: PerformerLink.billed(name: other.name)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: other.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                Text("^[\(other.shared) shared bill](inflect: true)")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
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
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    // MARK: - Provenance

    private var footnote: some View {
        Footnote(Text("Appearances come from publicly accessible Eventernote pages. Following is kept in your own library — nothing is written back."))
            .padding(.horizontal, 26)
            .padding(.top, 2)
    }
}

#Preview {
    NavigationStack {
        PerformerView(
            link: .profile(
                PerformerProfile(id: 2890, name: "水瀬いのり", reading: "みなせいのり",
                                 fanCount: 5514, slug: "%E6%B0%B4%E7%80%AC%E3%81%84%E3%81%AE%E3%82%8A")
            )
        )
    }
    .library(EventStore.preview)
}
