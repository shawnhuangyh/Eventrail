import SwiftUI

/// Searches publicly accessible Eventernote pages. Nothing tagged here is
/// written back to Eventernote.
struct SearchView: View {
    @Environment(EventStore.self) private var store

    @State private var query = ""
    @State private var scope: SearchScope = .events
    @State private var events = Feed<Event>()
    @State private var performers = Feed<PerformerProfile>()
    @State private var openEvent: Event?

    /// The query and the scope together: either one changing starts a new search.
    private struct Request: Hashable {
        let term: String
        let scope: SearchScope
    }

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
            .task(id: Request(term: term, scope: scope)) { await search() }
        }
    }

    /// Runs the search the field currently describes.
    ///
    /// `task(id:)` cancels this when the reader types again, so the pause at the
    /// top is what keeps a request from going out per keystroke.
    private func search() async {
        let term = term
        guard !term.isEmpty else {
            events.clear()
            performers.clear()
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        switch scope {
        case .events:
            await events.load { page in
                try await EventernoteClient.shared.searchEvents(keyword: term, page: page)
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
        if events.isLoading {
            SearchProgress()
        } else if let failure = events.failure {
            SearchFailure(message: failure) { await search() }
        } else if events.isEmptyResult {
            ContentUnavailableView.search(text: term)
                .padding(.top, 48)
        } else {
            LazyVStack(alignment: .leading, spacing: 9) {
                SectionLabel(label: "^[\(events.total) result](inflect: true) on Eventernote")

                ForEach(events.items) { event in
                    SearchResultRow(event: event) { openEvent = event }
                        .task { await store.pageOn(events, after: event) }
                }

                FeedFooter(feed: events) { store.remember(events.items) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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

    private var startingPoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.recentSearches.isEmpty {
                HStack {
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
                    ForEach(store.recentSearches, id: \.self) { recent in
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
        .environment(EventStore.preview)
}
