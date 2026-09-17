import SwiftUI

/// The reader's own library at a glance: what it holds, when it was last
/// imported, and what it keeps in front of them.
///
/// Everything that configures the app lives behind the gear rather than on this
/// screen. What is left is the library itself.
struct MeView: View {
    @Environment(EventStore.self) private var store
    @Environment(FollowedDates.self) private var followed

    @State private var openEvent: Event?
    @State private var isLinking = false
    @State private var isConfirmingUnlink = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    accountCard
                    statistics
                    favoritesCard
                    followingCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .washBackground()
            .navigationTitle("Me")
            .navigationDestination(for: PerformerLink.self) { link in
                PerformerView(link: link)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
            .sheet(isPresented: $isLinking) {
                EventernoteAccountSheet()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .confirmationDialog("Unlink this Eventernote account?",
                                isPresented: $isConfirmingUnlink, titleVisibility: .visible) {
                Button("Unlink", role: .destructive) { store.unlinkAccount() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("The events already imported stay in your library.")
            }
            // The same read the Following tab does, and the same object holds
            // it — whichever screen the reader opens first pays for it.
            .task(id: store.followedPerformers.map(\.id)) {
                await followed.load(for: store.followedPerformers)
            }
        }
    }

    // MARK: - The account, and the one thing it is for

    /// The account and the import it feeds are one card, because they are one
    /// intention: bring the library up to date from Eventernote. Refresh needs
    /// an account to refresh from, so the row that names one sits directly
    /// beneath it rather than on a screen of its own.
    ///
    /// Eventrail reads Eventernote's public pages and nothing else. There is no
    /// login behind this card, and nothing is ever written back.
    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AccountAvatar(url: store.eventernoteProfile?.avatarURL, width: 58)

                VStack(alignment: .leading, spacing: 5) {
                    accountTitle
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    accountDetail
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Text(store.isRefreshing ? "Refreshing" : "Refresh")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.brandTint)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .glassCapsule(interactive: true)
                .disabled(store.isRefreshing || !store.isLinked)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(16)

            refreshDetail
                .font(.system(size: 12))
                .foregroundStyle(store.refreshFailure == nil ? .secondary : Color.favorite)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            if let fraction = refreshFraction {
                ProgressView(value: fraction)
                    .tint(Color.trackTicket)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            if store.eventernoteHandle == nil {
                accountRow("Link Eventernote Account") { isLinking = true }
            } else {
                accountRow("Change Account") { isLinking = true }
                accountRow("Unlink Account") { isConfirmingUnlink = true }
            }
        }
        .glassPanel(cornerRadius: 28)
    }

    /// The account's own name when Eventernote has printed one, since that is
    /// how the reader knows themselves there; the handle alone otherwise, which
    /// is all a library linked before the app read the page has.
    private var accountTitle: Text {
        if let name = store.eventernoteProfile?.name {
            Text(verbatim: name)
        } else if let handle = store.eventernoteHandle {
            Text(verbatim: "@\(handle)")
        } else {
            Text("Eventernote")
        }
    }

    /// What the library holds, behind the handle when the title has given way to
    /// a display name. The handle is what every request is addressed to and what
    /// tells two accounts apart, so it stays on the card either way rather than
    /// only inside the sheet that changes it.
    private var accountDetail: Text {
        let counts = Text("^[\(store.library.count) event](inflect: true) · ^[\(store.favoriteEvents.count) favorite](inflect: true)")
        guard store.eventernoteProfile != nil, let handle = store.eventernoteHandle else {
            return counts
        }
        return Text(verbatim: "@\(handle) · ") + counts
    }

    /// The honest wording: the app reports when it last *succeeded*, never that
    /// the data is current.
    private var refreshDetail: Text {
        // Said before anything else: with no account there is nothing to
        // refresh from, and a stale timestamp would only be confusing.
        guard store.isLinked else {
            return Text("Link your account to bring your library up to date")
        }
        if store.isRefreshing {
            return workingDetail
        }
        // Counts and a short fall belong on the same line: "it worked" and "it
        // only got this far" are both true of a partial import.
        if let summary = store.importSummary, let counts = importCounts(summary) {
            guard let failure = store.refreshFailure else { return counts }
            return Text("\(counts) \(failure)")
        }
        if let failure = store.refreshFailure {
            return Text(verbatim: failure)
        }
        if let lastRefreshed = store.lastRefreshed {
            return Text("Refreshed \(lastRefreshed, format: .relative(presentation: .named))")
        }
        return Text("Never refreshed")
    }

    /// What the last import changed. The performers are counted apart from the
    /// events because they came from a different page — the account's own, and
    /// its favourites block — rather than out of the history.
    ///
    /// Either half can be the whole of it: a history that reached nothing can
    /// still have picked performers up, and usually neither number moves at all.
    private func importCounts(_ summary: EventStore.ImportSummary) -> Text? {
        var detail: Text?
        if summary.read > 0 {
            detail = Text("Imported ^[\(summary.read) event](inflect: true) — \(summary.added) added, \(summary.filled) updated")
        }
        if summary.followed > 0 {
            let follows = Text("^[\(summary.followed) performer](inflect: true) followed from your favorites")
            detail = detail.map { Text("\($0) · \(follows)") } ?? follows
        }
        return detail
    }

    /// Which of the two passes is running. They take very different amounts of
    /// time, so saying only "Refreshing" would leave the longer one looking
    /// stuck.
    private var workingDetail: Text {
        switch store.refreshStage {
        case .readingHistory(_, 0), .none:
            Text("Reading your Eventernote history…")
        case .readingHistory(let read, let total):
            Text("Reading your history — \(read) of ^[\(total) event](inflect: true)")
        case .reimporting(let read, let total):
            Text("Re-importing — \(read) of ^[\(total) event](inflect: true)")
        }
    }

    /// How far along the running pass is. Both passes know their own length, so
    /// neither has to spin without saying how much is left.
    private var refreshFraction: Double? {
        switch store.refreshStage {
        case .readingHistory(let read, let total) where total > 0,
             .reimporting(let read, let total) where total > 0:
            Double(read) / Double(total)
        default:
            nil
        }
    }

    private func accountRow(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .overlay(alignment: .top) {
            Divider().padding(.leading, 16)
        }
    }

    // MARK: - What the library adds up to

    private var statistics: some View {
        HStack(spacing: 11) {
            StatTile(tint: .trackInterest, value: store.eventsThisYear.formatted(),
                     label: "Events this year")
            StatTile(tint: .trackTicket, value: store.venuesVisited.formatted(),
                     label: "Venues visited")
            StatTile(tint: .trackAttended, value: store.performersSeen.formatted(),
                     label: "Performers seen")
        }
    }

    // MARK: - Favorites

    /// Events hearted from the detail sheet. Favoriting is separate from the
    /// three tracking fields: it says "keep this in front of me", not "I have a
    /// ticket".
    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Favorite Events")
                    .font(.system(size: 17, weight: .bold))
                if !store.favoriteEvents.isEmpty {
                    Text(store.favoriteEvents.count.formatted())
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, store.favoriteEvents.isEmpty ? 6 : 12)

            if store.favoriteEvents.isEmpty {
                Text("Tap the heart on any event to keep it here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.favoriteEvents.enumerated()), id: \.element.id) { index, event in
                        favoriteRow(event, isFirst: index == 0)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .glassPanel()
    }

    // MARK: - Followed performers

    /// Who the reader follows, and how much each of them has coming.
    ///
    /// The list is theirs, kept beside their library — it is not the favourite
    /// list their Eventernote account holds, which this app only ever reads.
    /// Unfollowing is here rather than only on a performer's own page, because
    /// this is the one screen that shows the list as a list.
    private var followingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Following Performers")
                    .font(.system(size: 17, weight: .bold))
                if !store.followedPerformers.isEmpty {
                    Text(store.followedPerformers.count.formatted())
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, store.followedPerformers.isEmpty ? 6 : 12)

            if store.followedPerformers.isEmpty {
                Text("Follow a performer from their page to keep them here. It stays in your library and is never written back to Eventernote.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.followedPerformers.enumerated()), id: \.element.id) { index, performer in
                        followRow(performer, isFirst: index == 0)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .glassPanel()
    }

    private func followRow(_ performer: PerformerProfile, isFirst: Bool) -> some View {
        NavigationLink(value: PerformerLink.profile(performer)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: performer.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    followDetail(performer)
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.snappy) { store.unfollow(performer) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.trackAttended)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop following")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if !isFirst { Divider().padding(.leading, 16) }
        }
    }

    /// The kana reading the site prints, and what they have coming — but only
    /// once their listing has actually been read. A count of zero beside
    /// somebody whose page has not answered yet would be a claim the app
    /// cannot make.
    private func followDetail(_ performer: PerformerProfile) -> Text {
        let dates: Text
        switch followed.count(for: performer) {
        case .none: dates = Text("Reading their dates…")
        case 0: dates = Text("No dates published yet")
        case let count?: dates = Text("^[\(count) upcoming date](inflect: true)")
        }
        guard let reading = performer.reading else { return dates }
        return Text("\(reading) · \(dates)")
    }

    private func favoriteRow(_ event: Event, isFirst: Bool) -> some View {
        Button {
            openEvent = event
        } label: {
            HStack(spacing: 12) {
                FlyerThumbnail(url: event.imageURL, width: 38, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(verbatim: "\(event.dayLine) · \(event.venue)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.snappy) { store.toggleFavorite(event) }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.favorite)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from favorites")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if !isFirst { Divider().padding(.leading, 66) }
        }
    }
}

#Preview {
    MeView()
        .environment(EventStore.preview)
        .environment(FollowedDates.preview)
}
