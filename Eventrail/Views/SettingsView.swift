import SwiftUI

/// Where the library is kept, and how to empty it.
///
/// General is what a reader sets once and lives with — the language, light or
/// dark, and the two switches that carry the library somewhere else of theirs
/// (their other devices and their calendar). Backup is the copy they keep
/// themselves. Advanced is what most readers never touch: how halls are
/// placed, on a screen of its own, and the pages kept from Eventernote, which
/// are nobody's record and so stay off the cards holding the reader's own.
/// About is the app itself. Delete All sits alone under Danger Zone at the
/// bottom, well away from the Refresh button on the screen behind.
///
/// Every row is an icon, a name and a control, and nothing else. A row speaks up
/// underneath only when there is something to say *now* — a sync that failed,
/// a refresh halfway through, access the system refused — because a line that
/// says the same thing every time the screen opens is one the reader learns to
/// skip, and then skips on the day it changes. The names are meant to say
/// what each row does; where one cannot, the welcome screen is where it is
/// sold.
struct SettingsView: View {
    @Environment(EventStore.self) private var store
    /// The two things read from Eventernote and kept on this device rather
    /// than in the library — what the cache row empties.
    @Environment(FollowedDates.self) private var followed
    @Environment(VenueRegions.self) private var venues
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDeleteAll = false
    @State private var isChoosingBackup = false
    /// The backup file waiting for the share sheet, rewritten on every change.
    @State private var exported: URL?
    /// The welcome, asked for again. Its own state rather than the flag
    /// ``RootView`` watches: replaying it is not un-launching the app, and a
    /// device that has seen it has still seen it.
    @State private var isReplayingWelcome = false
    /// Whether the cache has been emptied since this screen opened — the row's
    /// only answer, since what it empties is not the reader's to count.
    @State private var cacheCleared = false
    /// Per-device — see ``Appearance``.
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    /// Shown beside About, from the bundle rather than written down here, so a
    /// released build cannot claim a version it is not.
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("General") {
                        languageRow
                        SettingRowDivider()
                        appearanceRow
                        SettingRowDivider()
                        iCloudRow(store: $store)
                        SettingRowDivider()
                        calendarRow(store: $store)
                    }
                    section("Backup") {
                        exportRow
                        SettingRowDivider()
                        restoreRow
                    }
                    // Written before the share sheet is opened rather than when
                    // it asks for the file. Handed a file that exists, the
                    // system composes the preview the reader already knows from
                    // every other app — its name, its kind and its icon.
                    .task(id: store.revision) { await prepareExport() }
                    .choosingBackup($isChoosingBackup)

                    section("Advanced") {
                        venueLocationsRow
                        SettingRowDivider()
                        cacheRow
                    }
                    section("About") {
                        aboutRow
                        SettingRowDivider()
                        welcomeRow
                    }
                    section("Danger Zone") {
                        deleteAllButton
                    }
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
            .fullScreenCover(isPresented: $isReplayingWelcome) {
                WelcomeView()
            }
        }
        // A sheet over the root, so it draws its own — the venue refresh on
        // the screen pushed from Advanced would otherwise report behind it.
        .refreshNotices()
    }

    // MARK: - The shape of the screen

    /// A heading and the one glass card under it. Rows that share a card share
    /// a question.
    private func section<Rows: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label: title)
                .padding(.top, 14)
            VStack(spacing: 0, content: rows)
                .glassPanel(interactive: true)
        }
    }

    // MARK: - General

    /// How the app looks and speaks on this device, and the two switches that
    /// carry the library somewhere else of the reader's: their other devices,
    /// and their calendar.

    /// The app's language and the one descriptions are translated into, on a
    /// screen of their own — see ``LanguageSettingsView``. Just a chevron:
    /// with two answers behind it, naming one here would say only half.
    private var languageRow: some View {
        NavigationLink {
            LanguageSettingsView()
        } label: {
            SettingRowLabel("globe", "Language") {
                SettingRowChevron()
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
    }

    private static let systemSettings = URL(string: UIApplication.openSettingsURLString)!

    /// System, Light or Dark, chosen on the row itself rather than on a
    /// screen of its own — three answers need no more room than that.
    ///
    /// A segmented control rather than a menu: on iOS 26 a menu opened from
    /// a row grows out of the glass card holding it, and the whole General
    /// card vanished for as long as the menu was open.
    private var appearanceRow: some View {
        SettingRowLabel("circle.lefthalf.filled", "Appearance") {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .settingRowPadding()
        // Here rather than in `MyApp`, where it would belong: an `onChange`
        // on the app's own `@AppStorage` fired for the first change and not
        // for the ones after it, and the window kept whichever came first.
        .onChange(of: appearance) { appearance.apply() }
    }

    private func iCloudRow(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: store.iCloudSyncEnabled) {
                SettingRowLabel("icloud", "iCloud Sync",
                         status: syncStatus, needsAttention: syncNeedsAttention)
            }
            .settingRowPadding()

            if self.store.iCloudSyncEnabled, self.store.cloudUsage > 0.8 {
                quotaMeter
            }
        }
    }

    /// Anything the reader has to act on is said in the colour used for
    /// attention, not buried in the same grey as the ordinary case.
    private var syncNeedsAttention: Bool {
        guard store.iCloudSyncEnabled, let status = store.syncStatus else { return false }
        return status != .synced
    }

    /// What syncing is doing right now, in as few words as will say it — never
    /// a claim that it worked when it did not. Silent while it is off.
    private var syncStatus: Text? {
        guard store.iCloudSyncEnabled else { return nil }
        switch store.syncStatus {
        case .notConfigured:
            return Text("iCloud is not available in this build")
        case .signedOut:
            return Text("Sign in to iCloud to sync")
        case .accountChanged:
            return Text("iCloud account changed — turn on again to sync")
        case .rejected:
            return Text("iCloud refused the library — will retry")
        case .tooLarge(let bytes):
            return Text("Too large to sync (\(bytes.formatted(.byteCount(style: .file))))")
        case .failed(let reason):
            return Text(verbatim: reason)
        case .synced, .none:
            guard let lastSynced = store.lastSynced else { return nil }
            return Text("Synced \(lastSynced, format: .relative(presentation: .named))")
        }
    }

    /// iCloud's key-value storage has a fixed ceiling, and a library that grows
    /// past it stops syncing silently. The reader gets the warning before that.
    private var quotaMeter: some View {
        HStack(spacing: 10) {
            ProgressView(value: min(store.cloudUsage, 1))
                .tint(store.cloudUsage >= 1 ? Color.favorite : Color.trackTicket)
            Text(min(store.cloudUsage, 1), format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 48)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iCloud storage used")
    }

    /// Off until the reader turns it on — see ``EventStore/calendarSyncEnabled``.
    /// Nothing on this screen asks for calendar access on the way in; the
    /// system's permission sheet is the answer to the switch.
    private func calendarRow(store: Bindable<EventStore>) -> some View {
        Toggle(isOn: store.calendarSyncEnabled) {
            SettingRowLabel("calendar", "Calendar Sync",
                     status: calendarStatus, needsAttention: true) {
                if calendarDenied {
                    Link("Open Settings", destination: Self.systemSettings)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.brandTint)
                        .buttonStyle(.plain)
                }
            }
        }
        .settingRowPadding()
    }

    /// Only what needs the reader: a mirror that is working says nothing.
    /// With the switch off the one thing left to say is that the calendar it
    /// made could not be taken out again.
    private var calendarStatus: Text? {
        guard store.calendarSyncEnabled else {
            if case .failed(let reason) = store.calendarStatus { return Text(verbatim: reason) }
            return nil
        }
        switch store.calendarStatus {
        case .denied:
            return Text("Calendar access is off in Settings")
        case .failed(let reason):
            return Text(verbatim: reason)
        case .mirrored, .none:
            return nil
        }
    }

    /// Denied is the one failure the reader can mend from here, so the row
    /// carries the way to the switch that mends it.
    private var calendarDenied: Bool {
        guard store.calendarSyncEnabled, case .denied = store.calendarStatus else { return false }
        return true
    }

    // MARK: - Backup

    @ViewBuilder private var exportRow: some View {
        let row = SettingRowLabel("square.and.arrow.up", "Export Backup")
            .settingRowPadding()
        if let exported {
            ShareLink(item: exported) { row }
                .buttonStyle(.plain)
        } else {
            // The moment before the file is on disk. Dimmed rather than
            // removed, so the card does not change height under a thumb.
            row.opacity(0.4)
        }
    }

    private var restoreRow: some View {
        Button {
            isChoosingBackup = true
        } label: {
            SettingRowLabel("square.and.arrow.down", "Restore from Backup",
                            status: unreadableLibraryStatus, needsAttention: true)
                .settingRowPadding()
        }
        .buttonStyle(.plain)
    }

    /// The one time the library on screen is known to be missing something:
    /// a file this build could not read, kept aside for a build that can.
    private var unreadableLibraryStatus: Text? {
        guard store.unreadableLibraryFiles > 0 else { return nil }
        return Text("Part of your library could not be read and was set aside. Restore a backup, or update the app.")
    }

    /// Writes the file the share sheet will hand over.
    ///
    /// Off the main actor: encoding and compressing a large library is real
    /// work, and Settings should not stutter open because of it. Run again
    /// whenever the reader changes anything, so what leaves is never the
    /// library as it stood when this screen opened.
    private func prepareExport() async {
        let backup = store.backup
        exported = await Task.detached { try? backup.write() }.value
    }

    // MARK: - Advanced

    /// The switch and the refresh that decide how halls are placed, on a
    /// screen of their own — see ``VenueLocationsView``. A run under way shows
    /// here too, so leaving that screen does not hide it.
    private var venueLocationsRow: some View {
        NavigationLink {
            VenueLocationsView()
        } label: {
            SettingRowLabel("map", "Venue Locations") {
                if store.isRefreshingVenues {
                    ProgressView()
                }
                SettingRowChevron()
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
    }

    /// Empties what this device has read from Eventernote and kept: the
    /// followed performers' dates, which event pages have been read, every
    /// performer's and hall's page, every flyer, and which area each hall is in.
    ///
    /// None of it is the reader's, so there is nothing to confirm and nothing
    /// to count — the screens go back for whatever they still need. Where a
    /// hall *is* is deliberately not in here: rebuilding it is a run of
    /// hundreds of searches, and it has its own screen under Advanced.
    private var cacheRow: some View {
        Button {
            followed.clear()
            venues.clear()
            store.forgetReadPages()
            ListingCache.shared.clear()
            Task { await ImageCache.shared.clear() }
            withAnimation(.snappy) { cacheCleared = true }
        } label: {
            SettingRowLabel("clock.arrow.circlepath", "Clear Cache") {
                if cacheCleared {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.trackAttended)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
        .disabled(cacheCleared)
        .sensoryFeedback(.success, trigger: cacheCleared) { _, cleared in cleared }
    }

    // MARK: - About

    private var aboutRow: some View {
        NavigationLink {
            AboutView()
        } label: {
            SettingRowLabel("info.circle", "About Eventrail") {
                SettingRowValue(Text(verbatim: version), accessory: "chevron.right")
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
    }

    /// The first-launch screen, on request. Both answers still only take effect
    /// at its Done.
    private var welcomeRow: some View {
        Button {
            isReplayingWelcome = true
        } label: {
            SettingRowLabel("hand.wave", "Welcome Screen") {
                SettingRowChevron()
            }
            .settingRowPadding()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Emptying the library

    /// Alone, and in the attention colour: it is the only thing on this
    /// screen that takes something away. What goes is said in the confirmation
    /// rather than on the button.
    private var deleteAllButton: some View {
        Button {
            isConfirmingDeleteAll = true
        } label: {
            SettingRowLabel("trash", "Delete All Events", tint: .favorite, titleTint: .favorite)
                .settingRowPadding()
        }
        .buttonStyle(.plain)
        .disabled(!store.hasRecordsToDelete)
        .opacity(store.hasRecordsToDelete ? 1 : 0.4)
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

    /// Says what actually goes, and what does not come back.
    ///
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
        return Text("\(all) will go from this device and from your other devices, along with everything you wrote on them — your notes, your seats, and what the tickets cost. Anything your Eventernote account still lists comes back on the next refresh, but what you wrote does not; the rest you can add again from Search.")
    }
}

#Preview {
    SettingsView()
        .environment(EventStore.preview)
        .environment(FollowedDates.preview)
        .environment(VenueRegions.preview)
}
