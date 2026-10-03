import SwiftUI

/// One of the lists Eventernote keeps of its own rather than of anybody's —
/// the tabs over its event search. The third of them, the events of the
/// performers a member follows, is the Following tab; the fourth, the past,
/// is what Search's own Date filter reads.
nonisolated enum SiteListing: Hashable, CaseIterable {
    /// Everything on today's date, on the site's calendar.
    case today
    /// The hundred events most recently added to the site.
    case justAdded
}

extension SiteListing {
    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .justAdded: "Just Added"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .justAdded: "sparkles"
        }
    }

    /// The line under the title, on the Search tab and on the screen alike:
    /// which day today is — the site's, which in the Americas is already
    /// tomorrow by the evening — or how much the newest list holds.
    func detail(on day: Date) -> Text {
        switch self {
        case .today:
            var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
            style.timeZone = Event.publishedZone
            return Text(day.formatted(style))
        case .justAdded:
            return Text("The latest \(EventernoteClient.newestCount) on Eventernote")
        }
    }

    /// What the small print says the list is, after when it was read.
    var footnote: Text {
        switch self {
        case .today:
            Text("Everything Eventernote lists for this date in Japan, earliest start first, from its public pages — nothing is written back.")
        case .justAdded:
            Text("The events most recently added to Eventernote, newest first, from its public pages — some already past, added late. Nothing is written back.")
        }
    }
}

/// One of the site's own lists in full, opened from the Search tab before
/// anything is typed: what is on today, or what was added last.
///
/// Read the way a performer's or a hall's page is read (see
/// ``ListingCache``): shown at once from what this device last read, and read
/// again by itself only once that has gone stale — or, for today's, once the
/// site's calendar has moved on to another day — and always from Refresh in
/// the ⋯ menu. Only the first page is read on the reader's behalf; the rest of
/// today's pages as the reader scrolls to them, and kept with it.
///
/// Each list keeps the half of ``SearchFilter`` the site leaves to it: today's
/// an area, which the site's search answers; the newest whether a date is
/// still ahead, held here over the hundred rows, since that list takes no
/// area and has a past in it.
struct SiteListingView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.scenePhase) private var scenePhase

    let listing: SiteListing
    /// Kept by the Search tab, so it lasts from one visit to the next.
    @Binding var filter: SearchFilter

    /// The site's day the list is of. Moved on as the app comes back to the
    /// foreground on another one.
    @State private var day = Event.siteDay(of: .now)
    @State private var feed = Feed<Event>()
    /// Whether anything — a kept copy or a read — is on screen yet.
    @State private var hasRead = false
    /// Why the first read failed, with nothing on screen to fall back on.
    @State private var failure: String?
    /// Why the last read did not replace what is on screen, if it did not.
    @State private var refreshFailure: String?
    /// The read going on now and the list it is for, so a Refresh can wait for
    /// it — see ``refresh(byHand:)``.
    @State private var running: Task<RefreshNotice, Never>?
    @State private var runningKey: String?
    /// When what is on screen was read, so coming back to the app can tell
    /// whether it has gone stale meanwhile.
    @State private var readAt: Date?
    /// When the list was last refreshed by hand, so the flyers on it are asked
    /// about again with the rows — see ``EnvironmentValues/imagesCheckedSince``.
    @State private var imagesCheckedSince: Date?
    @State private var openEvent: Event?

    /// Which list is on screen: changing any of it shows another.
    private struct Shown: Hashable {
        let key: String
        let day: Date
    }

    /// What the copy on screen is filed under in ``ListingCache``: one per
    /// area for today's, carrying the day it was read for — see ``show(_:)``.
    private var cacheKey: String {
        switch listing {
        case .today: "site/today/\(filter.area?.areaID ?? 0)"
        case .justAdded: "site/new"
        }
    }

    /// What the list reads, a page at a time, for the day and area on screen.
    private var source: Feed<Event>.Source {
        switch listing {
        case .today:
            let day = day
            let areaID = filter.area?.areaID
            return { page in try await EventernoteClient.shared.events(on: day, areaID: areaID, page: page) }
        case .justAdded:
            // One page, and nothing behind it: never asked for a second.
            return { _ in try await EventernoteClient.shared.newestEvents() }
        }
    }

    private var pageURL: URL? {
        switch listing {
        case .today: EventernoteClient.pageURL(forEventsOn: day, areaID: filter.area?.areaID)
        case .justAdded: EventernoteClient.newestEventsURL
        }
    }

    /// The rows the filter leaves, in the site's order. An area was already
    /// applied by the site.
    private var shownEvents: [Event] {
        filter.holdsRows ? feed.items.filter(filter.matches) : feed.items
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        // Inside the room the capsule leaves, so a notice stands above the
        // capsule rather than over it — see ``refreshNotices(aboveBar:showing:)``.
        .refreshNotices(aboveBar: true)
        // Over the tab bar, in the middle, as Following's stands.
        .safeAreaInset(edge: .bottom) { controls }
        .washBackground()
        .navigationTitle(listing.title)
        .navigationSubtitle(listing.detail(on: day))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menu }
        .eventSheet($openEvent)
        .task(id: Shown(key: cacheKey, day: day)) { await open() }
        // A list left open while the reader was away is owed the check it
        // made as it opened — and today's is owed the day it now is.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let today = Event.siteDay(of: .now)
            if listing == .today, today != day {
                day = today
            } else if let readAt, readAt.timeIntervalSinceNow < -Freshness.window {
                Task { await refresh(byHand: false) }
            }
        }
        // Pages the reader scrolls on to are kept too, so the next visit opens
        // on them rather than on the first alone.
        .onChange(of: feed.page) {
            ListingCache.shared.extend(cacheKey, as: Date.self, with: feed)
        }
        .environment(\.imagesCheckedSince, imagesCheckedSince)
    }

    // MARK: - Loading

    /// Shows what this device last read of the list, and reads it again only
    /// when that is stale, of another day, or not there at all.
    private func open() async {
        refreshFailure = nil
        if let cached = ListingCache.shared.entry(for: cacheKey, as: Date.self),
           listing != .today || cached.subject == day {
            show(cached)
            guard !cached.isFresh else { return }
        } else {
            feed.clear()
            hasRead = false
            failure = nil
            readAt = nil
        }
        // A first visit or a stale copy: the app's own doing, so only a
        // failure is said.
        await refresh(byHand: false)
    }

    /// Reads the list again, whatever is held — what Refresh in the menu asks
    /// for, and what opening a stale one does by itself.
    ///
    /// A Refresh chosen while a read of the same list is already going waits
    /// for that one and ends with it, and says it as a Refresh would.
    private func refresh(byHand: Bool) async {
        let key = cacheKey
        let task: Task<RefreshNotice, Never>
        if let running, runningKey == key {
            task = running
        } else {
            task = Task { await read(key) }
            running = task
            runningKey = key
        }
        let notice = await task.value
        if running == task {
            running = nil
            runningKey = nil
        }
        notices?.report(notice, byHand: byHand)
    }

    /// Reads the first page and puts it on screen, if the list on screen is
    /// still the one it was read for. Lands in the cache either way.
    ///
    /// Run as a task of its own (see ``refresh(byHand:)``), so a filter
    /// changed or a screen left mid-read does not cancel it.
    private func read(_ key: String) async -> RefreshNotice {
        let started = Date.now
        let day = day
        let source = source
        do {
            let page = try await source(1)
            let entry = CachedListing(subject: day, items: page.items, total: page.total,
                                      pagesRead: 1, hasMore: page.hasMore, readAt: started)
            ListingCache.shared.store(entry, for: key)
            if key == cacheKey, day == self.day {
                show(entry)
                refreshFailure = nil
            }
            return .updated
        } catch {
            let reason = error.localizedDescription
            if key == cacheKey, day == self.day {
                // What was on screen stays, with the reason under it; only a
                // list with nothing to fall back on gives the whole screen to
                // the failure.
                if hasRead { refreshFailure = reason } else { failure = reason }
            }
            return .failed(reason)
        }
    }

    private func retry() async {
        failure = nil
        await refresh(byHand: true)
    }

    /// Puts a read — kept or just now — on screen, pointed at the listing it
    /// came from so scrolling pages on from where it stopped.
    ///
    /// The subject is the site's day the list was read for: a copy of
    /// today's from yesterday is not shown at all, rather than shown stale.
    private func show(_ entry: CachedListing<Date>) {
        feed.restore(entry.items, total: entry.total, pagesRead: entry.pagesRead,
                     hasMore: entry.hasMore, from: source)
        hasRead = true
        failure = nil
        readAt = entry.readAt
        store.remember(feed.items)
    }

    // MARK: - The list

    @ViewBuilder
    private var content: some View {
        if !hasRead {
            if let failure {
                SearchFailure(message: failure) { await retry() }
            } else {
                SearchProgress()
            }
        } else if shownEvents.isEmpty, filter.isNarrowing {
            nothingMatches
        } else if feed.items.isEmpty {
            ContentUnavailableView {
                Label("No Events", systemImage: listing.symbol)
            } description: {
                Text("Eventernote lists nothing here yet.")
            }
            .padding(.top, 48)
            failureNote
        } else {
            SectionLabel(label: countLabel)

            ForEach(shownEvents) { event in
                SearchResultRow(event: event) { openEvent = event }
                    .task { await store.pageOn(feed, after: event) }
            }

            FeedFooter(feed: feed) { store.remember(feed.items) }
            failureNote
            Footnote(listing.footnote, updated: readAt)
                .padding(.horizontal, 10)
                .padding(.top, 6)
        }
    }

    /// The site's count, or — while rows are held back here — how many of
    /// them are on screen out of it.
    private var countLabel: LocalizedStringKey {
        guard filter.holdsRows else { return "^[\(feed.total) event](inflect: true)" }
        return "\(shownEvents.count) of \(Text("^[\(feed.total) event](inflect: true)"))"
    }

    @ViewBuilder
    private var failureNote: some View {
        if let refreshFailure {
            RefreshFailureNote(message: refreshFailure)
        }
    }

    /// Nothing on the list falls within the filter.
    private var nothingMatches: some View {
        ContentUnavailableView {
            Label("No Matching Events", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Nothing on this list falls within the filter. Widen it to see the rest.")
        } actions: {
            Button("Clear Filter") {
                withAnimation(.snappy) { filter = SearchFilter() }
            }
            .buttonStyle(.glass)
        }
        .padding(.top, 48)
    }

    // MARK: - Controls

    /// The capsule over the tab bar — see ``ListMenu`` — holding the one half
    /// of the filter this list can be narrowed by, and no order: today's runs
    /// by the start, and the newest by when each was added.
    private var controls: some View {
        ListMenu(describes: "Filter", value: filter.summary) {
            Section("Filter") {
                switch listing {
                case .today: SearchAreaMenu(area: $filter.area)
                case .justAdded: SearchDateMenu(when: $filter.when)
                }
            }
        } face: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(filter.isNarrowing ? Color.brandTint : .secondary)
                filter.summary
                    .foregroundStyle(filter.isNarrowing ? Color.brandTint : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The page this list was read from, and reading it again — the group a
    /// performer's or a hall's ⋯ menu ends on. In the navigation bar, since
    /// the foot of the screen is the capsule's and the tab bar's.
    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let pageURL {
                    Link(destination: pageURL) {
                        Label("Open in Eventernote", systemImage: "safari")
                    }
                }
                RefreshMenuItem(isRefreshing: running != nil) {
                    imagesCheckedSince = .now
                    Task { await refresh(byHand: true) }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuOrder(.fixed)
        }
    }
}

#Preview {
    @Previewable @State var filter = SearchFilter()
    NavigationStack {
        SiteListingView(listing: .today, filter: $filter)
    }
    .library(EventStore.preview)
}
