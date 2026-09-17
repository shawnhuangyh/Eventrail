import SwiftUI

/// Where the library is kept, and how to empty it.
///
/// Both switches here decide where the reader's own records go, so they stand
/// together under one heading. Everything destructive is at the bottom, well
/// away from the Refresh button on the screen behind.
struct SettingsView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDeleteAll = false

    /// Shown beside About, from the bundle rather than written down here, so a
    /// released build cannot claim a version it is not.
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("Sync")
                    syncCard(store: $store)

                    sectionHeader("About")
                        .padding(.top, 6)
                    aboutRow
                    deleteAllButton
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .washBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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

    private func sectionHeader(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.35)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
    }

    // MARK: - Where the reader's records go

    private func syncCard(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: store.calendarSyncEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar Sync")
                        .font(.system(size: 14, weight: .semibold))
                    calendarDetail
                        .font(.system(size: 11.5))
                        .foregroundStyle(calendarNeedsAttention ? Color.favorite : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
            .overlay(alignment: .top) {
                Divider().padding(.leading, 16)
            }

            if self.store.iCloudSyncEnabled, self.store.cloudUsage > 0.8 {
                quotaMeter
            }
        }
        .glassPanel()
    }

    /// The line says exactly what the mirror writes, past events included — a
    /// calendar that filled up with more than the reader expected is one they
    /// turn off and never trust again.
    private var calendarDetail: Text {
        guard store.calendarSyncEnabled else {
            return Text("Off — nothing is written to your calendar")
        }
        switch store.calendarStatus {
        case .denied:
            return Text("Allow calendar access in Settings to add your events")
        case .failed(let reason):
            return Text(verbatim: reason)
        case .mirrored, .none:
            return Text("Every event in your library is added to your calendar, past and upcoming")
        }
    }

    private var calendarNeedsAttention: Bool {
        guard store.calendarSyncEnabled, let status = store.calendarStatus else { return false }
        if case .mirrored = status { return false }
        return true
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

    // MARK: - About

    private var aboutRow: some View {
        Button {
            // The destination lands with the About screen.
        } label: {
            HStack(spacing: 12) {
                Text("About Eventrail")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "Version \(version)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
    }

    // MARK: - Emptying the library

    private var deleteAllButton: some View {
        Button {
            isConfirmingDeleteAll = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                Text("Delete All Events")
                    .font(.system(size: 14.5, weight: .semibold))
            }
            .foregroundStyle(Color.favorite)
            .frame(maxWidth: .infinity)
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
        .disabled(store.library.isEmpty && store.favoriteEvents.isEmpty)
        .padding(.top, 6)
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

    private var footnote: some View {
        Text("Your notes, interest, ticket status and attendance belong to you. They stay on this device and, with iCloud Sync on, in your own private iCloud — there is no app-operated backend. Event details come from publicly accessible Eventernote pages and are never written back. Eventrail is not affiliated with Eventernote.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
    }
}

#Preview {
    SettingsView()
        .environment(EventStore.preview)
}
