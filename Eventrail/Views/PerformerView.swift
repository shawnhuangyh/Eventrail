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
/// and how much of it the reader has been to — read and laid out as a hall's
/// page is (``ListingRead``, ``ListingSections``).
///
/// There is deliberately no picture at the top. Eventernote publishes no
/// portrait of a performer, and the flyer for what they are billed on is the
/// artwork for an event rather than a likeness of them — so the page opens on
/// the name instead of dressing one up as the other.
struct PerformerView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    let link: PerformerLink

    @State private var listing: ListingRead<PerformerProfile>
    @State private var openEvent: Event?
    /// When the page was last refreshed by hand, so the flyers on it are asked
    /// about again with the rows — see ``EnvironmentValues/imagesCheckedSince``.
    @State private var imagesCheckedSince: Date?

    init(link: PerformerLink) {
        self.link = link
        _listing = State(initialValue: ListingRead(
            cacheKey: link.cacheKey,
            // A performer found stays found: their page is the listing.
            resolve: { known in
                if let known { return known }
                return try await Self.resolve(link)
            },
            listing: { profile, page in
                try await EventernoteClient.shared.events(forPerformer: profile, page: page)
            }))
    }

    private var profile: PerformerProfile? { listing.subject }

    /// Whose listing this is, for the screens and headings that are shared with
    /// a hall's page.
    private var subject: ListingSubject { .performer(link.name) }

    var body: some View {
        ListingPage(subject: subject, listing: listing, openEvent: $openEvent,
                    imagesCheckedSince: imagesCheckedSince) {
            subtitle
        } found: {
            ListingSections(subject: subject, listing: listing, openEvent: $openEvent)
        }
        .toolbar { actionBar }
    }

    /// Turns whatever the page was opened with into a profile: nil where the
    /// site lists nobody under exactly the billed name.
    nonisolated private static func resolve(_ link: PerformerLink) async throws -> PerformerProfile? {
        switch link {
        case .profile(let profile): profile
        case .billed(let name): try await EventernoteClient.shared.performer(named: name)
        }
    }

    // MARK: - Who they are

    @ViewBuilder
    private var subtitle: some View {
        switch listing.lookup {
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

    // MARK: - Actions

    /// What the reader can do with the performer, in a bar along the bottom
    /// of the page as an event's sheet has one: follow them, share the page,
    /// and — in a ⋯ menu, as on the sheet — open it on Eventernote or read it
    /// again. One capsule at the leading edge, with the space beside it left
    /// empty for the page to show through.
    ///
    /// Only once the page behind the name is found: a name the site files
    /// nobody under has nothing to follow, share or open.
    @ToolbarContentBuilder
    private var actionBar: some ToolbarContent {
        if let profile {
            let isFollowing = store.isFollowing(profile)
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    withAnimation(.snappy) { store.toggleFollow(profile) }
                } label: {
                    Label(isFollowing ? "Unfollow" : "Follow",
                          systemImage: isFollowing ? "checkmark" : "plus")
                        .contentTransition(.symbolEffect(.replace))
                }
                .tint(isFollowing ? .trackAttended : .brandTint)

                ShareLink(item: profile.pageURL)
                    .tint(.brandTint)

                // Everything in the bar as well, as the sheet's menu has it, so
                // the menu is the whole of what can be done here — in the
                // sheet's groups: the reader's own, passing it on, and the
                // page it was read from.
                Menu {
                    Button {
                        withAnimation(.snappy) { store.toggleFollow(profile) }
                    } label: {
                        Label(isFollowing ? "Unfollow" : "Follow",
                              systemImage: isFollowing ? "checkmark" : "plus")
                    }

                    Divider()

                    ShareLink(item: profile.pageURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    EventernotePageItems(page: profile.pageURL, isRefreshing: listing.isRefreshing) {
                        imagesCheckedSince = .now
                        Task { await listing.refresh(byHand: true, store: store, notices: notices) }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuOrder(.fixed)
                .tint(.brandTint)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }
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
    .library(EventStore.preview)
}
