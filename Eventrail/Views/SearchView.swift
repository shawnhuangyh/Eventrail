import SwiftUI

/// Searches publicly accessible Eventernote pages. Nothing tagged here is
/// written back to Eventernote.
struct SearchView: View {
    @Environment(EventStore.self) private var store

    @State private var query = ""
    @State private var scope: SearchScope = .events
    @State private var openEvent: Event?

    private var results: [Event] {
        store.searchResults(query: query, scope: scope)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startingPoints
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 48)
                } else {
                    resultList
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
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
        }
    }

    private var resultList: some View {
        LazyVStack(alignment: .leading, spacing: 9) {
            Text("^[\(results.count) result](inflect: true) on Eventernote")
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.35)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)

            ForEach(results) { event in
                SearchResultRow(event: event) { openEvent = event }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var startingPoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.35)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            FlowLayout(spacing: 8) {
                ForEach(SampleData.recentSearches, id: \.self) { term in
                    Button(term) { query = term }
                        .font(.system(size: 13, weight: .medium))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassCapsule(interactive: true)
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
private struct SearchResultRow: View {
    @Environment(EventStore.self) private var store

    let event: Event
    let open: () -> Void

    private var isSaved: Bool { store.isInLibrary(event) }

    var body: some View {
        EventRowContent(
            event: event,
            detail: Text("\(event.listedAttendees.formatted()) going")
        ) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { store.toggleLibraryMembership(event) }
                } label: {
                    Image(systemName: isSaved ? "checkmark" : "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSaved ? Color.trackAttended : Color.brandTint)
                        .frame(width: 38, height: 38)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .accessibilityLabel(isSaved ? "Remove from my events" : "Add to my events")
                Spacer(minLength: 0)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .glassPanel()
    }
}

#Preview {
    SearchView()
        .environment(EventStore())
}
