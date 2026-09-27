import SwiftUI
import Translation

/// One event: what Eventernote publishes about it, and what the reader records
/// about it. The two are kept visually distinct throughout.
///
/// A sheet opened from a search row starts with only what the row printed, and
/// imports the event's own page for the rest.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

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

    @Environment(\.openURL) private var openURL

    init(event: Event) {
        source = event
    }

    /// The fullest copy the app holds. An import lands in the store, so reading
    /// it back keeps this sheet and the lists behind it showing the same event.
    private var event: Event {
        store.event(id: source.id) ?? source
    }

    private var tracking: Binding<Tracking> {
        Binding(
            get: { store.tracking(for: event) },
            set: { store.setTracking($0, for: event) }
        )
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
        // sheet's own chrome is the Done button, so the bar stays hidden at the
        // root and comes back — with its back button — on whatever is pushed
        // onto it.
        NavigationStack {
            detail
                .toolbar(.hidden, for: .navigationBar)
                .venueDestination()
        }
        .presentationDragIndicator(.visible)
    }

    private var detail: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    actions
                    statistics
                    // Only for an event the reader keeps. Tracking answers
                    // questions about a night they mean to be at — the ticket,
                    // the seat, what it cost — so on an event that is not in
                    // the library there is nothing for it to be about, and a
                    // date opened from Following or Search shows the facts
                    // alone until it is added. A removal keeps whatever was
                    // written, so re-adding brings the card back as it was.
                    if store.isInLibrary(event) { trackingCard }
                    summaryCard
                    if !event.performers.isEmpty { performersCard }
                    venueCard
                    linksCard
                    openInEventernote
                    if let importFailure {
                        RefreshFailureNote(message: importFailure)
                            .padding(.horizontal, 16)
                    }
                    footnote
                }
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
        .task { await importPage() }
        // A sheet left open while the reader was away is owed the same check
        // it made as it opened: past the window, it reads its page again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await importPage() } }
        }
        .environment(\.imagesCheckedSince, imagesCheckedSince)
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

    private var header: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    CachedImage(url: event.imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.microphone")
                            .font(.system(size: 72, weight: .ultraLight))
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipped()
                .overlay {
                    // Fades the flyer into the wash so the title stays readable.
                    LinearGradient(
                        stops: [
                            .init(color: .washBase.opacity(0), location: 0),
                            .init(color: .washBase.opacity(0.75), location: 0.62),
                            .init(color: .washBase, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(height: 392)
                .accessibilityLabel("Event flyer")

            VStack(spacing: 9) {
                Text(event.title)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                dateLine
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                zoneBadge
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }

    /// The day, and only the day.
    ///
    /// Doors, start and end used to trail it here as well, which put the same
    /// three times twice on one screen — once in a run-on line under the title
    /// and again, labelled, in the tiles a scroll below. The tiles are where a
    /// time is read from, and they already say "—" for one the page has yet to
    /// publish, so the header is left with the one fact a title needs beside it.
    private var dateLine: Text {
        // An already-formatted date, so it is shown as given rather than as a
        // localizable key.
        Text(verbatim: shown.longDateLine)
    }

    /// The event as it is printed on the chosen clock — see
    /// ``Event/shown(on:)``. Only ever formatted.
    private var shown: Event { event.shown(on: timeDisplay) }

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
    /// be claiming an answer rather than having one — Seoul is not on Japan's
    /// clock because Eventernote is Japanese. The badge then says which clock
    /// the times are on without saying what that clock is set to, which is
    /// exactly what is known. The sheet asks for its own hall the moment it
    /// opens, so this is usually a second rather than a state.
    private var venueZone: TimeZone? {
        if let placed = place?.timeZone { return placed }
        if event.timeZone != Event.publishedZone { return event.timeZone }
        if let address = event.publishedAddress, Region.containing(address: address) != nil {
            return Event.publishedZone
        }
        return nil
    }

    /// Which clock every time on this sheet is on.
    ///
    /// On every sheet rather than only on the nights abroad. The times here
    /// are the hall's, as Eventernote's members wrote them — 18:00 is 18:00 at
    /// the door rather than 18:00 wherever the reader is standing — and that
    /// is as true of a Tokyo date as of a Taipei one. A reader in Shanghai
    /// reading Tokyo is owed the same sentence as a reader in Tokyo reading
    /// Taipei, and a badge that appeared only on the rare night abroad would
    /// leave every other sheet quietly implying whichever clock the reader
    /// happens to be on.
    ///
    /// Under the date, because it qualifies the date as much as the times: a
    /// night falls on the day its hall says it does.
    ///
    /// The venue's clock rather than a place name, for the reason
    /// ``Event/offsetLine(in:)`` gives: the name would be the map provider's
    /// and the provider is the reader's, so a Taipei hall comes back named for
    /// the mainland. The hall is named on this same sheet; what the badge adds
    /// is which clock it keeps.
    private var zoneBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 10, weight: .semibold))
            // On the reader's own clock the offset is always known: it is
            // this device's, on the night itself.
            if timeDisplay == .local {
                Text("My time · \(event.offsetLine(in: .current))")
                    .font(.system(size: 10.5, weight: .semibold))
            // The offset only where there is one to give — see ``venueZone``.
            } else if let zone = venueZone {
                Text("Venue time · \(event.offsetLine(in: zone))")
                    .font(.system(size: 10.5, weight: .semibold))
            } else {
                Text("Venue time")
                    .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassCapsule()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            timeDisplay == .local
                ? Text("Times shown in your own time, \(event.offsetLine(in: .current))")
                : venueZone.map { Text("Times shown in the venue's own time, \(event.offsetLine(in: $0))") }
                ?? Text("Times shown in the venue's own time")
        )
    }

    /// The way out of the sheet.
    ///
    /// A glyph rather than the word Done, because nothing here is being
    /// confirmed: every switch, note and star on this sheet has already taken
    /// effect, and a button that says Done invites the reader to think
    /// something is being saved by pressing it — and that leaving another way
    /// would lose it. It is the mark the system closes things with, in the
    /// same glass circle the actions under the title wear.
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

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 13) {
            if hasVenue {
                circularAction {
                    Button {
                        openVenueInMaps(directions: true)
                    } label: {
                        actionIcon("location.fill", tint: .brandTint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Directions to the venue")
                }
            }

            circularAction {
                Button {
                    withAnimation(.snappy) { store.toggleLibraryMembership(event) }
                } label: {
                    actionIcon(
                        store.isInLibrary(event) ? "checkmark" : "plus",
                        tint: store.isInLibrary(event) ? .trackAttended : .brandTint
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isInLibrary(event) ? "Remove from my events" : "Add to my events")
            }

            circularAction {
                Button {
                    withAnimation(.snappy) { store.toggleFavorite(event) }
                } label: {
                    actionIcon(
                        store.isFavorite(event) ? "heart.fill" : "heart",
                        tint: store.isFavorite(event) ? .favorite : .secondary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isFavorite(event) ? "Remove from favorites" : "Add to favorites")
            }

            // Both of these were a tap deeper under an ellipsis menu, which
            // held nothing else worth the indirection.
            circularAction {
                Link(destination: event.sourceURL) {
                    actionIcon("safari", tint: .brandTint)
                }
                .accessibilityLabel("Open in Eventernote")
            }

            circularAction {
                ShareLink(item: event.sourceURL) {
                    actionIcon("square.and.arrow.up", tint: .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share link")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func circularAction<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 56, height: 56)
            .glassCircle(interactive: true)
    }

    private func actionIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 56, height: 56)
            .contentShape(.rect)
            .contentTransition(.symbolEffect(.replace))
    }

    // MARK: - Imported facts

    /// An em dash stands in for a field the public page does not carry — the
    /// app never fills one in itself.
    private var statistics: some View {
        HStack(alignment: .top, spacing: 11) {
            // The head count reads as a number needing a noun, so the tile is
            // named for where it comes from and says what was counted under it.
            StatTile(tint: .trackInterest, value: event.listedAttendees?.formatted() ?? "—",
                     sub: event.listedAttendees.map { _ in Text("people listed") },
                     label: "Eventernote", layout: .field)
            StatTile(tint: .trackTicket, value: shown.doorsLine ?? "—",
                     label: "Doors open", layout: .field)
            // The end time qualifies the start rather than standing on its own,
            // so it sits under it — and stays away entirely when the page has
            // published no end.
            StatTile(tint: .trackAttended, value: shown.timeLine ?? "—",
                     sub: shown.endsLine.map { Text("Ends \($0)") },
                     label: "Performance", layout: .field)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - The reader's own record

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Text("My tracking")
                    .font(.system(size: 19, weight: .bold))

                Spacer(minLength: 12)

                // The promise the card makes, said once at the top of it and
                // set apart from it: on its own line under the title it read
                // as the card's subtitle — as if what followed were a section
                // about privacy — where a pill at the other end of the title
                // reads as a stamp on the card. The closed lock says it before
                // the words are read.
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Private to you")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCapsule()
            }

            // The one question the library does not already answer, and only
            // while it is still open to ask. Whether the reader means to go is
            // what keeping the event says, and whether they went is what its
            // date says once it has passed — see ``Tracking``. A night already
            // over was a night they held a ticket for, so the picker gives way
            // to what that ticket turned out to be.
            if event.isUpcoming {
                segment("Ticket", selection: tracking.ticket, options: TicketStatus.allCases)
            }

            // A count is asked on one line — see ``lotteryRow``.
            lotteryRow

            // What the ticket turned out to be, ruled off from the question
            // that was asked before anybody had one. The two are written
            // answers rather than a count, so they are asked the way the note
            // is, with the label above the field; side by side because neither
            // is more than a line and stacking them would push the note off
            // the bottom of the card.
            if hasTicket {
                Divider()

                HStack(alignment: .top, spacing: 12) {
                    writtenAnswer("Seat") { seatField }
                    writtenAnswer("Cost") { costField }
                }
            }

            // The one answer that is not a line at all, so it is given the
            // card's whole width and room to grow into.
            writtenAnswer("Notes") {
                writing {
                    TextField(
                        "Notes",
                        text: tracking.note,
                        prompt: Text("Something only you will see"),
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    /// Whether there is a ticket to say anything about.
    ///
    /// Not asked for a past event: the night happened, so the ticket existed.
    /// Still to come, it is there when the reader says they have bought it.
    private var hasTicket: Bool {
        !event.isUpcoming || store.tracking(for: event).ticket == .purchased
    }

    /// An answer written out: what is being asked, and under it the field it
    /// is written in.
    ///
    /// The label goes above rather than beside because what is written can run
    /// to the width of the card — a seat as a Japanese hall prints it, a price,
    /// a note — and a question sitting beside it would be taking that room
    /// away from the answer.
    private func writtenAnswer<Content: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(label)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// How many entries the reader put into the lottery for this night, asked
    /// on one line.
    ///
    /// The only answer here that is a count rather than something written, and
    /// the only one asked with the question at the left: a number needs a
    /// fixed and narrow field, so the room a label above it would take is room
    /// nothing would ever use.
    private var lotteryRow: some View {
        HStack(spacing: 0) {
            fieldLabel("Lottery entries")
            Spacer(minLength: 12)
            lotteryStepper
                .frame(width: Self.countWidth)
        }
    }

    /// How wide the count's field is.
    ///
    /// Two ends to press and, between them, room for the four digits
    /// ``EntryCount`` will take and no more. It was sized as a written answer
    /// before, which left a single digit sitting in the middle of a field with
    /// nothing else in it — a count is a narrow thing, and a field that says
    /// otherwise is asking for something bigger than it wants.
    private static let countWidth: CGFloat = 108

    /// The height every one-line field on the card stands at: the count, the
    /// seat, the price.
    ///
    /// A floor rather than a fixed height — a field is as tall as the text
    /// inside it, which grows with the reader's type size — but one floor for
    /// all three. They are stacked down one card rather than set beside one
    /// another, which is exactly when a difference of a few points reads as a
    /// mistake rather than as a distinction.
    ///
    /// The written fields carry less padding than a field of this height would
    /// give them on its own, so that the floor is what decides all three
    /// rather than the text inside two of them.
    private static let fieldHeight: CGFloat = 32

    /// How many entries the reader put into the lottery for this night.
    ///
    /// Asked whether or not there is a ticket, and before the ticket is asked
    /// about: the applications went in long before anybody knew, and a night
    /// applied for six times and lost is worth having written down by a reader
    /// who keeps the event anyway.
    ///
    /// An empty field is "not written down", and so is 0 — see
    /// ``Tracking/lotteryEntries``. There is one way to say "no lottery here"
    /// rather than two that mean the same thing and count differently.
    ///
    /// Stepped rather than typed, because the answer is nearly always one of
    /// the first few numbers and a keyboard for those is three taps of
    /// overhead. The field between the buttons still takes a typed number for
    /// the reader who applied eleven times, and either way down — stepping off
    /// 1 or clearing what was typed — leaves it empty.
    private var lotteryStepper: some View {
        HStack(spacing: 0) {
            lotteryStep(by: -1, symbol: "minus")

            stepperRule

            TextField("Lottery entries", value: tracking.lotteryEntries,
                      format: .entries, prompt: Text(verbatim: "—"))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .labelsHidden()
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .frame(maxWidth: .infinity)

            stepperRule

            lotteryStep(by: 1, symbol: "plus")
        }
        .frame(height: Self.fieldHeight)
        .background(.quaternary.opacity(0.5), in: Self.fieldShape)
        .overlay { Self.fieldShape.strokeBorder(.quaternary, lineWidth: 0.5) }
        .sensoryFeedback(.selection, trigger: tracking.wrappedValue.lotteryEntries)
    }

    /// One end of the lottery stepper.
    ///
    /// Counting up from nothing written down means 1 rather than 0 — the reader
    /// who reaches for plus is recording an application they made — and
    /// counting down off 1 empties the field again, because 0 is that same
    /// nothing rather than a step below it. So minus is dead on an empty
    /// field: there is no answer there to take one off. The ceiling is
    /// ``EntryCount``'s own four digits, so the two ways in agree on what a
    /// number is.
    ///
    /// Both ends fall out of one comparison: a step that would leave the field
    /// saying exactly what it says now is a step there is no point offering.
    private func lotteryStep(by delta: Int, symbol: String) -> some View {
        let current = tracking.wrappedValue.lotteryEntries
        let stepped = min(max((current ?? 0) + delta, 0), 9999)
        let next: Int? = stepped == 0 ? nil : stepped
        let enabled = next != current

        return Button {
            tracking.lotteryEntries.wrappedValue = next
        } label: {
            // The whole end of the field is the target, not the glyph in the
            // middle of it: the three parts are one control, and each of them
            // gets a third of it.
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Color.brandTint : Color.secondary.opacity(0.4))
                .frame(width: 33)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // The glyph alone reads as "Add" and "Remove", which on this sheet is
        // what the library button says.
        .accessibilityLabel(delta < 0 ? Text("Fewer lottery entries") : Text("More lottery entries"))
    }

    /// What separates the count from the two ends that step it. Inset from the
    /// field's own edges, so it divides the control rather than cutting it.
    private var stepperRule: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }

    /// Where the reader sat, as the ticket printed it.
    private var seatField: some View {
        writing(minHeight: Self.fieldHeight) {
            // A block, a row and a number in three languages worth of
            // conventions: nothing the keyboard would correct here is a
            // correction.
            TextField("Seat", text: tracking.seat, prompt: Text("Row and number"))
                .autocorrectionDisabled()
        }
    }

    /// What the night cost.
    private var costField: some View {
        writing(minHeight: Self.fieldHeight) {
            // The em dash the imported tiles use for a fact nobody published,
            // for the same thing here: nobody wrote it down.
            TextField("Cost", value: tracking.cost, format: .yen,
                      prompt: Text(verbatim: "¥—"))
                .keyboardType(.numberPad)
        }
    }

    /// The field the reader writes in. One helper so the four of them are the
    /// same field asked four questions.
    ///
    /// Flat rather than glass. Liquid Glass is the system's treatment for
    /// something floating *over* content — a toolbar, a sheet's own chrome, the
    /// round buttons under the flyer — and these are not floating over
    /// anything: they are inside a card that is already glass. Glass on glass
    /// has nothing to refract, which is why they read as empty pills rather
    /// than as somewhere to type.
    ///
    /// The radius is concentric with that card rather than chosen: 28 at the
    /// card's edge, less the 18 of inset the field sits behind, is 10 here, so
    /// the two sets of corners run parallel instead of bulging inside one
    /// another. The 20 they had was nearly half the field's own height, which
    /// is what made them look like capsules that had been squashed.
    private func writing<Content: View>(
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: minHeight)
            .background(.quaternary.opacity(0.5), in: Self.fieldShape)
            .overlay { Self.fieldShape.strokeBorder(.quaternary, lineWidth: 0.5) }
    }

    /// 28 − 18: see ``writing(content:)``.
    private static let fieldShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// Written for the one enum left rather than for any of them. It was
    /// generic over three, with a type switch to find each one's label,
    /// because three different questions were asked the same way.
    private func segment(
        _ label: LocalizedStringKey,
        selection: Binding<TicketStatus>,
        options: [TicketStatus]
    ) -> some View {
        writtenAnswer(label) {
            Picker(label, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// What one answer is being asked for.
    ///
    /// Written the way a question is written rather than set as a heading:
    /// small caps and letter-spacing are how a *section* is labelled, and these
    /// label neither a section nor anything the reader is meant to read past.
    /// Beside its own answer at the reader's own text size, a label is part of
    /// the sentence the row makes — "Lottery entries: 8".
    private func fieldLabel(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
                        HStack(spacing: 4) {
                            Text(isSummaryExpanded ? "Show less" : "Show more")
                                .font(.system(size: 12.5, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(isSummaryExpanded ? 180 : 0))
                        }
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
            .translationTask(translationRequest) { session in
                await translate(summary, with: session)
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
            HStack(spacing: 4) {
                if isTranslating {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "translate")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isShowing ? "Show Original" : "Translate")
                    .font(.system(size: 12.5, weight: .semibold))
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

    /// Translates line by line, so the description keeps its line breaks — the
    /// ticket terms in it are laid out as lists — and a line that is only an
    /// address is carried over as it stands rather than handed to a model that
    /// may "translate" it into a link to nowhere.
    private func translate(_ summary: String, with session: TranslationSession) async {
        // The target this run was started for; a change while it runs leaves
        // the result filed under the old one, which ``hasTranslation(of:)``
        // then declines to show.
        let target = translationTargetID
        let lines = summary.components(separatedBy: "\n")
        let requests = lines.indices.compactMap { index -> TranslationSession.Request? in
            Self.needsTranslating(lines[index])
                ? .init(sourceText: lines[index], clientIdentifier: String(index))
                : nil
        }
        guard !requests.isEmpty else {
            isTranslating = false
            return
        }
        do {
            var translated = lines
            for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier, let index = Int(id) {
                    translated[index] = response.targetText
                }
            }
            translatedSummary = (summary, target, translated.joined(separator: "\n"))
            showsTranslation = true
        } catch {
            // Declining the model download lands here too, and is an answer
            // rather than a failure — it says nothing.
            switch error {
            case is CancellationError, TranslationError.alreadyCancelled, TranslationError.notInstalled:
                break
            default:
                translationFailed = true
            }
        }
        isTranslating = false
    }

    /// Whether a line has words in it to translate — not blank, and not an
    /// address standing alone.
    private static func needsTranslating(_ line: String) -> Bool {
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

    /// Anything that changes the reader's Eventernote account happens on the
    /// official site, where they authenticate directly.
    private var openInEventernote: some View {
        ExternalLinkPanel(title: "Open in Eventernote", destination: event.sourceURL)
            .padding(.horizontal, 18)
    }

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

#Preview {
    EventDetailView(event: PreviewData.events[0])
        .environment(EventStore.preview)
}
