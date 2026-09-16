import SwiftUI

/// The reader's own library at a glance: what it holds, when it was last
/// imported, and where it is kept.
struct MeView: View {
    @Environment(EventStore.self) private var store

    @State private var openEvent: Event?
    @State private var isLinking = false
    @State private var isConfirmingUnlink = false
    @State private var isConfirmingDeleteAll = false

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) { settingsMenu }
            }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event)
            }
            .sheet(isPresented: $isLinking) {
                EventernoteAccountSheet()
            }
            .confirmationDialog("Unlink this Eventernote account?",
                                isPresented: $isConfirmingUnlink, titleVisibility: .visible) {
                Button("Unlink", role: .destructive) { store.unlinkAccount() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("The events already imported stay in your library.")
            }
            .confirmationDialog("Delete every event?", isPresented: $isConfirmingDeleteAll,
                                titleVisibility: .visible) {
                Button("Delete All Events", role: .destructive) { store.removeAllEvents() }
                Button("Cancel", role: .cancel) {}
            } message: {
                deleteAllDetail
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
                    accountBadge
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

    // MARK: - Keeping the library current

    /// The one thing this screen asks Eventernote for.
    ///
    /// Refreshing and importing an account were two buttons until it became
    /// clear they are one intention: bring the library up to date from
    /// Eventernote. With an account linked, Refresh reads its history too;
    /// without one there is nothing to import, so nothing extra is offered.
    /// The account itself is a row underneath rather than a second button.
    private var refreshCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    refreshTitle
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
                .disabled(store.isRefreshing || nothingToRefresh)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)

            if let fraction = refreshFraction {
                ProgressView(value: fraction)
                    .tint(Color.trackTicket)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if store.eventernoteHandle == nil {
                accountRow("Link Eventernote Account") { isLinking = true }
            } else {
                accountRow("Change Account") { isLinking = true }
                accountRow("Unlink Account") { isConfirmingUnlink = true }
            }
        }
        .glassPanel()
    }

    /// An empty library with no account named has nothing to ask about.
    private var nothingToRefresh: Bool {
        store.library.isEmpty && store.eventernoteHandle == nil
    }

    private var refreshTitle: Text {
        if let handle = store.eventernoteHandle {
            Text(verbatim: "@\(handle)")
        } else {
            Text("Last refreshed")
        }
    }

    /// The honest wording: the app reports when it last *succeeded*, never that
    /// the data is current.
    private var refreshDetail: Text {
        if store.isRefreshing {
            return workingDetail
        }
        // Counts and a short fall belong on the same line: "it worked" and "it
        // only got this far" are both true of a partial import.
        if let summary = store.importSummary {
            let counts = Text("Imported ^[\(summary.read) event](inflect: true) — \(summary.added) added, \(summary.filled) updated")
            guard let failure = store.refreshFailure else { return counts }
            return counts + Text(verbatim: " ") + Text(verbatim: failure)
        }
        if let failure = store.refreshFailure {
            return Text(verbatim: failure)
        }
        if let lastRefreshed = store.lastRefreshed {
            return Text("Refreshed \(lastRefreshed, format: .relative(presentation: .named))")
        }
        if nothingToRefresh {
            return Text("Add events from Search, or link your Eventernote account")
        }
        return Text("Never refreshed")
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

    /// The settings this screen keeps out of the way. Destructive work lives
    /// here rather than in the cards, where it would be one stray tap from the
    /// Refresh button beside it.
    private var settingsMenu: some View {
        Menu {
            Button("Delete All Events", systemImage: "trash", role: .destructive) {
                isConfirmingDeleteAll = true
            }
            .disabled(store.library.isEmpty && store.favoriteEvents.isEmpty)
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }

    /// Says what actually goes, including the favorites the reader would
    /// otherwise be left staring at.
    private var deleteAllDetail: Text {
        let events = Text("^[\(store.library.count) event](inflect: true)")
        guard !store.favoriteEvents.isEmpty else {
            return events + Text(" will be removed from this device and from your other devices. You can add them again from Search.")
        }
        return events + Text(" and ^[\(store.favoriteEvents.count) favorite](inflect: true) will be removed from this device and from your other devices. You can add them again from Search.")
    }

    /// The badge says what the app is reading, and never more than that: even
    /// with an account named, this is one public page being read, not a login.
    private var accountBadge: Text {
        if let handle = store.eventernoteHandle {
            Text("Reading @\(handle) — read only")
        } else {
            Text("No Eventernote account — read only")
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

            settingsRow("About Eventrail")
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
        case .notConfigured:
            return Text("This build cannot use iCloud yet — it needs the iCloud capability enabled for the app")
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

    private func settingsRow(_ label: LocalizedStringKey) -> some View {
        Button {
            // The destination lands with the About screen.
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
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
