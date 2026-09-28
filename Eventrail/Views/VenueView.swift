import SwiftData
import SwiftUI

/// How a venue page was reached, and so how much the app already knows about
/// the hall it is opening.
///
/// The two entry points publish different amounts, exactly as they do for a
/// performer: an event whose own page has been imported carries the site's
/// place id, while everything read from a listing row has the hall's name and
/// nothing else — no address, no id.
nonisolated enum VenueLink: Hashable {
    /// From an event that carries Eventernote's place id, which addresses the
    /// hall's page directly.
    case place(PlaceListing)
    /// From a listing row. The page behind the name has to be found first.
    case named(String)

    var name: String {
        switch self {
        case .place(let listing): listing.name
        case .named(let name): name
        }
    }
}

/// One hall: what Eventernote publishes about the place, everything held there,
/// and how much of it the reader has been to.
///
/// The same shape as ``PerformerView``, because it is the same listing read the
/// same way: `/places/{id}/events` runs from the furthest published date
/// backwards, so every date still to come sits at the front of it and the page
/// can split the listing in two and still count the upcoming half honestly
/// while the past half is paging in.
///
/// The one thing a performer's page has not got is the map. Eventernote
/// publishes no photograph of a hall either, but it does publish the address —
/// and a map drawn from that says where the place is rather than standing in
/// for a picture of it.
struct VenueView: View {
    @Environment(EventStore.self) private var store
    /// The library, which "You attended" is counted over — matched on the name
    /// the site printed, the one thing every row of a listing publishes about
    /// a hall, since an event imported from a search row has no place id.
    @Query(LibraryMembership.library) private var kept: [LibraryMembership]
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    let link: VenueLink

    @State private var lookup: Lookup = .looking
    @State private var feed = Feed<Event>()
    /// Whether the listing has been asked for yet. The feed cannot say so
    /// itself — an untouched feed and one that answered with nothing look the
    /// same from outside — and the gap between the two is a frame of empty
    /// sections the reader should never see.
    @State private var hasReadListing = false
    @State private var openEvent: Event?
    /// Where Maps says the hall is. Nil until the lookup comes back, and for a
    /// hall Maps has never heard of.
    @State private var place: VenuePlaces.Placing?
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

    /// Finding the page behind a hall's name fails in two ways that read very
    /// differently to the reader, so they are kept apart.
    private enum Lookup {
        case looking
        case found(VenueProfile)
        /// The search ran and Eventernote files no hall under exactly this name.
        case unlisted
        case failed(String)
    }

    private var profile: VenueProfile? {
        if case .found(let profile) = lookup { return profile } else { return nil }
    }

    /// Whose listing this is, for the screens and headings shared with a
    /// performer's page.
    private var subject: ListingSubject { .venue(link.name) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                switch lookup {
                case .looking:
                    SearchProgress()
                case .found:
                    placeCard
                    tipsCard
                    listing
                case .unlisted:
                    ContentUnavailableView {
                        Label("Not on Eventernote", systemImage: "mappin.slash")
                    } description: {
                        Text("Eventernote publishes no venue page under this name, so there is nothing to list.")
                    }
                    .padding(.top, 24)
                case .failed(let message):
                    SearchFailure(message: message) { await retry() }
                }
            }
            .padding(.bottom, 32)
        }
        .washBackground()
        // An imported name, shown in the language Eventernote published it in.
        .navigationTitle(Text(verbatim: link.name))
        .navigationBarTitleDisplayMode(.inline)
        .eventSheet($openEvent)
        .task { await open() }
        // The page's own, so a hall reached from the Following tab does not
        // answer a pull by re-reading every followed listing — the tab's
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
            ListingCache.shared.extend(link.cacheKey, as: VenueProfile.self, with: feed)
        }
        // Asked once the hall's own page has come back, because the address on
        // it is what places a hall — and asked again if either half of the
        // question ever changes.
        .task(id: mapKey) { await placeOnMap() }
    }

    // MARK: - Loading

    /// Shows what this device last read of the page, and reads it again only
    /// when that is stale or there is none — see ``ListingCache``.
    private func open() async {
        if let cached = ListingCache.shared.entry(for: link.cacheKey, as: VenueProfile.self) {
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
            subject: { try await Self.resolve(link, known: known) },
            listing: { venue, page in
                try await EventernoteClient.shared.events(atVenue: venue.id, page: page)
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
    private func show(_ entry: CachedListing<VenueProfile>) {
        lookup = .found(entry.subject)
        let id = entry.subject.id
        feed.restore(entry.items, total: entry.total, pagesRead: entry.pagesRead,
                     hasMore: entry.hasMore) { page in
            try await EventernoteClient.shared.events(atVenue: id, page: page)
        }
        hasReadListing = true
        readAt = entry.readAt
        store.remember(feed.items)
    }

    /// Reads the hall's own page: nil where the site files no hall under the
    /// name the page was opened with.
    ///
    /// Read again on every refresh rather than kept from the first, which is
    /// where this differs from a performer: the address, the capacity and the
    /// walk from the station are all on the hall's page, and members edit
    /// them. Only the search that turned a name into an id is not repeated —
    /// a hall a page has already found stays found.
    nonisolated private static func resolve(_ link: VenueLink, known: VenueProfile?) async throws -> VenueProfile? {
        let id: Int
        if let known {
            id = known.id
        } else {
            switch link {
            case .place(let listing):
                id = listing.id
            case .named(let name):
                guard let found = try await EventernoteClient.shared.venue(named: name) else { return nil }
                id = found.id
            }
        }
        return try await EventernoteClient.shared.venue(id: id)
    }

    /// What a lookup is actually asking about, and nil while there is nothing
    /// to ask — the same pair ``VenuePlaces`` keys its kept answers by, so a
    /// hall the reader has already opened an event at is answered at once.
    private var mapKey: String? {
        profile.map { "\($0.name)\n\($0.address ?? "")" }
    }

    private func placeOnMap() async {
        guard let profile else { return }
        place = await VenuePlaces.shared.mapItem(forVenue: profile.name, address: profile.address)
    }

    // MARK: - Where it is

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
            if let profile { actions(for: profile) }
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
            Text("Looking this venue up on Eventernote…")
        case .unlisted, .failed:
            // What went wrong is said under the header, where it can be acted on.
            EmptyView()
        case .found(let profile):
            // An imported address, printed as the site printed it.
            if let address = profile.address {
                Text(verbatim: address)
            }
        }
    }

    private func actions(for profile: VenueProfile) -> some View {
        HStack(spacing: 9) {
            Button {
                VenueDirections.open(profile.name, at: place, directions: true, with: openURL)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Directions")
                }
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Color.brandTint)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .glassCapsule(interactive: true)

            ShareLink(item: profile.pageURL) {
                Text("Share")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.brandTint)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .glassCapsule(interactive: true)
        }
        .padding(.top, 3)
    }

    // MARK: - What the hall publishes about itself

    @ViewBuilder
    private var placeCard: some View {
        if let profile {
            VStack(spacing: 0) {
                VenueMap(venue: profile.name, place: place) {
                    VenueDirections.open(profile.name, at: place, directions: false, with: openURL)
                }
                // Only the map is clipped, and only where the card's own
                // corners are. Clipping the whole card — which is what it used
                // to do — clips the glass with it, and a clipped glass effect
                // stops sampling what is behind it and flattens to a plain
                // light fill.
                .clipShape(.rect(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                 bottomTrailingRadius: 0, topTrailingRadius: 28,
                                 style: .continuous))

                VStack(spacing: 0) {
                    if let address = profile.address {
                        fact(icon: "mappin.and.ellipse", label: "Address", value: address)
                    }
                    if let capacity = profile.capacity {
                        fact(icon: "person.2.fill", label: "Capacity", value: capacity)
                    }
                    if let phone = profile.phone {
                        // Dialled rather than read: a hall's number is only
                        // ever wanted on the day, in a hurry.
                        fact(icon: "phone.fill", label: "Phone", value: phone,
                             destination: URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })"))
                    }
                    if let website = profile.website {
                        fact(icon: "safari", label: "Official site", value: website.host() ?? website.absoluteString,
                             destination: website)
                    }
                    if let chart = profile.seatingChart {
                        fact(icon: "chair.lounge.fill", label: "Seating chart",
                             value: String(localized: "Published by the venue"), destination: chart)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 6)
            }
            .glassPanel(cornerRadius: 28)
            .padding(.horizontal, 18)
        }
    }

    /// One published fact about the hall, and where tapping it goes when the
    /// fact is somewhere rather than something.
    @ViewBuilder
    private func fact(
        icon: String, label: LocalizedStringKey, value: String, destination: URL? = nil
    ) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brandTint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                // Imported text, printed as Eventernote printed it.
                Text(verbatim: value)
                    .font(.system(size: 13.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if destination != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(.rect)

        if let destination {
            Link(destination: destination) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// 会場TIPS: the exits, the walking times and what to know on the day,
    /// written by the site's own members rather than by the hall.
    @ViewBuilder
    private var tipsCard: some View {
        if let tips = profile?.tips {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Getting there")
                Text(verbatim: tips)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(17)
            .glassPanel(cornerRadius: 28)
            .padding(.horizontal, 18)
        }
    }

    // MARK: - What is held here

    /// How much of each half a section shows before sending the rest to a
    /// screen of its own — the same few ``PerformerView`` shows, and for the
    /// same reason: a hall with twenty years of bookings behind it would
    /// otherwise bury every card under the sections.
    private static let sectionLimit = 5

    private var upcoming: [Event] {
        ListingHalfView.Half.upcoming.rows(of: feed.items)
    }

    private var past: [Event] {
        ListingHalfView.Half.past.rows(of: feed.items)
    }

    /// True once a past event has been read, or the listing has run out —
    /// either way every upcoming one is in hand.
    private var hasEveryUpcoming: Bool {
        !feed.hasMore || feed.items.contains { !$0.isUpcoming }
    }

    private var hasMoreUpcoming: Bool {
        upcoming.count > Self.sectionLimit || (!hasEveryUpcoming && !upcoming.isEmpty)
    }

    private var hasMorePast: Bool {
        past.count > Self.sectionLimit || feed.hasMore
    }

    @ViewBuilder
    private var listing: some View {
        if feed.isLoading || !hasReadListing {
            SearchProgress()
        } else if let failure = feed.failure {
            SearchFailure(message: failure) { await refresh(byHand: true) }
        } else if feed.isEmptyResult {
            ContentUnavailableView {
                Label("No Events Listed", systemImage: "calendar")
            } description: {
                Text("Eventernote lists no events at this venue.")
            }
            .padding(.top, 32)
        } else {
            statistics
            section(half: .upcoming, count: hasEveryUpcoming ? upcoming.count : nil,
                    events: upcoming, hasMore: hasMoreUpcoming)
            // The count is left off while pages are still coming: a heading
            // that said "12" beside a listing the reader can keep scrolling
            // would be counting the reading, not the hall.
            section(half: .past, count: feed.hasMore ? nil : past.count,
                    events: past, hasMore: hasMorePast)
            FeedFooter(feed: feed) { store.remember(feed.items) }
            if !regulars.isEmpty { regularsCard }
            if let refreshFailure {
                RefreshFailureNote(message: refreshFailure)
                    .padding(.horizontal, 18)
            }
            openInEventernote
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
                     value: store.events(of: kept).attended.count { $0.venue == link.name }.formatted(),
                     label: "You attended")
            StatTile(tint: .trackTicket, value: feed.total.formatted(),
                     label: "Listed events")
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

    /// The way into the whole of a half the section only samples. The feed is
    /// handed over rather than a query, so the screen opens on what is already
    /// read — see ``ListingHalfView``.
    private func seeAll(_ half: ListingHalfView.Half) -> some View {
        NavigationLink {
            ListingHalfView(subject: subject, half: half, feed: feed)
        } label: {
            SeeAllLabel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Who plays here

    /// The names billed most often at this hall, over the events read so far.
    ///
    /// A listing row prints the whole bill, so this needs no extra request —
    /// but it also only knows the pages in hand, which the card says out loud.
    /// The same card ``PerformerView`` carries for the people a performer
    /// shares a bill with, asked of a place instead.
    private var regulars: [(name: String, appearances: Int)] {
        var counts: [String: Int] = [:]
        for event in feed.items {
            for performer in event.performers {
                counts[performer.name, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3)
            .map { (name: $0.key, appearances: $0.value) }
    }

    private var regularsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: "Often on this stage",
                caption: Text("^[Across the \(feed.items.count) event](inflect: true) read so far.")
            )

            VStack(spacing: 3) {
                ForEach(regulars, id: \.name) { performer in
                    NavigationLink(value: PerformerLink.billed(name: performer.name)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: performer.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                                Text("^[\(performer.appearances) date](inflect: true) here")
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

    @ViewBuilder
    private var openInEventernote: some View {
        if let profile {
            ExternalLinkPanel(title: "Open venue on Eventernote", destination: profile.pageURL)
                .padding(.horizontal, 18)
        }
    }

    private var footnote: some View {
        Footnote(Text("Venue details and events come from publicly accessible Eventernote pages. The map is drawn from the published address — nothing is written back."))
            .padding(.horizontal, 26)
            .padding(.top, 2)
    }
}

#Preview {
    NavigationStack {
        VenueView(link: .place(PlaceListing(id: 3, name: "日本武道館")))
    }
    .library(EventStore.preview)
}
