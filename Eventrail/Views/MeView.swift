import SwiftUI

/// Which of the Me tab's two lists has been opened in full.
enum MeList: Hashable {
    case favorites, following
}

/// The reader's own library at a glance: what it holds, when it was last
/// imported, and what it keeps in front of them.
///
/// Everything that configures the app lives behind the gear rather than on this
/// screen. What is left is the library itself.
struct MeView: View {
    @Environment(EventStore.self) private var store
    @Environment(FollowedDates.self) private var followed
    @Environment(VenueRegions.self) private var venues
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.scenePhase) private var scenePhase

    @State private var openEvent: Event?
    @State private var isLinking = false
    @State private var isConfirmingUnlink = false
    @State private var isShowingSettings = false

    /// How much of each list the cards show before sending the rest to a
    /// screen of its own. Enough to be a summary of what is there, few enough
    /// that the two cards below the account cannot push each other off the
    /// bottom as the library grows.
    private static let cardLimit = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    accountCard
                    passportCard
                    favoritesCard
                    followingCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .washBackground()
            .navigationTitle("Me")
            .performerDestination()
            .navigationDestination(for: PassportLink.self) { _ in EventPassportView() }
            .navigationDestination(for: MeList.self) { list in
                switch list {
                case .favorites: FavoriteEventsView()
                case .following: FollowedPerformersView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
            .eventSheet($openEvent)
            .sheet(isPresented: $isLinking) {
                EventernoteAccountSheet()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            // The same read the Following tab does, and the same object holds
            // it — whichever screen the reader opens first pays for it, and
            // only when what it holds is stale.
            .task(id: followed.loadKey(for: store.followedPerformers)) { await loadFollowed() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadFollowed() } }
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
                    VStack(alignment: .leading, spacing: 3) {
                        if let handle = store.eventernoteProfile != nil
                            ? store.eventernoteHandle : nil {
                            Text(verbatim: "@\(handle)")
                                .lineLimit(1)
                        }
                        accountCounts
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task { await refreshLibrary() }
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
                // The sheet hangs off the row that opens it: iOS points a
                // confirmation at whatever presented it, and one attached to the
                // whole screen arrives pointing at nothing in particular.
                accountRow("Unlink Account") { isConfirmingUnlink = true }
                    .confirmationDialog("Unlink this Eventernote account?",
                                        isPresented: $isConfirmingUnlink,
                                        titleVisibility: .visible) {
                        Button("Unlink", role: .destructive) { store.unlinkAccount() }
                        Button("Keep it", role: .cancel) {}
                    } message: {
                        Text("The events already imported stay in your library.")
                    }
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

    /// What the account brought over, behind the handle when the title has
    /// given way to a display name. Both halves come from Eventernote: the
    /// history the import read, and the performers seeded from the favourites
    /// on the site. The handle is what every request is addressed to and what
    /// tells two accounts apart, so it stays on the card either way rather than
    /// only inside the sheet that changes it.
    /// What the library holds, on a line of its own under the handle.
    ///
    /// Two lines rather than one: the handle and the counts are different
    /// kinds of fact — who this is, and what they have — and run together they
    /// wrapped wherever the name happened to end, breaking mid-count against
    /// the Refresh button.
    ///
    /// "following" is not inflected: a count of them is still "following",
    /// never "followings".
    private var accountCounts: Text {
        Text("^[\(store.library.count) event](inflect: true) · \(store.followedPerformers.count) following")
    }

    /// The honest wording: the app reports when it last *succeeded*, never that
    /// the data is current.
    /// Whatever followed listings have gone stale, and nothing else.
    private func loadFollowed() async {
        if let outcome = await followed.load(for: store.followedPerformers) {
            notices?.report(.following(outcome), byHand: false)
        }
        // The card counts what is still ahead, and a night abroad is ahead
        // until its own hall's clock says otherwise.
        venues.learn(from: store.library)
        await venues.settle(followed.events(for: store.followedPerformers))
    }

    /// Refresh, and then say how it went — over the top of the screen, as well
    /// as on the card's own line, since the reader may have scrolled on.
    private func refreshLibrary() async {
        guard await store.refresh() else { return }
        notices?.report(.library(failure: store.refreshFailure), byHand: true)
    }

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
            detail = Text("Imported ^[\(summary.read) event](inflect: true) — \(summary.added) added")
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

    // MARK: - The Passport

    /// The way into the reader's own record of where they have been, over the
    /// three counts that summarise it.
    ///
    /// One card, built the way the two cards under it are: a ``CardHeader``
    /// with the way into the rest on its right, and the contents laid directly
    /// on the glass beneath it. The whole card is the way in, so the counts
    /// push as readily as the See All does.
    ///
    /// The three are the Passport's own numbers rather than the library's:
    /// every one is counted over the nights already stood at, so a date still
    /// ahead moves nothing here until it has passed, and the card says what
    /// the screen behind it says.
    private var passportCard: some View {
        NavigationLink(value: PassportLink.passport) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Event Passport") { SeeAllLabel() }

                HStack(spacing: 0) {
                    passportTile(store.eventsAttended, tint: .trackInterest,
                                 label: "Events attended", isFirst: true)
                    passportTile(store.venuesVisited, tint: .trackTicket,
                                 label: "Venues visited", isFirst: false)
                    passportTile(store.performersSeen, tint: .trackAttended,
                                 label: "Performers seen", isFirst: false)
                }
            }
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 28, interactive: true)
    }

    /// One of the three counts, drawn on the card rather than in a
    /// ``StatTile`` of its own.
    ///
    /// The tints are the ones this screen has always given these three numbers;
    /// the panel is gone, because these sit *inside* one now and glass set in
    /// glass reads as a smudge. What separates them instead is a hairline, the
    /// same one the Passport's own Time at Events strip uses — three counts
    /// standing loose in a row read as three things that happen to be near each
    /// other rather than as one reading of a library.
    ///
    /// The dot leads the value on its own line rather than floating above it:
    /// a mark with a number beside it is a key, and a mark with a gap under it
    /// is a stray.
    private func passportTile(
        _ value: Int, tint: Color, label: LocalizedStringKey, isFirst: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(value.formatted())
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, isFirst ? 0 : 14)
        .overlay(alignment: .leading) {
            // A drawn hairline rather than a `Divider`: a divider left to work
            // out its own orientation inside an overlay takes the height of
            // the tallest line instead of the cell, and stops short above the
            // caption.
            if !isFirst {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Favorites

    /// Events hearted from the detail sheet. Favoriting is separate from what
    /// the reader records about a ticket: it says "keep this in front of me",
    /// not "I have a ticket".
    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Favorite Events",
                       count: store.favoriteEvents.isEmpty ? nil : store.favoriteEvents.count) {
                if !store.favoriteEvents.isEmpty {
                    seeAll(.favorites)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, store.favoriteEvents.isEmpty ? 6 : 12)

            if store.favoriteEvents.isEmpty {
                Text(FavoriteEventRow.emptyNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    let shown = Array(store.favoriteEvents.prefix(Self.cardLimit))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                        FavoriteEventRow(event: event, showsDivider: index > 0) {
                            openEvent = event
                        }
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
            CardHeader(title: "Following Performers",
                       count: store.followedPerformers.isEmpty
                           ? nil : store.followedPerformers.count) {
                if !store.followedPerformers.isEmpty {
                    seeAll(.following)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, store.followedPerformers.isEmpty ? 6 : 12)

            if store.followedPerformers.isEmpty {
                Text(FollowedPerformerRow.emptyNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 0) {
                    let shown = Array(store.followedPerformers.prefix(Self.cardLimit))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, performer in
                        FollowedPerformerRow(performer: performer, showsDivider: index > 0)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .glassPanel()
    }

    /// The way into the whole of a list the card only samples. It stands there
    /// whenever the list has anything in it, short one included: the full
    /// screen is where a list is worked on — reordered, opened, unfollowed —
    /// and that has to be reachable without waiting for a sixth row to arrive.
    private func seeAll(_ list: MeList) -> some View {
        NavigationLink(value: list) { SeeAllLabel() }
            .buttonStyle(.plain)
    }
}

#Preview {
    MeView()
        .environment(EventStore.preview)
        .environment(FollowedDates.preview)
        .environment(VenueRegions.preview)
}
