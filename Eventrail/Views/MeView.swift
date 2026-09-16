import SwiftUI

/// The associated public profile, library statistics, and the controls over
/// where the reader's own records live.
struct MeView: View {
    @Environment(EventStore.self) private var store

    @State private var openEvent: Event?

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    statistics
                    refreshCard
                    favoritesCard
                    settingsCard(store: $store)
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .washBackground()
            .navigationTitle("Me")
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(store.profileHandle)
                    .font(.system(size: 16, weight: .semibold))
                Text("Public profile imported · ^[\(store.listedParticipations) participation](inflect: true)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // A username is not a login: the import proves nothing about
                // who owns the account, and the interface has to say so.
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.trackTicket)
                        .frame(width: 6, height: 6)
                    Text("Unverified — read only")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.trackTicket)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .glassCapsule()
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .glassPanel(cornerRadius: 28)
    }

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

    private var refreshCard: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last refreshed")
                    .font(.system(size: 14, weight: .semibold))
                refreshDetail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .glassPanel()
    }

    /// The honest wording: the app reports when it last *succeeded*, never that
    /// the data is current.
    private var refreshDetail: Text {
        if store.isRefreshing {
            Text("Importing public profile…")
        } else if let lastRefreshed = store.lastRefreshed {
            Text("Public profile imported \(lastRefreshed, format: .relative(presentation: .named))")
        } else {
            Text("Never imported")
        }
    }

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

    private func favoriteRow(_ event: Event, isFirst: Bool) -> some View {
        Button {
            openEvent = event
        } label: {
            HStack(spacing: 12) {
                FlyerThumbnail(width: 38, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("\(event.dayLine) · \(event.venue)")
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

    private func settingsCard(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: store.iCloudSyncEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Sync")
                        .font(.system(size: 14, weight: .semibold))
                    Text(store.wrappedValue.iCloudSyncEnabled
                         ? "Notes, tracking and settings sync privately"
                         : "This device only — nothing leaves it")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            settingsRow("Backup & Restore", value: "Last backup 3 days ago")
            settingsRow("Export library", value: "CSV · JSON")
            settingsRow("Language", value: "System")
            settingsRow("About Eventrail", value: nil)
        }
        .glassPanel()
    }

    private func settingsRow(_ label: LocalizedStringKey, value: LocalizedStringKey?) -> some View {
        Button {
            // Destinations for these land with the persistence layer.
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Divider().padding(.leading, 16)
        }
    }

    private var footnote: some View {
        Text("Your notes, interest, ticket status and attendance live on this device and in your private iCloud. Eventrail is not affiliated with Eventernote.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

#Preview {
    MeView()
        .environment(EventStore())
}
