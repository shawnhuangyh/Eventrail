import SwiftUI

/// Where the halls in the library are on the map, pushed from Settings.
///
/// Its own screen rather than two rows on the main one: both are about one
/// thing — how a hall is placed — and neither is something a reader changes
/// often. The switch decides whether a hall Maps could not place may be
/// narrowed from its block to its building (see ``VenueBuildings``); the
/// refresh is the one way to ask about every hall at once (see
/// ``VenuePlaces/refresh(_:)``).
///
/// Above them, the one place in Settings that says how something works: the
/// three answers a hall can be placed by, in the order they are asked, each
/// with how many of the reader's halls it placed — opened by why the switch
/// is there, and that outside mainland China it needs no attention. The switch only makes sense once the
/// reader knows it governs the third of three, and the counts are what tell
/// them whether a refresh is worth running.
struct VenueLocationsView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    /// Whether a refresh asks about the halls Apple Maps already placed as
    /// well. Per device and off by default: those answers are the building
    /// already, and asking again is most of a refresh's minutes.
    @AppStorage("venueRefreshIncludesMaps") private var refreshIncludesMaps = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(label: "Why This Setting")
                why

                SectionLabel(label: "How Halls Are Placed")
                    .padding(.top, 22)
                steps

                SectionLabel(label: "Options")
                    .padding(.top, 22)
                VStack(spacing: 0) {
                    Toggle(isOn: $store.preciseVenuesEnabled) {
                        SettingRowLabel("scope", "Refine with OpenStreetMap")
                    }
                    .settingRowPadding()

                    SettingRowDivider()

                    Toggle(isOn: $refreshIncludesMaps) {
                        SettingRowLabel("map", "Refresh All Venues")
                    }
                    .settingRowPadding()
                    .disabled(store.isRefreshingVenues)

                    SettingRowDivider()

                    refreshRow
                }
                .glassPanel(interactive: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .washBackground()
        .navigationTitle("Venue Locations")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The three answers in the order they are asked, and what is left over.
    /// Counted over the halls behind the library and the favourites — the same
    /// set a refresh asks about.
    private var steps: some View {
        let breakdown = store.venueBreakdown
        return VStack(spacing: 0) {
            PlacingStep(
                "map", "Apple Maps", count: breakdown.maps,
                detail: "Searched first, by the hall's name. Places the building."
            )
            SettingRowDivider()
            PlacingStep(
                "building.columns", "GSI Address Search", count: breakdown.register,
                detail: "Used when Maps finds nothing. Places the block."
            )
            SettingRowDivider()
            PlacingStep(
                "scope", "OpenStreetMap", count: breakdown.openStreetMap,
                detail: "Narrows a block to its building, while Refine with OpenStreetMap is on. In mainland China it also places halls outside Japan and the mainland, whatever the switch says."
            )
            SettingRowDivider()
            PlacingStep(
                "mappin.slash", "Not Placed Yet", count: breakdown.unplaced,
                detail: "Shown by name until one of the three finds it."
            )
        }
        .glassPanel()
    }

    /// Why the switch is here at all, said before anything else: outside
    /// mainland China it needs no attention, and inside it the third answer
    /// is what most halls in Japan end up needing, because MapKit there is
    /// served by a provider that carries next to no halls abroad — see
    /// ``VenuePlaces``.
    private var why: some View {
        VStack(spacing: 0) {
            PlacingStep(
                "globe.asia.australia", "Outside Mainland China",
                detail: "Apple Maps is asked first and places nearly every hall. Nothing on this screen needs changing."
            )
            SettingRowDivider()
            PlacingStep(
                "exclamationmark.triangle", "In Mainland China",
                detail: "Apple Maps is served by a local provider that carries few venues outside the mainland, so a search for a hall in Japan often finds nothing. Such a hall falls through to the address register, which places only its block; turn on Refine with OpenStreetMap to narrow that to the building."
            )
            SettingRowDivider()
            PlacingStep(
                "airplane", "After Leaving Mainland China",
                detail: "Halls placed while you were there keep the block or building they were given. Refresh Venue Locations once you are elsewhere, and Apple Maps is asked for them again."
            )
        }
        .glassPanel()
    }

    private var refreshRow: some View {
        Button {
            Task {
                guard !store.isRefreshingVenues else { return }
                await store.refreshVenues(includingMaps: refreshIncludesMaps)
                if let notice = RefreshNotice.venues(store.venueStatus) {
                    notices?.report(notice, byHand: true)
                }
            }
        } label: {
            SettingRowLabel("mappin.and.ellipse", "Refresh Venue Locations",
                            status: status, needsAttention: needsAttention) {
                if store.isRefreshingVenues {
                    ProgressView()
                }
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshingVenues || !store.hasVenuesToPlace)
    }

    /// Progress while it runs, and a failure if it ends in one. A run that
    /// finished is reported by the notice along the bottom, not here as well.
    private var status: Text? {
        switch store.venueStatus {
        case .asking(let done, let of) where of > 0:
            Text("\(done) of \(of)")
        case .failed(let reason):
            Text(verbatim: reason)
        default:
            nil
        }
    }

    private var needsAttention: Bool {
        if case .failed = store.venueStatus { return true }
        return false
    }
}

/// One of the answers a hall can be placed by: the settings row's icon gutter
/// and name, how many halls it placed on the right, and what it does under.
/// The Why card draws its two cases the same way, with no count.
private struct PlacingStep: View {
    let symbol: String
    let title: LocalizedStringKey
    /// How many halls it placed; nil on a row that explains rather than counts.
    var count: Int?
    let detail: LocalizedStringKey

    init(_ symbol: String, _ title: LocalizedStringKey, count: Int? = nil, detail: LocalizedStringKey) {
        self.symbol = symbol
        self.title = title
        self.count = count
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRowLabel(symbol, title) {
                if let count {
                    SettingRowValue(Text(count, format: .number))
                }
            }
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}


#Preview {
    NavigationStack {
        VenueLocationsView()
    }
    .environment(EventStore.preview)
}
