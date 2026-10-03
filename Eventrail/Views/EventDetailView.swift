import SwiftUI
import Photos
import QuickLook
import Translation

/// One event: what Eventernote publishes about it, and what the reader records
/// about it. The two are kept visually distinct throughout.
///
/// Laid out as `Eventrail v3.dc.html` draws it: the flyer small beside the
/// title, the night's own clock in a card of its own, the reader's record as
/// two tiles that open ``TicketDetailsView``, then the page's description,
/// billing, hall and links — and the actions in a bar along the bottom.
///
/// A sheet opened from a search row starts with only what the row printed, and
/// imports the event's own page for the rest.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    /// Where this sheet starts; ``clockChoice`` is where the reader took it.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    /// The other clock, where the reader picked it on this sheet's switch —
    /// for as long as the sheet is open, and never written back to Settings.
    /// Nil follows Settings. See ``clock``.
    @State private var clockChoice: TimeDisplay?
    @Namespace private var clockSwitchSpace
    @Environment(\.colorScheme) private var colorScheme

    private let source: Event
    @State private var isImporting = false
    /// Why the page could not be read again just now, if it could not. The
    /// sheet goes on showing the copy it had, with this under it.
    @State private var importFailure: String?
    /// When this sheet last read its page, so the flyer is asked about again
    /// with it — see ``readPage()``.
    @State private var imagesCheckedSince: Date?
    /// Whether the description is shown whole. Collapsed to begin with, for the
    /// reason ``summaryCard`` gives.
    @State private var isSummaryExpanded = false
    /// Whether ``TicketDetailsView`` is up over this sheet.
    @State private var isEditingTicket = false
    /// What has been pushed onto this sheet's stack — a performer, a hall. The
    /// refresh notices are drawn above the action bar while nothing is, and
    /// over the whole stack once something is; see ``body``.
    @State private var path = NavigationPath()

    /// The description in the app's own language, the text it was made from
    /// and the target it was made for — so a page read again with a different
    /// description is not shown under a translation of the old one, and a
    /// target changed in Settings (another window, on an iPad) is not shown in
    /// the language it replaced. Held for this sheet only: a translation is a
    /// way of reading the page, not something the reader owns.
    @State private var translatedSummary: (source: String, target: String, text: String)?
    /// Whether the card shows ``translatedSummary`` rather than the original.
    @State private var showsTranslation = false
    /// Handed to `translationTask`; setting or invalidating it starts a run.
    @State private var translationRequest: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var translationFailed = false
    /// Whether this device can translate Japanese into ``translationTarget`` at
    /// all. Settled as the card appears, so the button is never offered for a
    /// pair the system does not support.
    @State private var canTranslate = false
    /// Per device — see ``TranslationTarget``.
    @AppStorage(TranslationTarget.storageKey) private var translationTargetID = ""

    /// Where Maps says the hall is. Nil until the lookup comes back, and for a
    /// hall Maps has never heard of.
    @State private var place: VenuePlaces.Placing?

    /// Why the Live Activity could not be started, while that is being said.
    @State private var liveActivityFailure: String?
    #if DEBUG
    /// The Live Activity bench is up — see ``LiveActivityTestView``.
    @State private var isTestingLiveActivity = false
    #endif

    /// The flyer as a file Quick Look and the share sheet can be handed —
    /// see ``ImageCache/file(for:named:checkedSince:)``. Nil until it is
    /// written, and for an event with no flyer.
    @State private var flyerFile: URL?
    /// The file Quick Look is showing, while it is.
    @State private var previewedFlyer: URL?
    /// Counted up as each save lands, for the tap that says so.
    @State private var flyerSaves = 0
    @State private var flyerSaveFailure: FlyerSaveFailure?

    /// Why the flyer did not reach the reader's photos.
    private enum FlyerSaveFailure {
        /// The reader has said no, here or in Settings.
        case notAllowed
        case failed(String)
    }

    /// What ``flyerFile`` is written from: the flyer, the title it is named
    /// for, and the last refresh by hand it has to be as fresh as.
    private struct FlyerLoad: Equatable {
        let url: URL?
        let name: String
        let checkedSince: Date?
    }

    @Environment(\.openURL) private var openURL

    init(event: Event) {
        source = event
    }

    /// The fullest copy the app holds. An import lands in the store, so reading
    /// it back keeps this sheet and the lists behind it showing the same event.
    private var event: Event {
        store.event(id: source.id) ?? source
    }

    private var tracking: Tracking {
        store.tracking(for: event)
    }

    /// Whether there is anywhere to go. Eventernote announces plenty of events
    /// before it has booked a hall, and nothing is offered for those.
    private var hasVenue: Bool {
        !event.venue.isEmpty || place != nil
    }

    /// What a lookup is actually asking about. The sheet asks again whenever
    /// this changes: an event opened from a search row carries the hall's name
    /// and no address until its own page is imported, and that address is often
    /// what finally places a hall Maps does not answer to by name.
    private var venueKey: String {
        "\(event.venue)\n\(event.publishedAddress ?? "")"
    }

    /// Opens Maps on the hall this event is at — see ``VenueDirections``.
    private func openVenueInMaps(directions: Bool) {
        VenueDirections.open(event.venue, at: place, directions: directions, with: openURL)
    }

    var body: some View {
        // A stack of its own, so a performer billed here — or the hall it is
        // held at — opens inside this sheet rather than dismissing it. The
        // sheet's own chrome is the close button and the action bar, so the
        // navigation bar stays hidden at the root and comes back — with its
        // back button — on whatever is pushed onto it.
        NavigationStack(path: $path) {
            detail
                .toolbar(.hidden, for: .navigationBar)
                .toolbar { actionBar }
                // Inside the stack at the root, so the notice stands above the
                // action bar rather than over it — the bar is part of the
                // root's safe area, and nothing here has to know its height.
                .refreshNotices(aboveBar: true, showing: path.isEmpty)
                .venueDestination()
        }
        // A performer's or a hall's page pushed here draws its own above its
        // bar; but the See All behind either has no bar and draws nothing, and
        // the root's notice went off screen with the root, so the stack draws
        // them there.
        .refreshNotices(showing: !path.isEmpty)
        .refreshNoticesInSheet()
        .presentationDragIndicator(.visible)
    }

    private var detail: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    timelineCard
                    // Only for an event the reader keeps. Tracking answers
                    // questions about a night they mean to be at — the ticket,
                    // the seat, what it cost — so on an event that is not in
                    // the library there is nothing for it to be about, and a
                    // date opened from Following or Search shows the facts
                    // alone until it is added. A removal keeps whatever was
                    // written, so re-adding brings the tiles back as they were.
                    if store.isInLibrary(event) { ticketTiles }
                    summaryCard
                    if !event.performers.isEmpty { performersCard }
                    venueCard
                    linksCard
                    if let importFailure {
                        RefreshFailureNote(message: importFailure)
                            .padding(.horizontal, 16)
                    }
                    footnote
                }
                // As wide as the sheet and no wider. A card's layout can come
                // out a hair over the width it was offered — the timeline card
                // measured 402.00000000000006 on a 402-point sheet, for one
                // event's times and not another's — and a stack any wider than
                // its scroll view let that sheet be dragged sideways as well as
                // up and down.
                .containerRelativeFrame(.horizontal)
                // Clear of the close button, which floats over the top of it.
                .padding(.top, 64)
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
            // The sheet's own, and not only for the sheets that had none. A
            // `.refreshable` is carried down the environment into whatever a
            // screen presents, so a sheet opened from the Following tab used
            // to answer a pull by re-reading every followed performer's
            // listing — and one opened from My Events, whose list has no
            // refresh, by doing nothing. Pulling on an event reads that event.
            .refreshable { await refreshPage() }

            closeButton
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .washBackground()
        .sheet(isPresented: $isEditingTicket) {
            TicketDetailsView(event: event)
        }
        #if DEBUG
        .sheet(isPresented: $isTestingLiveActivity) {
            LiveActivityTestView(event: event, seat: tracking.seat)
        }
        #endif
        .task { await importPage() }
        // A sheet left open while the reader was away is owed the same check
        // it made as it opened: past the window, it reads its page again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await importPage() } }
        }
        .environment(\.imagesCheckedSince, imagesCheckedSince)
        // A seat written, or a door time the page published, reaches the
        // event's Live Activity a moment later — not on every keystroke.
        .task(id: liveActivityKey) {
            guard liveActivity != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await EventActivities.shared.refresh(from: store)
        }
        .alert("Couldn't Start the Live Activity",
               isPresented: Binding { liveActivityFailure != nil } set: { if !$0 { liveActivityFailure = nil } },
               presenting: liveActivityFailure) { _ in
            Button("OK") {}
        } message: {
            Text(verbatim: $0)
        }
        // Over this sheet, rather than in its stack: the flyer is looked at
        // whole, the way the system shows any picture.
        .quickLookPreview($previewedFlyer)
        // Written again with the flyer, so the file opened is the picture on
        // the sheet — a pull asks the host about both at once.
        .task(id: FlyerLoad(url: event.imageURL, name: event.title, checkedSince: imagesCheckedSince)) {
            guard let url = event.imageURL else {
                flyerFile = nil
                return
            }
            flyerFile = await ImageCache.shared.file(for: url, named: event.title, checkedSince: imagesCheckedSince)
        }
        .sensoryFeedback(.success, trigger: flyerSaves)
        .alert("Couldn't Save the Flyer",
               isPresented: Binding { flyerSaveFailure != nil } set: { if !$0 { flyerSaveFailure = nil } },
               presenting: flyerSaveFailure) { failure in
            if case .notAllowed = failure {
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { failure in
            switch failure {
            case .notAllowed: Text("Eventrail isn't allowed to add to your photos. You can allow it in Settings.")
            case .failed(let reason): Text(verbatim: reason)
            }
        }
        // The first time an event at a hall nothing has looked up yet is
        // opened, this is what goes and finds it — whether or not the reader
        // mirrors anything to their calendar.
        .task(id: venueKey) { place = await VenuePlaces.shared.mapItem(for: event) }
    }

    /// Imports the event's own page for the times, billing, description and
    /// head count a search row does not carry — and reads it again when the
    /// copy held is stale.
    ///
    /// Asked of ``Event/isFullyDetailed`` rather than of `isDetailed`, so an
    /// event imported by a build that read less of the page than this one does
    /// is read again, once, the first time the reader opens it. And asked of
    /// ``EventStore/isStale(_:)``, so a sheet opened on a page this device read
    /// more than a few hours ago picks up a start time or a venue announced
    /// since, while one opened twice in an afternoon asks Eventernote nothing
    /// the second time.
    ///
    /// Whatever was held stays on screen while the page is read, and stays if
    /// it cannot be — the reason goes under it rather than over it.
    ///
    /// The app's own doing, so it says only a failure: an "Updated" over every
    /// event opened for the first time would be noise.
    private func importPage() async {
        guard !event.isFullyDetailed || store.isStale(event) else { return }
        await readPage(byHand: false)
    }

    /// Reads the event's own page again because the reader pulled for it —
    /// however recently it was read, since that is the reader asking. What is
    /// on screen stays if the page cannot be had, with the reason under it.
    private func refreshPage() async {
        await readPage(byHand: true)
    }

    /// The one read both of those make, and what it says when it is done: a
    /// notice — either way for a pull, only on failure otherwise — and on
    /// failure a line under the copy that stayed, which outlasts the notice
    /// since the reader is still looking at that copy after it has gone.
    private func readPage(byHand: Bool) async {
        isImporting = true
        defer { isImporting = false }
        let read = await store.reloadDetail(for: event)
        switch read {
        case .updated: importFailure = nil
        case .failed(let reason): importFailure = reason
        }
        notices?.report(.event(read), byHand: byHand)
        // The flyer is filed under the event's id, so a new one arrives under
        // the same address as the old — see ``ImageCache``. Asked about
        // whenever the page is, so the artwork never lags the page under it.
        imagesCheckedSince = .now
    }

    // MARK: - Header

    /// The flyer, and beside it what the night is called, when and where.
    ///
    /// The flyer at the size of a poster on a wall rather than across the
    /// width of the sheet: it is artwork for the event, and the sheet is read
    /// for the facts under it.
    private var header: some View {
        HStack(alignment: .top, spacing: 15) {
            poster

            VStack(alignment: .leading, spacing: 7) {
                Text(event.title)
                    .font(.system(size: 20, weight: .bold))
                    .kerning(-0.2)
                    .fixedSize(horizontal: false, vertical: true)
                // An already-formatted date, so it is shown as given rather
                // than as a localizable key. The day alone: the times are the
                // timeline's, a card below.
                Text(verbatim: shown.longDateLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                venueLine
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// Opens whole in Quick Look — the system's own viewer, zoomed with a
    /// pinch and closed with a swipe, whose share button saves and sends it —
    /// and on a long press offers the same as a menu over a larger copy.
    /// Neither until ``flyerFile`` is written: both are handed the file.
    private var poster: some View {
        Button {
            previewedFlyer = flyerFile
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    CachedImage(url: event.imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.microphone")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 76, height: 106)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let flyerFile {
                ShareLink(item: flyerFile)
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    Task { await saveFlyer(flyerFile) }
                }
            }
        } preview: {
            CachedImage(url: event.imageURL) { image in
                image.resizable().scaledToFit().frame(width: 300)
            } placeholder: {
                EmptyView()
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 8)
        .accessibilityLabel("Event flyer")
        .accessibilityHint(flyerFile == nil ? Text(verbatim: "") : Text("Opens the flyer"))
    }

    /// Adds the flyer to the reader's photos as the host sent it, asking for
    /// leave to add — and only to add — the first time.
    private func saveFlyer(_ file: URL) async {
        switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
        case .authorized, .limited:
            do {
                try await PHPhotoLibrary.shared().performChanges { @Sendable in
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil)
                }
                flyerSaves += 1
            } catch {
                flyerSaveFailure = .failed(error.localizedDescription)
            }
        default:
            flyerSaveFailure = .notAllowed
        }
    }

    /// The hall, as the way to everything else held there. An event announced
    /// before a hall was booked has no name to push, and says so.
    @ViewBuilder
    private var venueLine: some View {
        if event.venue.isEmpty {
            Text("Venue to be announced")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            NavigationLink(value: venueLink) {
                HStack(spacing: 4) {
                    Text(event.venue)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.brandTint)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the venue")
        }
    }

    /// The way out of the sheet.
    ///
    /// A glyph rather than the word Done, because nothing here is being
    /// confirmed: every answer on this sheet has already taken effect, and a
    /// button that says Done invites the reader to think something is being
    /// saved by pressing it — and that leaving another way would lose it.
    ///
    /// The label survives as the accessibility one. A close button with no
    /// name is a button VoiceOver can only call "x mark".
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassCircle(interactive: true)
        .accessibilityLabel("Close")
    }

    // MARK: - The event's clock

    /// The clock this sheet prints on: Settings › Time Zone, until the reader
    /// picks the other on the timeline card's switch.
    private var clock: TimeDisplay { clockChoice ?? timeDisplay }

    /// Picking the clock Settings already names goes back to following it, so
    /// a sheet switched there and back is no different from one never touched.
    private func choose(_ option: TimeDisplay) {
        clockChoice = option == timeDisplay ? nil : option
    }

    /// The event as it is printed on the chosen clock — see
    /// ``Event/shown(on:)``. Only ever formatted.
    private var shown: Event { event.shown(on: clock) }

    /// How far off the event is, its doors, start and end on one line, and how
    /// long it runs — and on the day itself, how far along it has got.
    ///
    /// Redrawn every second on the day, so the bars fill between the times as
    /// the event does. Any other day it only has to notice midnight.
    ///
    /// An em dash stands in for a time the public page does not carry — the
    /// app never fills one in itself.
    private var timelineCard: some View {
        let isToday = EventProgress(event: event, at: .now).isToday
        return TimelineView(.periodic(from: .now, by: isToday ? 1 : 60)) { context in
            timelineCard(EventProgress(event: event, at: context.date), at: context.date)
        }
    }

    private func timelineCard(_ progress: EventProgress, at now: Date) -> some View {
        let tint = tint(for: progress, at: now)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    statusDot(tint, pulsing: progress.isUnderway)
                    // Wraps rather than cutting off where the switch leaves it
                    // too little room: a countdown is no use with its end gone.
                    headline(for: progress, at: now)
                        .font(.system(size: 20, weight: .bold))
                        .kerning(-0.4)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // The offset and the switch on one baseline, so the two
                    // small lines read as one, and together centred on the
                    // headline's capitals rather than sitting on its baseline,
                    // as the dot before it is.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        clockOffset
                        clockSwitch
                    }
                    .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] + 3 }
                }
                if let detail = detail(for: progress, at: now) {
                    detail
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        // Under the words of the headline, not under its dot.
                        .padding(.leading, 17)
                }
            }
            .animation(.snappy, value: progress.phase)

            stopsRow(progress, tint: tint)

            HStack(spacing: 10) {
                Label { runLine } icon: { Image(systemName: "timer") }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                // The head count reads as a number needing a noun, so it says
                // where it was counted.
                if let listed = event.listedAttendees {
                    Label {
                        Text("\(listed.formatted()) going on Eventernote")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "person.2.fill")
                    }
                    .foregroundStyle(.tertiary)
                    // Whole on one line; the run time beside it gives way.
                    .fixedSize()
                }
            }
            .labelStyle(FooterLabelStyle())
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 13)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)
            }
        }
        .padding(18)
        // Tinted, faintly, while the event is under way: the one time the
        // card is about now rather than about a date.
        .glassBackground(in: .rect(cornerRadius: 28, style: .continuous),
                         tint: progress.isUnderway ? tint.opacity(0.1) : nil)
        .padding(.horizontal, 18)
    }

    /// Whether the event is still ahead, as ``Event/isUpcoming`` draws that
    /// line — the end of its day rather than of its show, the same line every
    /// list in the app draws. The ticket tile reads it; the timeline card
    /// reads the event's own times through ``EventProgress``.
    private var isAhead: Bool { event.isUpcoming }

    /// Whether there is a ticket to say anything about: a past event had one,
    /// and one still to come has one once the reader says it was bought.
    private var hasTicket: Bool { !isAhead || tracking.ticket == .purchased }

    /// The colour the card is in: amber while the event is to come, green
    /// with the doors open, orange in the last minutes before the start, the
    /// heart's red on stage — and once it is over, green if the reader kept
    /// it, since they went.
    private func tint(for progress: EventProgress, at now: Date) -> Color {
        switch progress.phase {
        case .ahead, .today, .beforeDoors, .beforeShow: .trackTicket
        case .doorsOpen(let starts):
            starts.timeIntervalSince(now) <= Self.startingSoon ? .orange : .trackAttended
        case .onNow: .favorite
        case .wrapped, .over: store.isInLibrary(event) ? .trackAttended : .secondary
        }
    }

    /// How close to the start the doors-open headline turns into "Starting in".
    private static let startingSoon: TimeInterval = 5 * 60

    /// What the card opens on: how far off the event is, where it has got to
    /// on the day, or — once the day is over — whether the reader went, which
    /// is whether it is in the library.
    private func headline(for progress: EventProgress, at now: Date) -> Text {
        switch progress.phase {
        case .ahead(1): Text("Tomorrow")
        case .ahead(let days): Text("^[In \(days) day](inflect: true)")
        case .today: Text("Today")
        case .beforeDoors(let doors): Text("Doors in \(Self.countdown(to: doors, from: now))")
        case .beforeShow(let starts): Text("Starts in \(Self.countdown(to: starts, from: now))")
        case .doorsOpen(let starts):
            starts.timeIntervalSince(now) <= Self.startingSoon
                ? Text("Starting in \(Self.countdown(to: starts, from: now))")
                : Text("Doors open")
        case .onNow: Text("On now")
        case .wrapped: Text("That's a wrap")
        case .over: store.isInLibrary(event) ? Text("Attended") : Text("Ended")
        }
    }

    /// The line under the headline on the day: what comes next, and when.
    private func detail(for progress: EventProgress, at now: Date) -> Text? {
        switch progress.phase {
        case .beforeDoors:
            return shown.timeLine.map { Text("Show starts at \($0)") }
        case .doorsOpen(let starts):
            return starts.timeIntervalSince(now) <= Self.startingSoon
                ? Text("Find your seat")
                : Text("Show in \(Self.countdown(to: starts, from: now))")
        case .onNow(let ends?):
            guard let endsLine = shown.endsLine else { return nil }
            return Text("\(Self.countdown(to: ends, from: now)) left · ends \(endsLine)")
        case .onNow(nil):
            return shown.timeLine.map { Text("Started at \($0)") }
        case .wrapped:
            return shown.endsLine.map { Text("Ended at \($0)") }
        default:
            return nil
        }
    }

    /// "1h 12m" to a moment later today, in whole minutes rounded up — so the
    /// last minute before the doors reads "1m" rather than "0m".
    private static func countdown(to moment: Date, from now: Date) -> String {
        let minutes = max(1, Int((moment.timeIntervalSince(now) / 60).rounded(.up)))
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// The dot before the headline, pulsing while the event is under way.
    private func statusDot(_ tint: Color, pulsing: Bool) -> some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 9))
            .foregroundStyle(tint)
            .symbolEffect(.pulse, options: .repeating, isActive: pulsing && !reduceMotion)
            // Centred on the headline's lower-case letters rather than sitting
            // on its baseline.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1.5 }
            .accessibilityHidden(true)
    }

    /// The offset of the clock this sheet's times are on, beside the switch
    /// that says which clock that is.
    ///
    /// On every sheet rather than only on the nights abroad. On the venue's
    /// clock the times are the hall's, as Eventernote's members wrote them —
    /// 18:00 is 18:00 at the door rather than 18:00 wherever the reader is
    /// standing — and that is as true of a Tokyo date as of a Taipei one.
    ///
    /// The offset rather than a place name, for the reason
    /// ``Event/offsetLine(in:)`` gives: the name would be the map provider's
    /// and the provider is the reader's, so a Taipei hall comes back named for
    /// the mainland. The hall is named on this same sheet; what the offset
    /// adds is which clock it keeps.
    @ViewBuilder private var clockOffset: some View {
        // On the reader's own clock the offset is always known: it is this
        // device's, on the night itself. On the venue's, only where there is
        // one to give — see ``venueZone``. Without it the switch alone says
        // the times are the hall's, which is all that is known.
        let zone = clock == .local ? TimeZone.current : venueZone
        if let zone {
            let offset = event.offsetLine(in: zone)
            Text(verbatim: offset)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .fixedSize()
                .accessibilityLabel(clock == .local
                    ? Text("Times shown in local time, \(offset)")
                    : Text("Times shown in the venue's own time, \(offset)"))
        }
    }

    /// Venue or Local: which clock this sheet prints on, for as long as it is
    /// open. It starts on Settings › Time Zone and goes back to it when the
    /// sheet closes — a way of reading this one night, not a preference, so
    /// it moves no other screen and not the Live Activity either.
    ///
    /// A capsule of its own rather than a segmented picker, as the design
    /// draws it: the system's control is too tall and too wide to sit beside
    /// the headline. VoiceOver is handed the picker it stands for.
    private var clockSwitch: some View {
        HStack(spacing: 2) {
            ForEach(TimeDisplay.allCases) { option in
                let isOn = clock == option
                Button {
                    withAnimation(.snappy) { choose(option) }
                } label: {
                    Text(option.shortLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isOn ? Color.primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : .white)
                                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "clock", in: clockSwitchSpace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: .capsule)
        .fixedSize()
        .accessibilityRepresentation {
            Picker("Time Zone", selection: Binding(get: { clock }, set: choose)) {
                ForEach(TimeDisplay.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        }
    }

    /// Which clock this sheet's times are on, where the app has established it
    /// rather than assumed it.
    ///
    /// Three answers, in order of how well they are known. The hall is placed
    /// and the placing carries the clock. Or it was placed on an earlier
    /// visit, and the store wrote that clock into the event itself — see
    /// ``Event/published(in:)``. Or Eventernote's own address opens with a
    /// Japanese prefecture, and Japan keeps one clock end to end, so no map
    /// service needs asking at all.
    ///
    /// Nil is the fourth answer and an honest one: a hall abroad that nothing
    /// has placed yet is on whatever clock its members wrote, and this app
    /// does not know which. It reads those times on Tokyo time because that is
    /// where every import starts, and printing GMT+9 under a Seoul date would
    /// be claiming an answer rather than having one. The caption then says
    /// which clock the times are on without saying what that clock is set to,
    /// which is exactly what is known. The sheet asks for its own hall the
    /// moment it opens, so this is usually a second rather than a state.
    private var venueZone: TimeZone? {
        if let placed = place?.timeZone { return placed }
        if event.timeZone != Event.publishedZone { return event.timeZone }
        if let address = event.publishedAddress, Region.containing(address: address) != nil {
            return Event.publishedZone
        }
        return nil
    }

    /// The doors, the start and the end on one line with a bar between each
    /// two, and what each is small over it — drawn as the Live Activity draws
    /// its times, so the sheet and the activity read the same. The first bar
    /// fills from the doors to the start, the second from the start to the
    /// end. An em dash stands in for a time the page does not carry.
    ///
    /// The names go over the times, as in the Dynamic Island, rather than
    /// beside them as on the Lock Screen: three times with a name beside each
    /// left the bars a couple of dashes. A twelve-hour clock's "10:30 PM"
    /// three times over can still outgrow the card, so the times come a size
    /// smaller wherever they would.
    private func stopsRow(_ progress: EventProgress, tint: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            stopsRow(progress, tint: tint, size: 18)
            stopsRow(progress, tint: tint, size: 15)
        }
        .accessibilityElement(children: .combine)
    }

    private func stopsRow(_ progress: EventProgress, tint: Color, size: CGFloat) -> some View {
        // ``EventProgress/fraction`` runs from the doors at 0 to the start at
        // ½ and the end at 1; each half is one bar.
        HStack(alignment: .timeMiddle, spacing: 10) {
            stop("Doors", at: shown.doorsOpen, size: size, alignment: .leading)
            stopBar(progress.fraction * 2, tint: tint)
            stop("Start", at: shown.startsAt, size: size, alignment: .center)
            stopBar((progress.fraction - 0.5) * 2, tint: tint)
            stop("End", at: shown.endsAt, size: size, alignment: .trailing)
        }
    }

    /// One time with what it is the time of small over it.
    private func stop(_ label: LocalizedStringKey, at instant: Date?, size: CGFloat,
                      alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            clock(instant, size: size)
                .font(.system(size: size, weight: .bold))
                .kerning(-0.4)
                .monospacedDigit()
                // The bars line up with the times, not with the names over them.
                .alignmentGuide(.timeMiddle) { $0[VerticalAlignment.center] }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func stopBar(_ filled: Double, tint: Color) -> some View {
        ProgressView(value: min(max(filled, 0), 1))
            .progressViewStyle(.linear)
            .tint(tint)
            .frame(minWidth: 20, idealWidth: 20, maxWidth: .infinity)
            .alignmentGuide(.timeMiddle) { $0[VerticalAlignment.center] }
            .accessibilityHidden(true)
    }

    /// A time as the reader's locale writes it, with the AM or PM a
    /// twelve-hour clock carries set small beside the digits.
    private func clock(_ instant: Date?, size: CGFloat) -> Text {
        guard let instant else { return Text(verbatim: "—") }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = shown.timeZone
        var time = instant.formatted(style.attributed)
        let periods = time.runs[\.dateField].compactMap { field, range in
            field == .amPM ? range : nil
        }
        for range in periods {
            time[range].font = .system(size: size * 0.6, weight: .bold)
        }
        return Text(time)
    }

    /// How long the show runs, from its start to its published end.
    ///
    /// Read in the order a night runs, so an end after midnight is the next
    /// morning — see ``Event/inOrder(_:_:_:)`` — and not past
    /// ``PassportStats/longestNight``, where the page's times are more likely
    /// a typo than a show.
    private var runLine: Text {
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)
        guard let starts = times.starts else { return Text("Start time not announced") }
        guard let ends = times.ends else { return Text("End time not announced") }
        let length = ends.timeIntervalSince(starts)
        guard length > 0, length <= PassportStats.longestNight else {
            return Text("End time not announced")
        }
        let runs = Duration.seconds(length)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return Text("Runs \(runs)")
    }

    // MARK: - The reader's own record

    /// The ticket and the seat as two tiles, and the note under them where
    /// there is one. Each opens ``TicketDetailsView``, where they are answered.
    private var ticketTiles: some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                ticketTile("Ticket", symbol: "ticket", tint: ticketTint,
                           value: ticketValue, valueTint: ticketTint, detail: ticketDetail)
                // Greyed with the ticket tile until there is a ticket: a seat
                // is only asked about once there is one to sit in.
                ticketTile("Seat", symbol: "sofa",
                           tint: hasTicket && !tracking.seat.isEmpty ? .primary : .secondary,
                           value: tracking.seat.isEmpty ? Text("Seat") : Text(verbatim: tracking.seat),
                           valueTint: hasTicket ? .primary : .secondary, detail: seatDetail)
            }

            if !tracking.note.isEmpty {
                Button {
                    isEditingTicket = true
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                        Text(tracking.note)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .glassPanel(cornerRadius: 18, interactive: true)
                .accessibilityLabel(Text("Notes"))
                .accessibilityValue(Text(tracking.note))
            }
        }
        .padding(.horizontal, 18)
        .accessibilityHint("Opens the ticket details")
    }

    private func ticketTile(_ title: LocalizedStringKey, symbol: String, tint: Color,
                            value: Text, valueTint: Color, detail: Text) -> some View {
        Button {
            isEditingTicket = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    value
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(valueTint)
                    detail
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 22, interactive: true)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(detail)"))
    }

    /// Where the ticket stands: in hand, still being tried for, or not yet —
    /// and once the night is over, simply that the reader was there.
    private var ticketValue: Text {
        if !isAhead { return Text("Attended") }
        if tracking.ticket == .purchased { return Text("Purchased") }
        if tracking.lotteryEntries != nil { return Text("In the lottery") }
        return Text("No ticket yet")
    }

    private var ticketTint: Color {
        if !isAhead { return .trackAttended }
        if tracking.ticket == .purchased { return .trackTicket }
        if tracking.lotteryEntries != nil { return .trackInterest }
        return .secondary
    }

    /// What it cost and what it took, where either was written down.
    private var ticketDetail: Text {
        var parts: [Text] = []
        if let cost = tracking.cost { parts.append(Text(verbatim: YenAmount().format(cost))) }
        if let entries = tracking.lotteryEntries { parts.append(Text("^[\(entries) entry](inflect: true)")) }
        guard let first = parts.first else { return Text("Tap to Edit") }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// The class the seat was sold as, where it was written down — in the
    /// reader's language where it is one of the chips, as written otherwise.
    private var seatDetail: Text {
        if !tracking.seatClass.isEmpty {
            return SeatClass(rawValue: tracking.seatClass).map { Text($0.label) }
                ?? Text(verbatim: tracking.seatClass)
        }
        return tracking.seat.isEmpty ? Text("Tap to Edit") : Text("Your seat")
    }

    // MARK: - Actions

    /// What the reader can do with the event, in a bar along the bottom of the
    /// sheet: keep it, share it, and the rest behind the ellipsis.
    ///
    /// One capsule at the leading edge, as the design draws it, with the space
    /// beside it left empty for the page to show through.
    @ToolbarContentBuilder
    private var actionBar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                withAnimation(.snappy) { store.toggleLibraryMembership(event) }
            } label: {
                Label(store.isInLibrary(event) ? "Remove from my events" : "Add to my events",
                      systemImage: store.isInLibrary(event) ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
            }
            .tint(store.isInLibrary(event) ? .trackAttended : .brandTint)

            if offersLiveActivity {
                Button(action: toggleLiveActivity) {
                    Label(liveActivity == nil ? "Enable Live Activity" : "Disable Live Activity",
                          systemImage: liveActivitySymbol)
                        .contentTransition(.symbolEffect(.replace))
                }
                .tint(liveActivity == .running ? .trackAttended : .brandTint)
            }

            ShareLink(item: event.sourceURL)
                .tint(.brandTint)

            moreMenu
                .tint(.brandTint)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }

    /// Everything the bar has no room for. In the order the design lists it
    /// top to bottom, whichever way the menu opens.
    private var moreMenu: some View {
        Menu {
            Section {
                if offersLiveActivity {
                    Button(action: toggleLiveActivity) {
                        Label(liveActivity == nil ? "Enable Live Activity" : "Disable Live Activity",
                              systemImage: "clock")
                    }
                }
                Button {
                    withAnimation(.snappy) { store.toggleFavorite(event) }
                } label: {
                    Label(store.isFavorite(event) ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: store.isFavorite(event) ? "heart.fill" : "heart")
                }
            }

            Section {
                if hasVenue {
                    Button {
                        openVenueInMaps(directions: true)
                    } label: {
                        Label("Directions", systemImage: "location.fill")
                    }
                }
                // Anything that changes the reader's Eventernote account
                // happens on the official site, where they authenticate
                // directly.
                Link(destination: event.sourceURL) {
                    Label("Open in Eventernote", systemImage: "safari")
                }
                ShareLink(item: event.sourceURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            #if DEBUG
            Section {
                Button {
                    isTestingLiveActivity = true
                } label: {
                    Label { Text(verbatim: "Test Live Activity…") } icon: { Image(systemName: "hammer") }
                }
            }
            #endif

            // The same place either way, so the menu keeps its shape as the
            // event goes in and out of the library.
            Section {
                if store.isInLibrary(event) {
                    Button(role: .destructive) {
                        withAnimation(.snappy) { store.remove(CollectionOfOne(event)) }
                    } label: {
                        Label { Text("Remove Event") } icon: { removalIcon }
                    }
                } else {
                    Button {
                        withAnimation(.snappy) { store.toggleLibraryMembership(event) }
                    } label: {
                        Label("Add Event", systemImage: "plus")
                    }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuOrder(.fixed)
    }

    /// What the event's Live Activity is doing, if it has one.
    private var liveActivity: EventActivities.Status? {
        EventActivities.shared.statuses[event.id]
    }

    /// Whether the bar and the menu offer the Live Activity: for a night the
    /// reader holds a ticket for — see ``EventActivities/canOffer(_:tracking:inLibrary:at:)``
    /// — and, whatever has changed since, for one already asked for, so it
    /// can always be turned off from here.
    private var offersLiveActivity: Bool {
        liveActivity != nil
            || EventActivities.shared.canOffer(event, tracking: tracking, inLibrary: store.isInLibrary(event))
    }

    /// A clock, with a tick on it once one is scheduled and filled in the
    /// colour of a night under way once it is on — the design's plain, pale
    /// and filled button.
    private var liveActivitySymbol: String {
        switch liveActivity {
        case nil: "clock"
        case .scheduled: "clock.badge.checkmark"
        case .running: "clock.fill"
        }
    }

    /// What the Live Activity is made from here: the seat, and the times.
    private var liveActivityKey: String {
        [tracking.seat, "\(store.isInLibrary(event))",
         event.doorsOpen?.description, event.startsAt?.description, event.endsAt?.description]
            .map { $0 ?? "" }
            .joined(separator: "|")
    }

    /// Turns the event's Live Activity on, at once, or off. Too early for it
    /// to last the night it says from when it can be instead, in passing —
    /// the notice pill and its error haptic, no alert to answer: the button
    /// is there all along, so the reader learns the feature exists and when
    /// to come back for it. See ``EventActivities/refusal(for:at:in:)``.
    private func toggleLiveActivity() {
        let activities = EventActivities.shared
        let event = event
        let tracking = tracking
        Task {
            if activities.statuses[event.id] != nil {
                await activities.stop(for: event)
            } else {
                do {
                    try await activities.start(for: event, tracking: tracking)
                } catch EventActivities.Refusal.beforeItsDay {
                    notices?.post(.refused("Available on the day of the event"))
                } catch EventActivities.Refusal.tooEarly(let earliest) {
                    // On the clock the sheet prints its times on.
                    var style = Date.FormatStyle(date: .omitted, time: .shortened)
                    style.timeZone = shown.timeZone
                    notices?.post(.refused("Available from \(earliest.formatted(style))"))
                } catch {
                    liveActivityFailure = error.localizedDescription
                }
            }
        }
    }

    /// The trash in the red its words are drawn in. A menu draws every icon
    /// in its own tint whatever it is handed, so only an image carrying its
    /// colour with it keeps one.
    private var removalIcon: Image {
        guard let trash = UIImage(systemName: "trash") else { return Image(systemName: "trash") }
        return Image(uiImage: trash.withTintColor(.systemRed, renderingMode: .alwaysOriginal))
    }

    // MARK: - What the page says the event is

    /// 概要: the one thing on an Eventernote event page somebody wrote out in
    /// sentences.
    ///
    /// It is where everything the site has no field for ends up — ticket
    /// prices, seat types, the on-sale date, which stage each act is on — so
    /// for most events it is the fullest thing published about the night. It
    /// also runs from one line to forty, which is why it opens collapsed: the
    /// billing and the hall below it should not sit under a wall of ticket
    /// terms the reader has already read once.
    @ViewBuilder
    private var summaryCard: some View {
        if let summary = event.summary {
            let shown = shownSummary(for: summary)
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Overview", caption: translationCaption(for: summary)) {
                    if canTranslate { translateButton(for: summary) }
                }

                // Imported text, shown as Eventernote published it — with the
                // addresses written into it made tappable, which is the one
                // thing this app adds to it. A translation is linked the same
                // way, since the addresses are carried through it untouched.
                Text(shown.linkingURLs)
                    .font(.system(size: 13))
                    .tint(Color.brandTint)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(isSummaryExpanded ? nil : Self.collapsedSummaryLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLong(shown) {
                    Button {
                        withAnimation(.snappy) { isSummaryExpanded.toggle() }
                    } label: {
                        Text(isSummaryExpanded ? "Show less" : "Show more")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.brandTint)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .glassPanel(cornerRadius: 28)
            .padding(.horizontal, 18)
            .task(id: translationTargetID) {
                dropTranslation(unlessFor: translationTargetID)
                await checkTranslation()
            }
            // Off the main actor from the start: the session is not
            // `Sendable`, so one that ever sat on the main actor could not be
            // handed to its own nonisolated methods. Only text crosses back.
            .translationTask(translationRequest) { @concurrent session in
                let target = await translationTargetID
                let outcome = await Self.translation(of: summary, with: session)
                await finishTranslating(summary, into: target, outcome)
            }
        }
    }

    // MARK: - Translating the description

    private var translationTarget: Locale.Language {
        TranslationTarget.resolved(translationTargetID)
    }

    /// Whether ``translatedSummary`` is this description, in the target the
    /// reader has chosen now.
    private func hasTranslation(of summary: String) -> Bool {
        translatedSummary?.source == summary && translatedSummary?.target == translationTargetID
    }

    private func shownSummary(for summary: String) -> String {
        if showsTranslation, hasTranslation(of: summary), let translatedSummary {
            return translatedSummary.text
        }
        return summary
    }

    /// Lets go of a translation made for another target, and of the request
    /// that would make another one: a configuration keeps the target it was
    /// created with, so invalidating it would translate into the old language
    /// again. Kept when the target is unchanged, since this also runs every
    /// time the card reappears — coming back from a performer's page should
    /// not cost the reader the translation they were reading.
    private func dropTranslation(unlessFor target: String) {
        if let translatedSummary, translatedSummary.target != target {
            self.translatedSummary = nil
            showsTranslation = false
            translationFailed = false
        }
        if let translationRequest, translationRequest.target != translationTarget {
            self.translationRequest = nil
            isTranslating = false
        }
    }

    /// Says the card is machine-translated while it is, since the reader is
    /// otherwise reading words nobody on the site wrote.
    private func translationCaption(for summary: String) -> Text? {
        if translationFailed { return Text("Couldn't translate") }
        if showsTranslation, hasTranslation(of: summary) { return Text("Translated by iOS") }
        return nil
    }

    private static let translateFont = UIFont.systemFont(ofSize: 12.5, weight: .semibold)

    private func translateButton(for summary: String) -> some View {
        let isShowing = showsTranslation && hasTranslation(of: summary)
        return Button {
            translationFailed = false
            if isShowing {
                showsTranslation = false
            } else if hasTranslation(of: summary) {
                showsTranslation = true
            } else {
                isTranslating = true
                if translationRequest == nil {
                    translationRequest = .init(source: TranslationTarget.source, target: translationTarget)
                } else {
                    translationRequest?.invalidate()
                }
            }
        } label: {
            // On the words' baseline, so the card's header lines them up with
            // its title — see ``SeeAllLabel``.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    if isTranslating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .centredOnLine(of: Self.translateFont)
                Text(isShowing ? "Show Original" : "Translate")
                    .font(Font(Self.translateFont))
            }
            .foregroundStyle(Color.brandTint)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isTranslating)
    }

    /// Offers translation only where it means something: not into Japanese,
    /// and not for a pair the system has
    /// no model for. A pair whose model is not downloaded yet is still offered
    /// — the system asks to download it on the first tap.
    private func checkTranslation() async {
        let target = translationTarget
        guard TranslationTarget.isWorthOffering(target) else {
            canTranslate = false
            return
        }
        let status = await LanguageAvailability().status(from: TranslationTarget.source, to: target)
        canTranslate = status != .unsupported
    }

    /// What a run of the translator came to, as far as the card is concerned.
    private nonisolated enum TranslationOutcome: Sendable {
        case translated(String)
        /// Nothing to show and nothing to say: no line needed translating, or
        /// the reader declined the model download, which is an answer rather
        /// than a failure.
        case nothing
        case failed
    }

    /// Translates line by line, so the description keeps its line breaks — the
    /// ticket terms in it are laid out as lists — and a line that is only an
    /// address is carried over as it stands rather than handed to a model that
    /// may "translate" it into a link to nowhere.
    @concurrent private nonisolated static func translation(
        of summary: String, with session: TranslationSession
    ) async -> TranslationOutcome {
        let lines = summary.components(separatedBy: "\n")
        let requests = lines.indices.compactMap { index -> TranslationSession.Request? in
            needsTranslating(lines[index])
                ? .init(sourceText: lines[index], clientIdentifier: String(index))
                : nil
        }
        guard !requests.isEmpty else { return .nothing }
        do {
            var translated = lines
            for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier, let index = Int(id) {
                    translated[index] = response.targetText
                }
            }
            return .translated(translated.joined(separator: "\n"))
        } catch {
            switch error {
            case is CancellationError, TranslationError.alreadyCancelled, TranslationError.notInstalled:
                return .nothing
            default:
                return .failed
            }
        }
    }

    /// Files a run's result under the target it was started for; a change
    /// while it ran leaves the result under the old one, which
    /// ``hasTranslation(of:)`` then declines to show.
    private func finishTranslating(_ summary: String, into target: String, _ outcome: TranslationOutcome) {
        switch outcome {
        case .translated(let text):
            translatedSummary = (summary, target, text)
            showsTranslation = true
        case .failed:
            translationFailed = true
        case .nothing:
            break
        }
        isTranslating = false
    }

    /// Whether a line has words in it to translate — not blank, and not an
    /// address standing alone.
    private nonisolated static func needsTranslating(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true { return false }
        return true
    }

    /// How much of a long description stands before the reader asks for the rest.
    private static let collapsedSummaryLines = 8

    /// Roughly whether anything is being cut off.
    ///
    /// What this wants is the laid-out line count, which SwiftUI will not give
    /// for a `Text` inside a scroll view, so it is guessed from the text: eight
    /// lines of the Japanese these are written in is around two hundred
    /// characters. A guess can only be wrong in one direction here — a Show
    /// more that opens onto nothing new — and it is the cheaper of the two
    /// mistakes than a description silently ending mid-sentence.
    private func isLong(_ summary: String) -> Bool {
        summary.count > 200
            || summary.split(whereSeparator: \.isNewline).count > Self.collapsedSummaryLines
    }

    // MARK: - Where the announcement was made

    /// 関連リンク and Twitterハッシュタグ: the pages the event was announced on,
    /// and what to follow the night under.
    ///
    /// One card rather than two, because both answer the same question — where
    /// the rest of this is — and because most events publish one or the other
    /// rather than both.
    @ViewBuilder
    private var linksCard: some View {
        let links = event.relatedLinks ?? []
        let hashtags = event.hashtags ?? []
        if !links.isEmpty || !hashtags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Links")

                VStack(spacing: 0) {
                    ForEach(links, id: \.self) { link in
                        linkRow(link)
                    }
                }

                if !hashtags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(hashtags) { hashtag in
                            Link(destination: hashtag.searchURL) {
                                Text(verbatim: hashtag.tag)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Color.brandTint)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassCapsule(interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .glassPanel(cornerRadius: 28)
            .padding(.horizontal, 18)
        }
    }

    /// One published link: the site it goes to, and enough of the address under
    /// it to tell two links to the same site apart.
    ///
    /// The host on its own line because that is the part a reader recognises —
    /// the promoter, the ticket agency, the post that broke the news — and the
    /// rest of these addresses is a tracking query nobody reads.
    private func linkRow(_ link: URL) -> some View {
        Link(destination: link) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandTint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: host(of: link))
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    if let path = trail(of: link) {
                        Text(verbatim: path)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The site, as a reader would name it: "www." is how a host is written
    /// rather than part of who it belongs to.
    private func host(of link: URL) -> String {
        guard let host = link.host() else { return link.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What follows the host, where there is anything worth printing. A link to
    /// the front page of a site has nothing to add to its own name.
    private func trail(of link: URL) -> String? {
        let path = link.path()
        return path.isEmpty || path == "/" ? nil : path
    }

    // MARK: - Performers

    /// Eventernote bills performers by name and nothing else — no instrument, no
    /// role, and no picture of them anywhere on the site — so a row is the name,
    /// in the billing order it was given in, and nothing dressed up around it.
    ///
    /// The billing carries no link to the person's own page either, so opening
    /// a row looks the name up first; ``PerformerView`` does that.
    private var performersCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            CardHeader(title: "Performers", count: event.performers.count)

            VStack(spacing: 3) {
                ForEach(event.performers) { performer in
                    NavigationLink(value: PerformerLink.billed(name: performer.name)) {
                        HStack(spacing: 12) {
                            Text(performer.name)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the performer")
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    // MARK: - Venue

    private var venueCard: some View {
        VStack(spacing: 0) {
            VenueMap(venue: event.venue, place: place) { openVenueInMaps(directions: false) }
                // The map alone is clipped, and only where the card's own
                // corners are. Clipping the whole card clips the glass with
                // it, and a clipped glass effect stops sampling what is behind
                // it and flattens to a plain light fill.
                .clipShape(.rect(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                 bottomTrailingRadius: 0, topTrailingRadius: 28,
                                 style: .continuous))

            HStack(spacing: 12) {
                venueName
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasVenue {
                    Button {
                        openVenueInMaps(directions: true)
                    } label: {
                        Text("Directions")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.brandTint)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .glassCapsule(interactive: true)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
        }
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    /// The hall's name, and — where the site has a page for it — the way to
    /// everything else held there.
    ///
    /// A link rather than the Directions button beside it: those two are
    /// different errands, one to Maps and one to the rest of the hall's
    /// calendar. An event announced before a hall was booked has no name to
    /// push, and stays the plain line it has always been.
    @ViewBuilder
    private var venueName: some View {
        if event.venue.isEmpty {
            venueLines
        } else {
            NavigationLink(value: venueLink) {
                HStack(spacing: 7) {
                    venueLines
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// The place id where the event's own page has been imported, and the name
    /// alone otherwise — which the hall's page is found by, the way a billed
    /// performer's is.
    private var venueLink: VenueLink {
        if let placeID = event.placeID {
            .place(PlaceListing(id: placeID, name: event.venue))
        } else {
            .named(event.venue)
        }
    }

    private var venueLines: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.venue.isEmpty ? String(localized: "Venue to be announced") : event.venue)
                .font(.system(size: 14.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let venueDetail = event.venueDetail {
                Text(venueDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Provenance

    private var footnote: some View {
        Footnote(isImporting
                 ? Text("Importing this event from its public Eventernote page…")
                 : provenance)
            .padding(.horizontal, 26)
            .padding(.top, 2)
    }

    /// Where the facts came from and, where the page's history says so, who
    /// wrote them down last.
    ///
    /// Eventernote's event pages are written by its members rather than by the
    /// promoter, so how recently one was touched is part of reading it: an
    /// upcoming night last edited two years ago has doors nobody has checked
    /// since. The handle is shown as the site prints it.
    private var provenance: Text {
        let source = Text("Event data imported from the public Eventernote page.")
        guard let editedAt = event.editedAt else { return source }
        let when = Text(editedAt, format: .relative(presentation: .named))
        guard let handle = event.editedBy else {
            return Text("\(source) The page was last edited \(when).")
        }
        return Text("\(source) The page was last edited by \(Text(verbatim: handle)) \(when).")
    }
}

/// A small symbol before a line of the timeline card's footer, drawn a step
/// lighter than the words.
private struct FooterLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.8)
            configuration.title
        }
    }
}

#Preview {
    EventDetailView(event: PreviewData.events[0])
        .library(EventStore.preview)
}

private extension VerticalAlignment {
    /// The middle of the timeline card's times, which its bars sit level with.
    enum TimeMiddle: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let timeMiddle = VerticalAlignment(TimeMiddle.self)
}
