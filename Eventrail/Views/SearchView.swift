import SwiftData
import SwiftUI

/// Searches publicly accessible Eventernote pages. Nothing tagged here is
/// written back to Eventernote.
///
/// Event results can be narrowed — ahead or past, an area — and run either way
/// round by date, from the menu in the capsule over the search field; see
/// ``SearchFilter`` for which of that the site answers and which is held here.
struct SearchView: View {
    @Environment(EventStore.self) private var store
    @Query private var settingsRows: [LibrarySettings]

    @State private var query = ""
    @State private var scope: SearchScope = .events
    @State private var events = Feed<Event>()
    @State private var performers = Feed<PerformerProfile>()
    @State private var openEvent: Event?
    /// What event results are narrowed to. Kept across searches, as a search
    /// form keeps its fields, until the reader clears it.
    @State private var filter = SearchFilter()
    /// Which way round the event results run. Kept across searches with the
    /// filter.
    @State private var order = SearchOrder.newestFirst
    /// Pages read in a row without one more row surviving the filter — see
    /// ``readOn()``.
    @State private var fruitlessPages = 0
    /// Whether the search is still finding the first page worth reading — see
    /// ``firstPage(of:pages:reading:filter:)``.
    @State private var isSkipping = false

    /// Everything a search is made of: any of it changing starts a new one.
    /// The filter as a whole, not only what the site is asked: what is held
    /// here decides which page the reading starts on.
    private struct Request: Hashable {
        let term: String
        let scope: SearchScope
        let filter: SearchFilter
        let order: SearchOrder
    }

    /// How many pages are read for a filter that turns up nothing new in them
    /// before the reading waits on the reader — see ``readOn()``.
    private static let fruitlessLimit = 5

    private var term: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if term.isEmpty {
                    startingPoints
                } else {
                    results
                }
            }
            // Over the search field, in the middle: the tab's own content
            // stops short of the field, so the capsule rests just above it,
            // and the rows scroll clear of it rather than under it.
            .safeAreaInset(edge: .bottom) {
                if scope == .events, !term.isEmpty {
                    controls
                }
            }
            .washBackground()
            .navigationTitle("Search")
            .searchable(text: $query, prompt: Text("Search Eventernote events"))
            .searchScopes($scope) {
                ForEach(SearchScope.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .onSubmit(of: .search) { store.remember(search: term) }
            .performerDestination()
            .eventSheet($openEvent)
            .task(id: Request(term: term, scope: scope, filter: filter, order: order)) { await search() }
        }
    }

    /// Runs the search the field currently describes.
    ///
    /// `task(id:)` cancels this when the reader types again, so the pause at the
    /// top is what keeps a request from going out per keystroke.
    private func search() async {
        let term = term
        let filter = filter
        let order = order
        fruitlessPages = 0
        isSkipping = false
        guard !term.isEmpty else {
            events.clear()
            performers.clear()
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        switch scope {
        case .events:
            let areaID = filter.area?.areaID
            let source: Feed<Event>.Source = { page in
                try await EventernoteClient.shared.searchEvents(keyword: term, areaID: areaID,
                                                                order: order, page: page)
            }
            await events.load(from: source)
            // Where the rows the filter wants begin pages in, the pages in
            // front are skipped rather than read. A page that will not come is
            // no reason to give up the first one: the reading goes on from it,
            // a page at a time, as it would have anyway.
            if let last = events.items.last, events.hasMore,
               filter.comesBeforeMatches(last, reading: order) {
                isSkipping = true
                defer { isSkipping = false }
                let pages = (events.total + EventernoteClient.pageSize - 1) / EventernoteClient.pageSize
                if let first = try? await Self.firstPage(of: source, pages: pages, reading: order, filter: filter),
                   first > 1, !Task.isCancelled {
                    await events.load(startingAt: first, from: source)
                }
            }
            store.remember(events.items)
        case .performers:
            await performers.load { page in
                try await EventernoteClient.shared.searchPerformers(keyword: term, page: page)
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        switch scope {
        case .events: eventResults
        case .performers: performerResults
        }
    }

    @ViewBuilder
    private var eventResults: some View {
        if events.isLoading || isSkipping {
            SearchProgress()
        } else if let failure = events.failure {
            SearchFailure(message: failure) { await search() }
        } else if events.isEmptyResult, !filter.isNarrowing {
            ContentUnavailableView.search(text: term)
                .padding(.top, 48)
        } else if events.page > 0, shownEvents.isEmpty, hasEveryMatch {
            nothingMatches
        } else if shownEvents.isEmpty, !isWaitingOnReader, events.moreFailure == nil {
            // Reading on towards the first row the filter wants. With nothing
            // on screen there is no row to read on from, so it is done here.
            SearchProgress()
                .task(id: events.items.count) { await readOn() }
        } else {
            LazyVStack(alignment: .leading, spacing: 9) {
                SectionLabel(label: resultsLabel)

                ForEach(shownEvents) { event in
                    SearchResultRow(event: event) { openEvent = event }
                        // Held back here, the rows on screen are not the rows
                        // read, so the last few of them read on — and again
                        // with each page, for as long as they are in view and
                        // a page adds nothing to them.
                        .task(id: events.items.count) {
                            if filter.holdsRows {
                                if shownEvents.suffix(4).contains(where: { $0.id == event.id }) { await readOn() }
                            } else {
                                await store.pageOn(events, after: event)
                            }
                        }
                }

                FeedFooter(feed: events) { store.remember(events.items) }
                if isWaitingOnReader { keepLooking }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Narrowing

    /// The rows the filter leaves, in the site's order. Only what is held here
    /// is applied: an area was already applied by the site.
    private var shownEvents: [Event] {
        filter.holdsRows ? events.items.filter(filter.matches) : events.items
    }

    /// Whether every row that could survive the filter has been read: the site
    /// has no page left, or the last row read is past anything the filter could
    /// want — see ``SearchFilter/comesAfterMatches(_:reading:)``.
    private var hasEveryMatch: Bool {
        guard events.hasMore, let last = events.items.last else { return true }
        return filter.comesAfterMatches(last, reading: order)
    }

    /// Whether the reading has stopped on its own, short of the end, for the
    /// reader to say whether to go on.
    private var isWaitingOnReader: Bool {
        filter.holdsRows && !hasEveryMatch && fruitlessPages >= Self.fruitlessLimit
            && events.moreFailure == nil && !events.isLoadingMore
    }

    /// The site's count, or — while rows are held back here — how many of them
    /// are on screen out of it, and whether more may yet turn up.
    private var resultsLabel: LocalizedStringKey {
        let results = Text("^[\(events.total) result](inflect: true)")
        guard filter.holdsRows else {
            return "^[\(events.total) result](inflect: true) on Eventernote"
        }
        return hasEveryMatch
            ? "\(shownEvents.count) of \(results)"
            : "\(shownEvents.count) of \(results) so far"
    }

    /// Reads the next page for a filter held here.
    ///
    /// The site cannot be asked for "upcoming", so the rows the filter wants
    /// are read for. The pages wholly in front of them are skipped
    /// as the search starts — see ``firstPage(of:pages:reading:filter:)`` — so
    /// from there on nearly every page adds to the screen. Should one run of
    /// pages not, the reading stops after ``fruitlessLimit`` of them and waits
    /// on Keep Looking: a site asked too fast stops answering the app
    /// altogether.
    private func readOn() async {
        guard filter.holdsRows, !isSkipping, !hasEveryMatch, fruitlessPages < Self.fruitlessLimit,
              events.moreFailure == nil, !events.isLoading, !events.isLoadingMore
        else { return }
        let shown = shownEvents.count
        await events.loadMore()
        store.remember(events.items)
        fruitlessPages = shownEvents.count > shown ? 0 : fruitlessPages + 1
    }

    /// The first page of a listing in date order that can hold a row the
    /// filter wants — found by halving, a page asked at a time, rather than by
    /// reading every page in front of it. A listing of 349 results takes four
    /// pages to search this way, and a listing of thousands a dozen.
    ///
    /// A page whose last row is still in front of the rows wanted is wholly in
    /// front of them, since the listing is in order; the first page whose last
    /// row is not is where they begin. Page 1 has already been read and is in
    /// front, or this would not be asked.
    nonisolated private static func firstPage(
        of source: Feed<Event>.Source, pages: Int, reading order: SearchOrder, filter: SearchFilter
    ) async throws -> Int {
        var low = 2
        var high = max(pages, 2)
        while low < high {
            let middle = (low + high) / 2
            let page = try await source(middle)
            guard let last = page.items.last else {
                // Past the end the site actually holds: look nearer.
                high = middle
                continue
            }
            if await filter.comesBeforeMatches(last, reading: order) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// The capsule over the search field — see ``ListMenu`` — holding the filter
    /// and the order. Its face says what the results are held to while they are
    /// held to anything, so a short list is never a mystery.
    private var controls: some View {
        ListMenu(describes: "Filter and Sort", value: Text("\(filterSummary), \(Text(order.label))")) {
            // Both halves of the filter a level down, each a row with its
            // icon and what it is set to, beside the order's own rows. In
            // each, the choice that holds nothing back stands above a divider
            // and the ones that do below it.
            Section("Filter") {
                Menu {
                    Toggle(isOn: menuChoice($filter.when, .any)) { Text(SearchFilter.When.any.label) }
                    Section {
                        ForEach(SearchFilter.When.allCases.filter { $0 != .any }, id: \.self) { when in
                            Toggle(isOn: menuChoice($filter.when, when)) { Text(when.label) }
                        }
                    }
                } label: {
                    Label("Date", systemImage: "calendar")
                    Text(filter.when.label)
                }
                Menu {
                    Toggle(isOn: menuChoice($filter.area, nil)) { Text("Anywhere") }
                    Section {
                        ForEach(SearchFilter.Area.all, id: \.self) { area in
                            Toggle(isOn: menuChoice($filter.area, area)) { Text(area.label) }
                        }
                    }
                } label: {
                    Label("Area", systemImage: "map")
                    Text(filter.area?.label ?? "Anywhere")
                }
            }
            Section("Sort") {
                ForEach(SearchOrder.allCases, id: \.self) { choice in
                    Toggle(isOn: menuChoice($order, choice)) {
                        Label(choice.label, systemImage: choice.systemImage)
                    }
                }
            }
        } face: {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(filter.isNarrowing ? Color.brandTint : .secondary)
                    filterSummary
                        .foregroundStyle(filter.isNarrowing ? Color.brandTint : .primary)
                        .lineLimit(1)
                }
                Circle()
                    .fill(.tertiary)
                    .frame(width: 3, height: 3)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    /// What the filter holds the results to, in as few words as will say it:
    /// when, and where.
    private var filterSummary: Text {
        var parts: [Text] = []
        if filter.when != .any { parts.append(Text(filter.when.label)) }
        if let area = filter.area { parts.append(Text(area.label)) }
        guard let first = parts.first else { return Text("All") }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// Nothing the site sent survives the filter.
    private var nothingMatches: some View {
        ContentUnavailableView {
            Label("No Matching Events", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Nothing Eventernote found for this search falls within the filter. Widen it to see the rest.")
        } actions: {
            Button("Clear Filter") {
                withAnimation(.snappy) { filter = SearchFilter() }
            }
            .buttonStyle(.glass)
        }
        .padding(.top, 48)
    }

    /// Where the reading stopped short of the end, and the way on.
    private var keepLooking: some View {
        HStack(spacing: 10) {
            Text("^[\(events.items.count) result](inflect: true) read so far. The rest may hold more.")
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Keep Looking") {
                fruitlessPages = 0
                Task { await readOn() }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassPanel()
    }

    @ViewBuilder
    private var performerResults: some View {
        if performers.isLoading {
            SearchProgress()
        } else if let failure = performers.failure {
            SearchFailure(message: failure) { await search() }
        } else if performers.isEmptyResult {
            ContentUnavailableView.search(text: term)
                .padding(.top, 48)
        } else {
            LazyVStack(alignment: .leading, spacing: 9) {
                SectionLabel(label: "^[\(performers.total) performer](inflect: true) on Eventernote")

                ForEach(performers.items) { performer in
                    PerformerRow(performer: performer)
                        .task {
                            guard performers.isNearEnd(performer) else { return }
                            await performers.loadMore()
                        }
                }

                FeedFooter(feed: performers)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Before a search

    private var recentSearches: [String] { settingsRows.first?.recentSearches ?? [] }

    private var startingPoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !recentSearches.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    // Not a ``SectionLabel``: that carries its own inset, and
                    // this one is set by the row it shares with Clear.
                    Text("Recent")
                        .font(.system(size: 11.5, weight: .semibold))
                        .kerning(0.35)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear") { store.clearRecentSearches() }
                        .font(.system(size: 12, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandTint)
                }
                .padding(.horizontal, 4)

                FlowLayout(spacing: 8) {
                    ForEach(recentSearches, id: \.self) { recent in
                        Button(recent) { query = recent }
                            .font(.system(size: 13, weight: .medium))
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .glassCapsule(interactive: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Searching public Eventernote pages")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Results come from publicly accessible event pages. Nothing you tag here is written back to Eventernote.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassPanel()
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// A search result. The circular control adds the event to the library, or
/// removes it again — always an explicit choice.
struct SearchResultRow: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let event: Event
    let open: () -> Void

    /// A search row carries no head count, so it shows what the row does know
    /// — the listed head count where there is one, and otherwise whatever the
    /// row would have said about the time anyway.
    private var detail: Text {
        guard let listed = event.listedAttendees else { return event.shown(on: timeDisplay).timeDetail }
        return Text("\(listed.formatted()) going")
    }

    var body: some View {
        EventRowContent(event: event, detail: detail) {
            LibraryToggle(event: event)
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .glassPanel()
    }
}

/// A performer search result. Opening one lists everything they are billed on.
private struct PerformerRow: View {
    let performer: PerformerProfile

    var body: some View {
        NavigationLink(value: PerformerLink.profile(performer)) {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(performer.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                    if let reading = performer.reading {
                        Text(reading)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let fans = performer.fanCount {
                    Text("^[\(fans) fan](inflect: true)")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
    }
}

/// The wait while Eventernote answers.
struct SearchProgress: View {
    var compact = false

    var body: some View {
        ProgressView()
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .padding(.top, compact ? 12 : 60)
            .padding(.bottom, compact ? 12 : 0)
    }
}

/// What sits under a paged listing: a spinner while the next page is on its
/// way, or why it did not arrive and a Try Again. Without the second a failed
/// page looked exactly like the end of the listing.
struct FeedFooter<Item: Identifiable & Sendable>: View {
    let feed: Feed<Item>
    /// What the screen does with the rows once a retried page lands.
    var landed: () -> Void = {}

    var body: some View {
        if let failure = feed.moreFailure {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.favorite)
                    .frame(width: 18)
                Text(verbatim: failure)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") {
                    Task {
                        await feed.retryMore()
                        landed()
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassPanel()
        } else if feed.isLoadingMore {
            SearchProgress(compact: true)
        }
    }
}

/// Eventernote could not be reached. The reader is told which, and can retry.
struct SearchFailure: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Search Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(verbatim: message)
        } actions: {
            Button("Try Again") { Task { await retry() } }
                .buttonStyle(.glass)
        }
        .padding(.top, 40)
    }
}

#Preview {
    SearchView()
        .library(EventStore.preview)
}
