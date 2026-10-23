import SwiftUI

/// How a venue page was reached, and so how much the app already knows about
/// the hall it is opening.
///
/// The two entry points publish different amounts, exactly as they do for a
/// performer: an event whose own page has been imported carries the site's
/// place id, while everything read from a listing row has the hall's name and
/// nothing else — no address, no id.
nonisolated enum VenueLink: Hashable {
    /// From an event that carries Eventernote's place id, which addresses the
    /// hall's page directly.
    case place(PlaceListing)
    /// From a listing row. The page behind the name has to be found first.
    case named(String)

    var name: String {
        switch self {
        case .place(let listing): listing.name
        case .named(let name): name
        }
    }
}

nonisolated extension Event {
    /// The way to this event's hall: by the place id where the event's own
    /// page has been imported, and by the name alone otherwise — which the
    /// hall's page is found by, the way a billed performer's is.
    var venueLink: VenueLink {
        if let placeID {
            .place(PlaceListing(id: placeID, name: venue))
        } else {
            .named(venue)
        }
    }
}

/// One hall: what Eventernote publishes about the place, everything held there,
/// and how much of it the reader has been to.
///
/// The same shape as ``PerformerView``, because it is the same listing read the
/// same way (``ListingRead``, ``ListingSections``): `/places/{id}/events` runs
/// from the furthest published date backwards, as a performer's does.
///
/// The one thing a performer's page has not got is the map. Eventernote
/// publishes no photograph of a hall either, but it does publish the address —
/// and a map drawn from that says where the place is rather than standing in
/// for a picture of it.
struct VenueView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.openURL) private var openURL

    let link: VenueLink

    @State private var listing: ListingRead<VenueProfile>
    @State private var openEvent: Event?
    /// How the hall's lookup came out, with the question it answered (see
    /// ``mapKey``). Nil until the first comes back.
    @State private var mapLookup: (key: String, answer: VenuePlaces.Lookup)?
    /// Raised by the map's Try Again, which asks the same question again.
    @State private var mapAttempts = 0
    /// When the page was last refreshed by hand, so the flyers on it are asked
    /// about again with the rows — see ``EnvironmentValues/imagesCheckedSince``.
    @State private var imagesCheckedSince: Date?

    init(link: VenueLink) {
        self.link = link
        _listing = State(initialValue: ListingRead(
            cacheKey: link.cacheKey,
            resolve: { known in try await Self.resolve(link, known: known) },
            listing: { venue, page in
                try await EventernoteClient.shared.events(atVenue: venue.id, page: page)
            }))
    }

    private var profile: VenueProfile? { listing.subject }

    /// Whose listing this is, for the screens and headings shared with a
    /// performer's page.
    private var subject: ListingSubject { .venue(link.name) }

    var body: some View {
        ListingPage(subject: subject, listing: listing, openEvent: $openEvent,
                    imagesCheckedSince: imagesCheckedSince) {
            subtitle
        } found: {
            placeCard
            tipsCard
            ListingSections(subject: subject, listing: listing, openEvent: $openEvent)
        }
        .toolbar { actionBar }
        // Asked once the hall's own page has come back, because the address on
        // it is what places a hall — and asked again if either half of the
        // question ever changes.
        .task(id: MapQuestion(key: mapKey, attempt: mapAttempts)) { await placeOnMap() }
    }

    /// What the hall's lookup is asked from: the hall, and how many times the
    /// reader has asked again.
    private struct MapQuestion: Equatable {
        let key: String?
        let attempt: Int
    }

    /// Reads the hall's own page: nil where the site files no hall under the
    /// name the page was opened with.
    ///
    /// Read again on every refresh rather than kept from the first, which is
    /// where this differs from a performer: the address, the capacity and the
    /// walk from the station are all on the hall's page, and members edit
    /// them. Only the search that turned a name into an id is not repeated —
    /// a hall a page has already found stays found.
    nonisolated private static func resolve(_ link: VenueLink, known: VenueProfile?) async throws -> VenueProfile? {
        let id: Int
        if let known {
            id = known.id
        } else {
            switch link {
            case .place(let listing):
                id = listing.id
            case .named(let name):
                guard let found = try await EventernoteClient.shared.venue(named: name) else { return nil }
                id = found.id
            }
        }
        return try await EventernoteClient.shared.venue(id: id)
    }

    /// What a lookup is actually asking about, and nil while there is nothing
    /// to ask — the same pair ``VenuePlaces`` keys its kept answers by, so a
    /// hall the reader has already opened an event at is answered at once.
    private var mapKey: String? {
        profile.map { "\($0.name)\n\($0.address ?? "")" }
    }

    private func placeOnMap() async {
        guard let profile, let key = mapKey else { return }
        let found = await VenuePlaces.shared.lookUp(venue: profile.name, address: profile.address)
        // A refresh that changed the address asks again, and the answer for
        // the old one, landing after it, would draw over it.
        guard !Task.isCancelled else { return }
        mapLookup = (key, found)
    }

    /// Where Maps says the hall is — the last placing to come back, kept while
    /// the hall is asked about again. Nil until one does, and for a hall
    /// nobody has.
    private var place: VenuePlaces.Placing? {
        mapLookup?.answer.placing
    }

    /// What the map draws: the lookup's answer, but only for the question
    /// being asked now. A placing from before a refresh changed the address is
    /// still drawn until the new answer lands; any other answer from then
    /// reads as still looking.
    private var shownLookup: VenuePlaces.Lookup? {
        guard let mapLookup else { return nil }
        guard mapLookup.key == mapKey else { return place.map(VenuePlaces.Lookup.placed) }
        return mapLookup.answer
    }

    // MARK: - Where it is

    @ViewBuilder
    private var subtitle: some View {
        switch listing.lookup {
        case .looking:
            Text("Looking this venue up on Eventernote…")
        case .unlisted, .failed:
            // What went wrong is said under the header, where it can be acted on.
            EmptyView()
        case .found(let profile):
            // An imported address, printed as the site printed it.
            if let address = profile.address {
                Text(verbatim: address)
            }
        }
    }

    // MARK: - Actions

    /// What the reader can do with the hall, in a bar along the bottom of the
    /// page as an event's sheet has one: the way there, the page shared, and —
    /// in a ⋯ menu, as on the sheet — the page opened on Eventernote or read
    /// again. One capsule at the leading edge, with the space beside it left
    /// empty for the page to show through.
    ///
    /// Only once the hall's page is found: a name the site files no hall
    /// under has no page to share or open.
    @ToolbarContentBuilder
    private var actionBar: some ToolbarContent {
        if let profile {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    VenueDirections.open(profile.name, at: place, directions: true, with: openURL)
                } label: {
                    Label("Directions", systemImage: "location.fill")
                }
                .tint(.brandTint)

                ShareLink(item: profile.pageURL)
                    .tint(.brandTint)

                // Everything in the bar as well, as the sheet's menu has it, so
                // the menu is the whole of what can be done here — in the
                // sheet's groups: where it is and passing it on, then the page
                // it was read from.
                Menu {
                    Button {
                        VenueDirections.open(profile.name, at: place, directions: true, with: openURL)
                    } label: {
                        Label("Directions", systemImage: "location.fill")
                    }
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

    // MARK: - What the hall publishes about itself

    @ViewBuilder
    private var placeCard: some View {
        if let profile {
            VStack(spacing: 0) {
                VenueMap(venue: profile.name, lookup: shownLookup) {
                    VenueDirections.open(profile.name, at: place, directions: false, with: openURL)
                } retry: {
                    mapLookup = nil
                    mapAttempts += 1
                }
                // Only the map is clipped, and only where the card's own
                // corners are: the card's panel rounds the rest.
                .clipShape(.rect(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                 bottomTrailingRadius: 0, topTrailingRadius: 28,
                                 style: .continuous))

                VStack(spacing: 0) {
                    if let address = profile.address {
                        fact(icon: "mappin.and.ellipse", label: "Address", value: address)
                    }
                    if let capacity = profile.capacity {
                        fact(icon: "person.2.fill", label: "Capacity", value: capacity)
                    }
                    if let phone = profile.phone {
                        // Dialled rather than read: a hall's number is only
                        // ever wanted on the day, in a hurry.
                        fact(icon: "phone.fill", label: "Phone", value: phone,
                             destination: Self.dialURL(for: phone))
                    }
                    if let website = profile.website {
                        fact(icon: "safari", label: "Official site", value: website.host() ?? website.absoluteString,
                             destination: website)
                    }
                    if let chart = profile.seatingChart {
                        fact(icon: "chair.lounge.fill", label: "Seating chart",
                             value: String(localized: "Published by the venue"), destination: chart)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 6)
            }
            .panel(cornerRadius: 28)
            .padding(.horizontal, 18)
        }
    }

    /// The number to dial for what the hall's page publishes as its phone,
    /// or nil where it holds none. Members type it, often in full-width
    /// figures — ０３－３２１６－０５５５, which a `tel:` link carried as
    /// percent-escapes no phone dials — and now and then as 非公開.
    nonisolated static func dialURL(for phone: String) -> URL? {
        let halfwidth = phone.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? phone
        let number = String(halfwidth.filter { $0.isASCII && ($0.isNumber || $0 == "+") })
        guard number.filter(\.isNumber).count >= 6 else { return nil }
        return URL(string: "tel:\(number)")
    }

    /// One published fact about the hall, and where tapping it goes when the
    /// fact is somewhere rather than something.
    @ViewBuilder
    private func fact(
        icon: String, label: LocalizedStringKey, value: String, destination: URL? = nil
    ) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: icon)
                .scalingFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.brandTint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .scalingFont(size: 11, weight: .medium)
                    .foregroundStyle(.tertiary)
                // Imported text, printed as Eventernote printed it.
                Text(verbatim: value)
                    .scalingFont(size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if destination != nil {
                Image(systemName: "arrow.up.right")
                    .scalingFont(size: 11, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(.rect)

        if let destination {
            Link(destination: destination) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// 会場TIPS: the exits, the walking times and what to know on the day,
    /// written by the site's own members rather than by the hall.
    @ViewBuilder
    private var tipsCard: some View {
        if let tips = profile?.tips {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Getting there")
                Text(verbatim: tips)
                    .scalingFont(size: 13)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(17)
            .panel(cornerRadius: 28)
            .padding(.horizontal, 18)
        }
    }
}

#Preview {
    NavigationStack {
        VenueView(link: .place(PlaceListing(id: 3, name: "日本武道館")))
    }
    .library(EventStore.preview)
}
