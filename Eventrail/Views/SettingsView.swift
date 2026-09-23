import SwiftUI

/// Where the library is kept, and how to empty it.
///
/// Four headings, because the rows answer four different questions. Calendar
/// decides what Eventrail writes into a diary the reader keeps elsewhere;
/// Location is where its events are on the map, which the calendar wants and
/// so does every event's own sheet; Data decides where what this app holds
/// lives — the reader's own records on their devices through iCloud and in a
/// file they hold themselves, and beneath those the pages it has read from
/// Eventernote and kept; About is the app itself. Everything destructive is at the
/// bottom, well away from the Refresh button on the screen behind.
///
/// One card per heading, so the shape on the glass says the same thing the
/// heading does: rows that share a card share a question. Delete All is the
/// exception and sits outside the About card on its own — a row that empties
/// the library has no business sharing a shape with a row that opens a version
/// number.
///
/// Every row reads the same way — an icon in the gutter, what it is, and a
/// line underneath saying what it is doing *now* rather than what it would do
/// in general. That line is the whole point of the screen: a toggle that says
/// only "iCloud Sync" cannot tell the reader it has been failing for a week.
struct SettingsView: View {
    @Environment(EventStore.self) private var store
    /// The two things read from Eventernote and kept on this device rather
    /// than in the library — what the cache row empties.
    @Environment(FollowedDates.self) private var followed
    @Environment(VenueRegions.self) private var venues
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDeleteAll = false
    @State private var isChoosingBackup = false
    /// The backup file waiting for the share sheet, rewritten on every change.
    @State private var exported: URL?
    /// The welcome, asked for again. Its own state rather than the flag
    /// ``RootView`` watches: replaying it is not un-launching the app, and a
    /// device that has seen it has still seen it.
    @State private var isReplayingWelcome = false
    /// How many flyers and pictures are kept on this device. Counted when the
    /// screen opens rather than watched: ``ImageCache`` is an actor, and a
    /// count that is a second out of date on a Settings row is no loss.
    @State private var imageCount = 0

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
                    SectionLabel(label: "Calendar")
                    calendarCard(store: $store)

                    SectionLabel(label: "Location")
                        .padding(.top, 6)
                    locationCard(store: $store)

                    SectionLabel(label: "Data")
                        .padding(.top, 6)
                    dataCard(store: $store)

                    SectionLabel(label: "About")
                        .padding(.top, 6)
                    aboutCard
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
            .fullScreenCover(isPresented: $isReplayingWelcome) {
                WelcomeView()
            }
        }
        // A sheet over the root, so it draws its own — the venue refresh
        // below would otherwise report behind it.
        .refreshNotices()
    }

    // MARK: - One row's face

    /// The shape every row on this screen takes: an icon, a name, the line
    /// underneath, and whatever the row puts on the right — a switch, a
    /// spinner, a version number.
    ///
    /// One helper rather than a shape per row, so a toggle and a button that
    /// sit in the same card line up down to the pixel: the icons share a
    /// gutter of the same width whether or not a row has anything to put in
    /// it, which is what keeps the titles on one left edge.
    ///
    /// The padding is left to the caller, because it belongs to whatever is
    /// tappable — the whole `Toggle` for a switch, the label alone inside a
    /// `Button`.
    private func rowLabel<Trailing: View>(
        _ symbol: String,
        _ title: LocalizedStringKey,
        _ detail: Text?,
        needsAttention: Bool = false,
        tint: Color = .secondary,
        titleTint: Color = .primary,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(titleTint)
                if let detail {
                    detail
                        .font(.system(size: 11.5))
                        .foregroundStyle(needsAttention ? Color.favorite : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    /// The hairline between two rows of one card, inset past the icon gutter
    /// so it starts under the text rather than cutting the icons off.
    ///
    /// A sibling in the stack rather than something laid over the row beneath
    /// it: an overlay renders at the mercy of whatever the row is made of, and
    /// went missing over the one row here built from a `ShareLink`.
    private var rowDivider: some View {
        Divider().padding(.leading, 48)
    }

    // MARK: - What Eventrail writes to the calendar

    /// One switch, and nothing happens until it is flipped.
    ///
    /// Off until the reader turns it on — see ``EventStore/calendarSyncEnabled``.
    /// Nothing on this screen asks for calendar access on the way in; the
    /// system's permission sheet is the answer to the switch, which is the
    /// only place the reader has said they want their diary written to.
    private func calendarCard(store: Bindable<EventStore>) -> some View {
        Toggle(isOn: store.calendarSyncEnabled) {
            rowLabel("calendar", "Calendar Sync", calendarDetail,
                     needsAttention: calendarNeedsAttention)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel()
    }

    /// The line says exactly what the mirror writes, past events included — a
    /// calendar that filled up with more than the reader expected is one they
    /// turn off and never trust again.
    private var calendarDetail: Text {
        guard store.calendarSyncEnabled else {
            return Text("Off — nothing is written to your calendar, and nothing asks for access to it")
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

    // MARK: - Where the events are

    /// Its own heading rather than a second row under Calendar.
    ///
    /// Where a hall is is not a calendar setting: it is what draws the map on
    /// an event's own sheet, and what Maps opens when the reader taps it,
    /// whether or not they ever write a thing to their diary. The calendar is
    /// one of the things a placed hall mends, and the line underneath says so
    /// — but only while the mirror is on, because promising a calendar entry
    /// to someone who has not asked for one is how a screen starts lying.
    /// Whether a hall Maps could not place may be narrowed from its block to
    /// its building — see ``VenueBuildings`` for why that is a separate
    /// question and a separate service.
    private func locationCard(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            preciseVenuesRow(store: store)
            rowDivider
            venueRefreshRow
        }
        .glassPanel(interactive: true)
    }

    private func preciseVenuesRow(store: Bindable<EventStore>) -> some View {
        Toggle(isOn: store.preciseVenuesEnabled) {
            rowLabel("scope", "Precise Venue Locations",
                     Text("Where Apple Maps has no such hall, ask OpenStreetMap which building at the published address it is."))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var venueRefreshRow: some View {
        Button {
            Task {
                guard !store.isRefreshingVenues else { return }
                await store.refreshVenues()
                if let notice = RefreshNotice.venues(store.venueStatus) { notices?.post(notice) }
            }
        } label: {
            rowLabel("mappin.and.ellipse", "Refresh Venue Locations", venueDetail,
                     needsAttention: venueNeedsAttention) {
                if store.isRefreshingVenues {
                    ProgressView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshingVenues || !store.hasVenuesToPlace)
    }

    /// What the refresh is doing, and then what it found — never a bare
    /// "done", because a run that placed nothing is worth saying out loud.
    private var venueDetail: Text {
        switch store.venueStatus {
        case .asking(let done, let of) where of > 0:
            return Text("Asking Maps — \(done) of \(of) venues")
        case .asking:
            return Text("Asking Maps about your venues…")
        case .refreshed(let found, let of):
            let placed = Text("Placed \(found) of \(of) venues on the map")
            guard store.calendarSyncEnabled else { return placed }
            return Text("\(placed), and wrote them to your calendar")
        case .failed(let reason):
            return Text(verbatim: reason)
        case .none:
            guard store.calendarSyncEnabled else {
                return Text("Looks up every venue again, so each event's map is the one Maps has now. This takes a while.")
            }
            return Text("Looks up every venue again, and writes the ones it finds into your calendar. This takes a while.")
        }
    }

    private var venueNeedsAttention: Bool {
        if case .failed = store.venueStatus { return true }
        return false
    }

    // MARK: - Where the reader's records go

    /// One card, because the rows answer one question — where what this app
    /// holds lives. The first three are the reader's own records, in three
    /// places: on their other devices, in a file they keep, and back off one.
    /// Sync keeps devices agreeing, which means a removal travels too; a file
    /// is the one copy nothing done in the app afterwards can reach.
    ///
    /// The last is the other half of what is on the device and belongs to
    /// nobody — pages read from Eventernote, kept only so they are not asked
    /// for again. It sits under the same heading because it answers the same
    /// question, and it is the one row here that takes something away without
    /// the reader losing anything by it.
    private func dataCard(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            iCloudRow(store: store)
            rowDivider
            exportRow
            rowDivider
            restoreRow
            rowDivider
            cacheRow
        }
        .glassPanel(interactive: true)
        // Written before the share sheet is opened rather than when it asks for
        // the file. Handed a file that exists, the system composes the preview
        // the reader already knows from every other app — its name, its kind
        // and its icon — where a `Transferable` leaves that to this screen,
        // which has no business drawing a file.
        .task(id: self.store.revision) { await prepareExport() }
        .choosingBackup($isChoosingBackup)
    }

    private func iCloudRow(store: Bindable<EventStore>) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: store.iCloudSyncEnabled) {
                rowLabel("icloud", "iCloud Sync", syncDetail,
                         needsAttention: syncNeedsAttention)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
        case .accountChanged:
            return Text("This device signed in to a different iCloud account — turn sync on again to use it")
        case .rejected:
            return Text("iCloud would not take this library just now — it will be tried again")
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

    // MARK: - The copy the reader keeps

    @ViewBuilder private var exportRow: some View {
        let row = rowLabel("square.and.arrow.up", "Export Backup",
                           Text("Save your events, notes and tracking as a file you keep"))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
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
            rowLabel("square.and.arrow.down", "Restore from Backup",
                     Text("Puts back what a backup holds and this device no longer does. Nothing here is erased."))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - What was read from Eventernote

    /// Empties what this device has read and kept: the dates published for the
    /// performers the reader follows, which of their event pages have already
    /// been read, every performer's and hall's page opened, every flyer
    /// downloaded, and which part of the country each hall is in.
    ///
    /// None of it is the reader's — every one of them is a fact this device
    /// went and read, written down so opening a screen does not read it again
    /// for a while. So
    /// there is nothing to confirm and nothing to lose: the screens go back
    /// for whatever they still need, which is the whole of what this changes.
    ///
    /// Where a hall *is* — its pin, its map, its clock — is deliberately not
    /// in here. That one is answered by Maps and two donated services rather
    /// than by Eventernote, a hall does not move, and rebuilding it is a run
    /// of hundreds of searches. Its own row is above, under Location.
    private var cacheRow: some View {
        Button {
            followed.clear()
            venues.clear()
            store.forgetReadPages()
            ListingCache.shared.clear()
            imageCount = 0
            Task { await ImageCache.shared.clear() }
        } label: {
            rowLabel("clock.arrow.circlepath", "Clear Cache", cacheDetail)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(cachedItems == 0)
        .task { imageCount = await ImageCache.shared.count() }
    }

    /// How much is being held, item by item rather than as a size on disk: a
    /// reader deciding whether to clear this wants to know what it is, and
    /// "1.2 MB" does not say.
    private var cachedItems: Int {
        followed.performerCount + store.readPageCount + ListingCache.shared.count
            + imageCount + venues.placedCount
    }

    /// Named one by one, and only the ones there are any of: a device that has
    /// refreshed but follows nobody would otherwise read "0 followed listings"
    /// at the head of the line it is trying to explain.
    private var cacheDetail: Text {
        var parts: [Text] = []
        if followed.performerCount > 0 {
            parts.append(Text("^[\(followed.performerCount) followed listing](inflect: true)"))
        }
        if store.readPageCount > 0 {
            parts.append(Text("^[\(store.readPageCount) event page](inflect: true)"))
        }
        if ListingCache.shared.count > 0 {
            parts.append(Text("^[\(ListingCache.shared.count) performer or venue page](inflect: true)"))
        }
        if imageCount > 0 {
            parts.append(Text("^[\(imageCount) image](inflect: true)"))
        }
        if venues.placedCount > 0 {
            parts.append(Text("^[\(venues.placedCount) venue area](inflect: true)"))
        }
        guard let first = parts.first else {
            return Text("Nothing is kept — pages are read from Eventernote as they are needed")
        }
        let held = parts.dropFirst().reduce(first) { Text("\($0), \($1)") }
        return Text("Holding \(held). Each is read again by itself once it is more than six hours old.")
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

    // MARK: - About

    /// About and the welcome, which are one card and not two: both say what
    /// the app is rather than change what it does. Delete All stays outside
    /// it, alone — a row that empties the library has no business sharing a
    /// shape with a row that opens a version number.
    private var aboutCard: some View {
        VStack(spacing: 0) {
            aboutRow
            rowDivider
            welcomeRow
        }
        .glassPanel(interactive: true)
    }

    /// The first-launch screen, on request.
    ///
    /// Under About rather than beside it: it is not a setting, it is the four
    /// questions this screen already answers, asked the way a new reader is
    /// asked them. Both answers still only take effect at its Done.
    private var welcomeRow: some View {
        Button {
            isReplayingWelcome = true
        } label: {
            rowLabel("hand.wave", "Welcome Screen", nil) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var aboutRow: some View {
        NavigationLink {
            AboutView()
        } label: {
            rowLabel("info.circle", "About Eventrail", nil) {
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
    }

    // MARK: - Emptying the library

    /// The one row that reads in the attention colour rather than wearing it
    /// only when something has gone wrong: it is the only thing on this screen
    /// that takes something away.
    private var deleteAllButton: some View {
        Button {
            isConfirmingDeleteAll = true
        } label: {
            rowLabel("trash", "Delete All Events",
                     Text("Empties this device and your other devices"),
                     tint: .favorite, titleTint: .favorite)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
        return Text("\(all) will go from this device and from your other devices, along with everything you wrote on them — your notes, your seats, and what the tickets cost. Anything your Eventernote account still lists comes back on the next refresh, but what you wrote does not; the rest you can add again from Search.")
    }

    private var footnote: some View {
        Footnote(Text("What you write on an event — a note, a seat, what it cost — belongs to you. It stays on this device and, with iCloud Sync on, in your own private iCloud — there is no app-operated backend. A backup you export goes only where you send it. Event details come from publicly accessible Eventernote pages and are never written back. Eventrail is not affiliated with Eventernote."))
            .padding(.horizontal, 8)
            .padding(.top, 6)
    }
}

#Preview {
    SettingsView()
        .environment(EventStore.preview)
        .environment(FollowedDates.preview)
        .environment(VenueRegions.preview)
}
