import SwiftUI

/// Where the library is kept, and how to empty it.
///
/// Two headings, because the switches answer two different questions. Calendar
/// Sync decides what Eventrail writes into a diary the reader keeps elsewhere;
/// Data decides where the reader's own records live. Everything destructive is
/// at the bottom, well away from the Refresh button on the screen behind.
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
                    sectionHeader("Calendar")
                    calendarCard(store: $store)

                    sectionHeader("Data")
                        .padding(.top, 6)
                    iCloudCard(store: $store)

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

    // MARK: - What Eventrail writes to the calendar

    private func calendarCard(store: Bindable<EventStore>) -> some View {
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
        .glassPanel()
    }

    // MARK: - Where the reader's records go

    private func iCloudCard(store: Bindable<EventStore>) -> some View {
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
        .disabled(!store.hasRecordsToDelete)
        .padding(.top, 6)
        // Asked from the button rather than from the screen, so the sheet
        // points at what opened it.
        .confirmationDialog("Delete every event?", isPresented: $isConfirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete All Events", role: .destructive) { store.removeAllEvents() }
            Button("Cancel", role: .cancel) {}
        } message: {
            deleteAllDetail
        }
    }

    /// Says what actually goes: the favorites the reader would otherwise be left
    /// staring at, and the records they wrote themselves — which, unlike the
    /// events, no refresh brings back.
    /// Spelled out rather than inflected, for the reason ``EventsView``'s own
    /// removal gives: a dialog's words reach UIKit as plain text, and the
    /// `^[…](inflect:)` markup arrives there unprocessed.
    private var deleteAllDetail: Text {
        let events = store.library.count
        let favorites = store.favoriteEvents.count
        let what = events == 1 ? Text("1 event") : Text("\(events) events")
        let all: Text = switch favorites {
        case 0: what
        case 1: Text("\(what) and 1 favorite")
        default: Text("\(what) and \(favorites) favorites")
        }
        return Text("\(all) will go from this device and from your other devices, along with every note, interest, ticket status and attendance you recorded. Anything your Eventernote account still lists comes back on the next refresh, but what you wrote does not; the rest you can add again from Search.")
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
