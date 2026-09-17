import SwiftUI

/// Every date Eventernote has published for the performers the reader follows.
///
/// The library tab is what the reader has decided about; this is what is coming
/// that they have not decided about yet. Nothing here is in the library until
/// they put it there, which is what the control on each row is for.
struct FollowingView: View {
    @Environment(EventStore.self) private var store
    @Environment(FollowedDates.self) private var followed

    /// Which followed performer the list is narrowed to, or nil for all of
    /// them. Held as an id rather than a profile so unfollowing someone while
    /// their filter is on falls back to all of them rather than to an empty
    /// list of one person who is no longer there.
    @State private var filter: PerformerProfile.ID?
    @State private var openEvent: Event?

    private var performers: [PerformerProfile] { store.followedPerformers }

    /// The performers the list is currently showing dates for.
    private var shown: [PerformerProfile] {
        guard let filter, let chosen = performers.first(where: { $0.id == filter }) else {
            return performers
        }
        return [chosen]
    }

    private var events: [Event] { followed.events(for: shown) }

    private var groups: [EventGroup] {
        // `events` is already date-ordered, so first appearance sets section
        // order — the same way the library groups its months.
        var order: [String] = []
        var buckets: [String: [Event]] = [:]
        for event in events {
            let key = event.monthGroupLabel
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(event)
        }
        return order.map { EventGroup(id: $0, label: $0, events: buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if performers.isEmpty {
                        nobodyFollowed
                    } else {
                        filters
                        if let failure = followed.failure, events.isEmpty {
                            SearchFailure(message: failure) { await reload() }
                        } else if groups.isEmpty {
                            if followed.isLoading {
                                SearchProgress()
                            } else {
                                noDatesPublished
                            }
                        } else {
                            months
                            if followed.isLoading { SearchProgress(compact: true) }
                            footnote
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .washBackground()
            .navigationTitle("Following")
            .navigationSubtitle(subtitle)
            .navigationDestination(for: PerformerLink.self) { link in
                PerformerView(link: link)
            }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
            .refreshable { await reload() }
            // Following someone on their page should show their dates here on
            // the way back, so this follows the list rather than only the first
            // appearance of the screen.
            .task(id: performers.map(\.id)) { await load() }
        }
    }

    /// What the tab adds up to: how many people, and how much they have coming.
    private var subtitle: Text {
        guard !performers.isEmpty else { return Text("Nobody followed yet") }
        let people = Text("^[\(performers.count) performer](inflect: true)")
        let dates = Text("^[\(followed.events(for: performers).count) event](inflect: true)")
        return Text("\(people) · \(dates)")
    }

    // MARK: - Loading

    private func load() async {
        await followed.load(for: performers)
        store.remember(followed.events(for: performers))
    }

    private func reload() async {
        await followed.reload(for: performers)
        store.remember(followed.events(for: performers))
    }

    // MARK: - Narrowing to one of them

    /// One chip per followed performer, each carrying what it would leave on
    /// screen. A count that is still being read shows nothing rather than a
    /// zero it would have to take back.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(label: Text("All"), count: followed.events(for: performers).count,
                     isOn: filter == nil) { filter = nil }

                ForEach(performers) { performer in
                    chip(label: Text(verbatim: performer.name),
                         count: followed.count(for: performer),
                         isOn: filter == performer.id) { filter = performer.id }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(
        label: Text, count: Int?, isOn: Bool, choose: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy) { choose() }
        } label: {
            HStack(spacing: 7) {
                label
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.brandTint : .secondary)
                    .lineLimit(1)
                if let count {
                    Text(count.formatted())
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassCapsule(interactive: true)
    }

    // MARK: - The dates themselves

    /// Sectioned and pinned, the way the library tab's own months are: a long
    /// list of published dates is read by month, so the month being read stays
    /// on screen while it is being read.
    private var months: some View {
        LazyVStack(alignment: .leading, spacing: 9, pinnedViews: .sectionHeaders) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.events) { event in
                        FollowedDateRow(event: event,
                                        billing: followed.billed(on: event, among: performers)) {
                            openEvent = event
                        }
                        .padding(.horizontal, 16)
                    }
                } header: {
                    GroupHeader(label: Text(group.label), count: group.events.count)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - When there is nothing to show

    /// Two different silences, told apart: nobody to follow dates for, and
    /// nobody who has any.
    private var nobodyFollowed: some View {
        ContentUnavailableView {
            Label("Nobody Followed", systemImage: "person.2")
        } description: {
            Text("Follow a performer from their page and every date Eventernote publishes for them shows up here.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var noDatesPublished: some View {
        ContentUnavailableView {
            Label("No Dates Published", systemImage: "calendar")
        } description: {
            Text("Eventernote has published nothing upcoming for the performers you follow. New dates appear here as they are listed.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var footnote: some View {
        Text("Dates come from publicly accessible Eventernote pages. Following is kept in your own library — nothing is written back.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 6)
    }
}

/// One published date, captioned with whichever followed performers are billed
/// on it. Tapping the caption opens that performer; the circular control adds
/// the event to the library, or takes it out again.
private struct FollowedDateRow: View {
    @Environment(EventStore.self) private var store

    let event: Event
    let billing: [PerformerProfile]
    let open: () -> Void

    private var isSaved: Bool { store.isInLibrary(event) }

    /// A performer's listing prints times for some rows and not others, and an
    /// announced date says so rather than being given an invented hour.
    private var detail: Text {
        event.timeLine.map { Text(verbatim: $0) } ?? Text("Time to be announced")
    }

    var body: some View {
        EventRowContent(event: event, detail: detail) {
            if let first = billing.first {
                // The whole caption leads to the first name on it. Two followed
                // performers sharing a bill is the uncommon case, and a row is
                // not the place to make the reader choose between them — their
                // own page is one tap further on either way.
                NavigationLink(value: PerformerLink.profile(first)) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.brandTint)
                            .frame(width: 6, height: 6)
                        Text(verbatim: billing.map(\.name).joined(separator: " · "))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.brandTint)
                            .lineLimit(1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } trailing: {
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
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .glassPanel()
    }
}

#Preview {
    FollowingView()
        .environment(EventStore.preview)
        .environment(FollowedDates.preview)
}
