import SwiftUI

/// One event: what Eventernote publishes about it, and what the reader records
/// about it. The two are kept visually distinct throughout.
///
/// A sheet opened from a search row starts with only what the row printed, and
/// imports the event's own page for the rest.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let source: Event
    @State private var isImporting = false

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
                    trackingCard
                    if !event.performers.isEmpty { performersCard }
                    venueCard
                    openInEventernote
                    footnote
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)

            closeButton
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .washBackground()
        .task { await importPage() }
        // The first time an event at a hall nothing has looked up yet is
        // opened, this is what goes and finds it — whether or not the reader
        // mirrors anything to their calendar.
        .task(id: venueKey) { place = await VenuePlaces.shared.mapItem(for: event) }
    }

    /// Imports the event's own page for the times, billing and head count a
    /// search row does not carry. A row already imported is left alone.
    private func importPage() async {
        guard !event.isDetailed else { return }
        isImporting = true
        defer { isImporting = false }
        await store.loadDetail(for: event)
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    AsyncImage(url: event.imageURL) { image in
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
        Text(verbatim: event.longDateLine)
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
            StatTile(tint: .trackTicket, value: event.doorsLine ?? "—",
                     label: "Doors open", layout: .field)
            // The end time qualifies the start rather than standing on its own,
            // so it sits under it — and stays away entirely when the page has
            // published no end.
            StatTile(tint: .trackAttended, value: event.timeLine ?? "—",
                     sub: event.endsLine.map { Text("Ends \($0)") },
                     label: "Performance", layout: .field)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - The reader's own record

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Text("My tracking")
                    .font(.system(size: 17, weight: .bold))
                Text("Private to you")
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
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

            if hasTicket { ticketCard }

            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("Notes")
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

    /// What the ticket turned out to be: the seat it named, and what it cost.
    ///
    /// Side by side because neither is more than a line, and asking for them
    /// one under the other would push the notes off the bottom of the card.
    private var ticketCard: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("Seat")
                writing {
                    // A block, a row and a number in three languages worth of
                    // conventions: nothing the keyboard would correct here is
                    // a correction.
                    TextField("Seat", text: tracking.seat, prompt: Text("Row and number"))
                        .autocorrectionDisabled()
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("Cost")
                writing {
                    // The em dash the imported tiles use for a fact nobody
                    // published, for the same thing here: nobody wrote it down.
                    TextField("Cost", value: tracking.cost, format: .yen,
                              prompt: Text(verbatim: "¥—"))
                        .keyboardType(.numberPad)
                }
            }
            .frame(width: 112)
        }
    }

    /// The glass a field the reader writes in sits in. One helper so the three
    /// of them are the same field asked three questions.
    private func writing<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .glassPanel(cornerRadius: 20)
    }

    /// Written for the one enum left rather than for any of them. It was
    /// generic over three, with a type switch to find each one's label,
    /// because three different questions were asked the same way.
    private func segment(
        _ label: LocalizedStringKey,
        selection: Binding<TicketStatus>,
        options: [TicketStatus]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(label)
            Picker(label, selection: selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func fieldLabel(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.44)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
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
                 : Text("Event data imported from the public Eventernote page."))
            .padding(.horizontal, 26)
            .padding(.top, 2)
    }
}

#Preview {
    EventDetailView(event: PreviewData.events[0])
        .environment(EventStore.preview)
}
