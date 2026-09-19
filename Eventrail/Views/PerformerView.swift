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

    let link: PerformerLink

    @State private var lookup: Lookup = .looking
    @State private var feed = Feed<Event>()
    /// Whether the listing has been asked for yet. The feed cannot say so
    /// itself — an untouched feed and one that answered with nothing look the
    /// same from outside — and the gap between the two is a frame of empty
    /// sections the reader should never see.
    @State private var hasReadListing = false
    @State private var openEvent: Event?

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
        // An imported name, shown in the language Eventernote published it in.
        .navigationTitle(Text(verbatim: link.name))
        .navigationBarTitleDisplayMode(.inline)
        .eventSheet($openEvent)
        .task { await load() }
    }

    // MARK: - Loading

    private func load() async {
        // Already resolved on a retry of the listing alone; resolved again when
        // it was the name lookup that failed.
        var resolved = profile
        if resolved == nil { resolved = await resolve() }
        guard let profile = resolved else { return }

        await feed.load { page in
            try await EventernoteClient.shared.events(forPerformer: profile, page: page)
        }
        hasReadListing = true
        store.remember(feed.items)
        await readRemainingUpcoming()
    }

    private func retry() async {
        lookup = .looking
        await load()
    }

    /// Turns whatever the page was opened with into a profile.
    private func resolve() async -> PerformerProfile? {
        switch link {
        case .profile(let profile):
            lookup = .found(profile)
            return profile
        case .billed(let name):
            do {
                guard let found = try await EventernoteClient.shared.performer(named: name) else {
                    lookup = .unlisted
                    return nil
                }
                lookup = .found(found)
                return found
            } catch {
                lookup = .failed(error.localizedDescription)
                return nil
            }
        }
    }

    /// Reads pages until the first past appearance shows up.
    ///
    /// The listing runs from the furthest published date backwards, so one past
    /// row proves every upcoming one is already in hand. Without this, Upcoming
    /// would show however many happened to fall on the first page and the count
    /// over it would be wrong.
    private func readRemainingUpcoming() async {
        while feed.hasMore, !feed.items.contains(where: { !$0.isUpcoming }) {
            let read = feed.items.count
            await feed.loadMore()
            // A page that adds nothing would otherwise spin here forever.
            guard feed.items.count > read else { break }
        }
        store.remember(feed.items)
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
            if let profile {
                actions(for: profile)
                followNote(for: profile)
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

    private func actions(for profile: PerformerProfile) -> some View {
        let isFollowing = store.isFollowing(profile)
        return HStack(spacing: 9) {
            Button {
                withAnimation(.snappy) { store.toggleFollow(profile) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    if isFollowing { Text("Following") } else { Text("Follow") }
                }
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(isFollowing ? Color.trackAttended : Color.brandTint)
                .padding(.horizontal, 22)
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

    /// Says what following does here, which is less than the word usually
    /// promises: it marks the performer in this reader's own library and
    /// nothing is sent to Eventernote.
    private func followNote(for profile: PerformerProfile) -> some View {
        Group {
            if store.isFollowing(profile) {
                Text("Kept with your library and private to you. Your Eventernote favourites are untouched.")
            } else {
                Text("Following keeps a performer with your library. It is private to you and never written back to Eventernote.")
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 290)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
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
            SearchFailure(message: failure) { await load() }
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
            if feed.isLoadingMore { SearchProgress(compact: true) }
            if !sameBill.isEmpty { sameBillCard }
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
                     value: store.attendedCount(billing: link.name).formatted(),
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
                ForEach(events.prefix(Self.sectionLimit)) { event in
                    Divider().opacity(0.45).padding(.leading, 12)
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

    @ViewBuilder
    private var openInEventernote: some View {
        if let profile {
            ExternalLinkPanel(title: "Open performer on Eventernote",
                              destination: profile.pageURL)
                .padding(.horizontal, 18)
        }
    }

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
    .environment(EventStore.preview)
}
