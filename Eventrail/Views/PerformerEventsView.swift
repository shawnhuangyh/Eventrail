import SwiftUI

/// Everything one performer is billed on, from their public Eventernote page.
///
/// Reached from the Performers scope of Search: finding the person is usually
/// easier than guessing how their tour was titled.
struct PerformerEventsView: View {
    @Environment(EventStore.self) private var store

    let performer: PerformerProfile

    @State private var feed = Feed<Event>()
    @State private var openEvent: Event?

    var body: some View {
        ScrollView {
            if feed.isLoading {
                SearchProgress()
            } else if let failure = feed.failure {
                SearchFailure(message: failure) { await load() }
            } else if feed.isEmptyResult {
                ContentUnavailableView {
                    Label("No Events Listed", systemImage: "calendar")
                } description: {
                    Text("Eventernote lists no events for this performer.")
                }
                .padding(.top, 48)
            } else {
                list
            }
        }
        .washBackground()
        // An imported name, shown in the language Eventernote published it in.
        .navigationTitle(Text(verbatim: performer.name))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openEvent) { event in
            EventDetailView(event: event)
        }
        .task { await load() }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 9) {
            Text("^[\(feed.total) event](inflect: true) on Eventernote")
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.35)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)

            ForEach(feed.items) { event in
                SearchResultRow(event: event) { openEvent = event }
                    .task {
                        guard feed.isNearEnd(event) else { return }
                        await feed.loadMore()
                        store.remember(feed.items)
                    }
            }

            if feed.isLoadingMore { SearchProgress(compact: true) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func load() async {
        let performer = performer
        await feed.load { page in
            try await EventernoteClient.shared.events(forPerformer: performer, page: page)
        }
        store.remember(feed.items)
    }
}

#Preview {
    NavigationStack {
        PerformerEventsView(
            performer: PerformerProfile(id: 2890, name: "水瀬いのり", reading: "みなせいのり",
                                        fanCount: 5514, slug: "%E6%B0%B4%E7%80%AC%E3%81%84%E3%81%AE%E3%82%8A")
        )
    }
    .environment(EventStore.preview)
}
