import SwiftUI

/// Where the halls in the library are on the map, pushed from Settings.
///
/// Its own screen rather than two rows on the main one: both are about one
/// thing — how a hall is placed — and neither is something a reader changes
/// often. The switch decides whether a hall Maps could not place may be
/// narrowed from its block to its building (see ``VenueBuildings``); the
/// refresh is the one way to ask about every hall at once (see
/// ``VenuePlaces/refresh(_:)``).
struct VenueLocationsView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 0) {
                Toggle(isOn: $store.preciseVenuesEnabled) {
                    SettingRowLabel("scope", "Precise Venue Locations")
                }
                .settingRowPadding()

                SettingRowDivider()

                refreshRow
            }
            .glassPanel(interactive: true)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .washBackground()
        .navigationTitle("Venue Locations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var refreshRow: some View {
        Button {
            Task {
                guard !store.isRefreshingVenues else { return }
                await store.refreshVenues()
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

#Preview {
    NavigationStack {
        VenueLocationsView()
    }
    .environment(EventStore.preview)
}
