import SwiftUI

/// The reader's own library at a glance: what it holds, when it was last
/// imported, and where it is kept.
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

    /// Eventrail reads Eventernote's public pages and nothing else. There is no
    /// account behind this screen, and the card has to say so rather than imply
    /// a profile the app has not got.
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
                Text("My library")
                    .font(.system(size: 16, weight: .semibold))
                Text("^[\(store.library.count) event](inflect: true) · ^[\(store.favoriteEvents.count) favorite](inflect: true)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.trackTicket)
                        .frame(width: 6, height: 6)
                    Text("No Eventernote account — read only")
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

    /// Re-imports every event in the library from its public page. Only imported
    /// fields are replaced; notes, interest, tickets and attendance are not.
    private var refreshCard: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last refreshed")
                    .font(.system(size: 14, weight: .semibold))
                refreshDetail
                    .font(.system(size: 12))
                    .foregroundStyle(store.refreshFailure == nil ? .secondary : Color.favorite)
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
            .disabled(store.isRefreshing || store.library.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .glassPanel()
    }

    /// The honest wording: the app reports when it last *succeeded*, never that
    /// the data is current.
    private var refreshDetail: Text {
        if store.isRefreshing {
            Text("Re-importing ^[\(store.library.count) event](inflect: true)…")
        } else if let failure = store.refreshFailure {
            Text(verbatim: failure)
        } else if let lastRefreshed = store.lastRefreshed {
            Text("Events re-imported \(lastRefreshed, format: .relative(presentation: .named))")
        } else if store.library.isEmpty {
            Text("Add events from Search to fill your library")
        } else {
            Text("Never re-imported")
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

    private func settingsCard(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: store.iCloudSyncEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Sync")
                        .font(.system(size: 14, weight: .semibold))
                    syncDetail
                        .font(.system(size: 11.5))
                        .foregroundStyle(syncNeedsAttention ? Color.favorite : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if self.store.iCloudSyncEnabled, self.store.cloudUsage > 0.8 {
                quotaMeter
            }

            settingsRow("Export library", value: "CSV · JSON")
            settingsRow("Language", value: "System")
            settingsRow("About Eventrail", value: nil)
        }
        .glassPanel()
    }

    /// Anything the reader has to act on is said in the colour used for
    /// attention, not buried in the same grey as the ordinary case.
    private var syncNeedsAttention: Bool {
        guard store.iCloudSyncEnabled, let status = store.syncStatus else { return false }
        return status != .synced
    }

    /// What syncing is actually doing right now — never a claim that it worked
    /// when it did not.
    private var syncDetail: Text {
        guard store.iCloudSyncEnabled else {
            return Text("This device only — nothing leaves it")
        }
        switch store.syncStatus {
        case .signedOut:
            return Text("Sign in to iCloud in Settings to sync this library")
        case .tooLarge(let bytes):
            return Text("Library is too large to sync (\(bytes.formatted(.byteCount(style: .file))))")
        case .failed(let reason):
            return Text(verbatim: reason)
        case .synced, .none:
            if let lastSynced = store.lastSynced {
                return Text("Events, notes and tracking synced \(lastSynced, format: .relative(presentation: .named))")
            }
            return Text("Your events, notes and tracking sync privately")
        }
    }

    /// iCloud's key-value storage has a fixed ceiling, and a library that grows
    /// past it stops syncing silently. The reader gets the warning before that.
    private var quotaMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: min(store.cloudUsage, 1))
                .tint(store.cloudUsage >= 1 ? Color.favorite : Color.trackTicket)
            Text("\(Int(store.cloudUsage * 100))% of the space iCloud allows for this library")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
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
        Text("Your notes, interest, ticket status and attendance belong to you. They stay on this device and, with iCloud Sync on, in your own private iCloud — there is no app-operated backend. Event details come from publicly accessible Eventernote pages and are never written back. Eventrail is not affiliated with Eventernote.")
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
        .environment(EventStore.preview)
}
