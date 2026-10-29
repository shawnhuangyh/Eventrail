import MapKit
import SwiftUI

/// The event flyer Eventernote hosts, with the placeholder the design uses
/// until it loads — or for the events the site has no artwork for.
struct FlyerThumbnail: View {
    var url: URL?
    var width: CGFloat = 58
    var cornerRadius: CGFloat = 15

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        shape
            .fill(.quaternary)
            .overlay {
                // Flyers are listed as squares and printed 5:7, so the artwork
                // fills the frame and is cropped rather than letterboxed.
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.microphone")
                        .font(.system(size: width * 0.34, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
            }
            .frame(width: width, height: width * 7 / 5)
            .accessibilityLabel("Event flyer")
    }
}

/// The way out of a sheet that floats its own over the top of the page, as an
/// event's sheet and the ticket stub do: a glyph in a glass circle, named
/// Close for VoiceOver, and pressed by Escape — `shortcut`, nil while a sheet
/// of its own stands over it, which a key it does not take falls through to.
struct CloseButton: View {
    var shortcut: KeyboardShortcut? = .cancelAction
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassCircle(interactive: true)
        .accessibilityLabel("Close")
        .keyboardShortcut(shortcut)
    }
}

/// The single collapsed tracking badge on an event row.
struct StatusBadge: View {
    let status: TrackingStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.tint)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(status.tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .capsulePanel()
        .accessibilityElement(children: .combine)
    }
}

/// How long until an event, as a count of days over the word for them.
///
/// The one thing a row about the future can say that a row about the past
/// cannot, and the thing a reader with a ticket actually wants off a list: not
/// which day it is — the row says that already — but how far off it is. Read
/// as a number rather than as a phrase, because a column of them is scanned
/// rather than read.
struct DaysAway: View {
    /// Whole days, as ``Event/daysAway`` counts them.
    let days: Int

    /// The last week reads in the app's own colour and everything further out
    /// in grey. Nothing is filtered or sorted by it; it is the row telling the
    /// eye where to stop.
    private var isSoon: Bool { days <= 7 }

    var body: some View {
        // Centred on each other rather than set against the chevron: "DAYS"
        // is about as wide as two digits and hid the difference, but 天 and
        // 日 are one narrow character and sat off to the side of the number.
        VStack(alignment: .center, spacing: -1) {
            if days == 0 {
                // The day itself has no number worth printing, and "0" would
                // be the wrong answer to how far off it is.
                Text("Today")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.brandTint)
            } else {
                Text(days, format: .number)
                    .font(.system(size: 21, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSoon ? AnyShapeStyle(Color.brandTint) : AnyShapeStyle(.primary))
                Text(days == 1 ? "Day" : "Days")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSoon ? AnyShapeStyle(Color.brandTint.opacity(0.85)) : AnyShapeStyle(.tertiary))
            }
        }
        // Set in caps here rather than in the string, so a language that has
        // no cases is handed its own word untouched.
        .textCase(.uppercase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 0 ? Text("Today") : Text("^[In \(days) day](inflect: true)"))
    }
}

/// What a row the reader has not looked at yet says about itself — New, or
/// Updated where the page changed after they did. See ``FollowingRead``.
/// Following and My Events both draw it, off the same record, so a date read
/// in one is read in the other.
struct UnreadTag: View {
    let unread: FollowingUnread

    var body: some View {
        label
            .textCase(.uppercase)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Color.brandTint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.brandTint.opacity(0.13),
                        in: .rect(cornerRadius: 5, style: .continuous))
            .fixedSize()
            .transition(.scale.combined(with: .opacity))
    }

    private var label: Text {
        switch unread {
        // Keyed in capitals as the design writes them, and apart from the
        // refresh notice's "Updated", which is a sentence rather than a tag.
        case .new: Text("NEW")
        case .updated: Text("UPDATED")
        }
    }
}

/// One cell of a three-up statistics row: a number with its caption under it.
/// Three of these read as one row of counts, which is what the performer and
/// venue screens show.
struct StatTile: View {
    let tint: Color
    /// A formatted number, so not a localizable key.
    let value: String
    /// A second line under the value, for a fact that only qualifies it. Nil
    /// where the public page published nothing to put there.
    var sub: Text?
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 9, height: 9)
                .padding(.bottom, 3)
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
            if let sub {
                sub
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.top, -2)
            }
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 15)
        .panel(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}

/// The section header pills that stand over a month of events.
///
/// It reads the same wherever it is used, which takes saying twice: a `List`
/// section header arrives with the system's own uppercased, secondary styling,
/// and a header pinned over a scrolling list has the rows passing behind it.
/// Both are answered here rather than at each call site, so the Events tab and
/// the Following tab cannot drift apart again.
///
/// Two pills rather than one and a bare line of text. The count used to sit
/// loose beside the month in tertiary grey, which is legible over the wash and
/// not over a flyer — and a pinned header has flyers going past under it all
/// day. So it wears the month's own backing, and is kept the smaller of the
/// two by its size and its weight instead.
struct GroupHeader: View {
    /// A formatted month, an imported artist name, or the filter's own name.
    let label: Text
    /// How many are under it, said in what they are — events, or rounds on
    /// the Lotteries screen.
    let count: Text
    /// The label's own colour, where the header says how what is under it
    /// stands — Won in green — rather than only when it falls.
    var tint: Color?

    init(label: Text, count: Int) {
        self.init(label: label, count: Text("^[\(count) event](inflect: true)"))
    }

    init(label: Text, count: Text, tint: Color? = nil) {
        self.label = label
        self.count = count
        self.tint = tint
    }

    /// Where the header sits in its `List` row, and where each event row under
    /// it sits: the two tabs' months are spaced alike only if both read these.
    static let insets = EdgeInsets(top: 4, leading: 20, bottom: 5, trailing: 20)
    static let rowInsets = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    /// The gap a month opens with, over the rows' own insets — wider than the
    /// one between the header and its first row, so a header reads as the top
    /// of the month below it rather than the foot of the one above.
    static let sectionSpacing: CGFloat = 20

    var body: some View {
        HStack(spacing: 7) {
            pill {
                label
                    .font(.system(size: 12, weight: .bold))
                    .kerning(0.24)
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }
            pill {
                count
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        .textCase(nil)
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
    }

    /// The pill both halves are set in.
    ///
    /// The wash goes *under* the pill: the pill is drawn translucent, and over
    /// an opaque slice of the wash a flyer scrolling behind a pinned header
    /// cannot show through it.
    private func pill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .capsulePanel()
            .background(Color.washBase, in: .capsule)
    }
}

extension View {
    /// A `List` of months headed by ``GroupHeader``, spaced by its numbers
    /// alone: the system's own section gap and header and row minimums are
    /// taken away, since left in they differ with what else the list holds.
    /// On a Mac the band under the bar is the list's own
    /// (``SwiftUI/View/bandUnderBarOnMac()``), since the headers pin.
    func monthSections() -> some View {
        listSectionSpacing(GroupHeader.sectionSpacing)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .bandUnderBarOnMac()
    }
}

/// Lays chips out left to right, wrapping to a new line when they run out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// The gap between two lines, where it is not ``spacing`` — a legend
    /// spaces its items wider than it spaces its lines.
    var lineSpacing: CGFloat?

    private var lineGap: CGFloat { lineSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineGap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(within: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineGap
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(within maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// One favorited event: the flyer, what and where it is, and the heart that
/// takes it back out again.
///
/// Shared by the card on the Me tab and the full list behind its See All, so
/// that the short version and the long one cannot drift apart.
///
/// The heart is the same circular control the Following tab's rows carry, so
/// the one gesture that takes a row out of a list looks the same wherever the
/// list is.
struct FavoriteEventRow: View {
    @Environment(EventStore.self) private var store

    /// What stands where these rows would, when there are none.
    ///
    /// Kept beside the row rather than written out on each of the two screens
    /// that show a list of them: the card on the Me tab and the full list
    /// behind its See All are the same list, and were saying the same sentence
    /// in two copies.
    static let emptyNote: LocalizedStringKey = "Tap the heart on any event to keep it here."

    let event: Event
    var showsDivider = false
    var isSelecting = false
    var isSelected = false
    var open: () -> Void

    var body: some View {
        CompactEventRow(event: event, showsDivider: showsDivider,
                        isSelecting: isSelecting, isSelected: isSelected, open: open) {
            Button {
                withAnimation(.snappy) { store.toggleFavorite(event) }
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.favorite)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .circlePanel()
            .accessibilityLabel("Remove from favorites")
        }
    }
}

/// A short row inside a card — flyer, title, day and hall — with one round
/// control beside it: Favorite Events' heart, Not on Your Account's way to
/// the site.
///
/// The control is a sibling of the row's own button rather than a button
/// inside its label. Nested, the row's tap target covers it and a tap on the
/// heart opens the event instead of un-favoriting it.
struct CompactEventRow<Control: View>: View {
    /// Which clock the day is printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let event: Event
    /// Drawn above the row rather than below it, so a list ends on a row and
    /// not on a line.
    var showsDivider = false
    /// While the screen is picking rows, the mark stands in front of the flyer
    /// and the control stands down: a tap anywhere on the row is the choice,
    /// and a heart that still un-favorited would be a second, contradictory
    /// way to take the same event out.
    var isSelecting = false
    var isSelected = false
    var open: () -> Void
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    if isSelecting {
                        SelectionMark(isSelected: isSelected)
                    }

                    FlyerThumbnail(url: event.imageURL, width: 38, cornerRadius: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .scalingFont(size: 14, weight: .semibold)
                            .lineLimit(1)
                        Text(verbatim: "\(event.shown(on: timeDisplay).dayLine) · \(event.venue)")
                            .scalingFont(size: 11.5)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !isSelecting { control }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // A row inside its card rather than a card of its own.
        .marksEventBeside(event.id, cornerRadius: 20)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 66) }
        }
    }
}

/// A performer out of one of the site's lists — the search, the ranking, the
/// directory. Opening one lists everything they are billed on.
struct PerformerRow: View {
    let performer: PerformerProfile
    /// Where the ranking places them, ahead of the name.
    var rank: Int?

    var body: some View {
        NavigationLink(value: PerformerLink.profile(performer)) {
            HStack(spacing: 13) {
                if let rank {
                    Text(rank, format: .number)
                        .scalingFont(size: 13, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 26, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(performer.name)
                        .scalingFont(size: 14.5, weight: .semibold)
                        .lineLimit(1)
                    if let reading = performer.reading {
                        Text(reading)
                            .scalingFont(size: 12)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let fans = performer.fanCount {
                    Text("^[\(fans) fan](inflect: true)")
                        .scalingFont(size: 11.5, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .scalingFont(size: 11, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
        }
        .buttonStyle(.plain)
        .panel()
    }
}

/// A hall out of one of the site's lists — the venue search, a prefecture of
/// its directory. Opening one reads its own page.
struct VenueRow: View {
    let place: PlaceListing

    var body: some View {
        NavigationLink(value: VenueLink.place(place)) {
            HStack(spacing: 13) {
                Image(systemName: "mappin.and.ellipse")
                    .scalingFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.brandTint)
                    .frame(width: 18)
                Text(place.name)
                    .scalingFont(size: 14.5, weight: .semibold)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .scalingFont(size: 11, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
        }
        .buttonStyle(.plain)
        .panel()
    }
}

/// One followed performer: who they are, what they have coming, and the mark
/// that stops following them.
///
/// Shared by the Me card and the full list behind its See All. The unfollow
/// button sits beside the link rather than inside it, and is the same
/// circular control, for the reasons ``FavoriteEventRow`` gives.
struct FollowedPerformerRow: View {
    @Environment(EventStore.self) private var store
    @Environment(FollowedDates.self) private var followed

    /// What stands where these rows would, when there are none — for the
    /// reason ``FavoriteEventRow/emptyNote`` gives.
    static let emptyNote: LocalizedStringKey =
        "Follow a performer from their page to keep them here. It stays in your library and is never written back to Eventernote."

    let performer: PerformerProfile
    var showsDivider = false
    /// While the screen is picking rows, the row chooses rather than pushes,
    /// for the reason ``FavoriteEventRow`` gives.
    var isSelecting = false
    var isSelected = false
    /// What a tap does while picking. Unused otherwise.
    var choose: () -> Void = {}

    @State private var isConfirmingUnfollow = false

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Button(action: choose) {
                    HStack(spacing: 12) {
                        SelectionMark(isSelected: isSelected)
                        name
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: PerformerLink.profile(performer)) {
                    name.contentShape(.rect)
                }
                .buttonStyle(.plain)

                // Asked first, as the list's own Unfollow asks: the row goes
                // with the follow, on every device, and a performer followed
                // in Eventrail alone does not come back with a refresh. The
                // page's Follow button asks nothing, being its own undo.
                Button {
                    isConfirmingUnfollow = true
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.trackAttended)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .circlePanel()
                .accessibilityLabel("Stop following")
                .confirmationDialog("Stop following them?", isPresented: $isConfirmingUnfollow,
                                    titleVisibility: .visible) {
                    Button("Unfollow", role: .destructive) {
                        withAnimation(.snappy) { store.unfollow(performer) }
                    }
                    Button("Keep following", role: .cancel) {}
                } message: {
                    Text("Their dates stop appearing in Following, on this device and on your other devices. Anyone your Eventernote account still favorites comes back on the next refresh.")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 16) }
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: performer.name)
                .scalingFont(size: 14, weight: .semibold)
                .lineLimit(1)
            detail
                .scalingFont(size: 11.5)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The kana reading the site prints, and what they have coming — but only
    /// once their listing has actually been read. A count of zero beside
    /// somebody whose page has not answered yet would be a claim the app
    /// cannot make.
    private var detail: Text {
        let events: Text
        switch followed.count(for: performer) {
        case .none: events = Text("Reading their events…")
        case 0: events = Text("No events published yet")
        case let count?: events = Text("^[\(count) upcoming event](inflect: true)")
        }
        guard let reading = performer.reading else { return events }
        return Text("\(reading) · \(events)")
    }
}

/// Opens a hall in Maps, however well it has been placed.
///
/// The map item wherever ``VenuePlaces`` placed it, so Maps opens the point on
/// the map — the hall's own card, its pin, its directions — rather than running
/// a search for the name and leaving the reader to pick the right one out of a
/// list of near misses. A hall Maps has not placed still falls back to that
/// search, which is the best there is to offer for it.
///
/// Two screens send the reader to Maps — an event's sheet and the hall's own
/// page — and both do it from the map and from a Directions button, so the rule
/// is written once here rather than four times between them.
enum VenueDirections {
    static func open(
        _ venue: String, at place: VenuePlaces.Placing?, directions: Bool, with openURL: OpenURLAction
    ) {
        if let place {
            var options: [String: Any] = [:]
            if directions {
                options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDefault
            }
            place.item.openInMaps(launchOptions: options)
        } else if let url = searchURL(venue, directions: directions) {
            openURL(url)
        }
    }

    /// The hall by name, for Maps to find for itself — as a query value, so
    /// an `&` or a `+` in it is part of the name rather than the end of the
    /// query or a space: HMV&BOOKS SHIBUYA was searched for as "HMV".
    static func searchURL(_ venue: String, directions: Bool) -> URL? {
        guard !venue.isEmpty, var components = URLComponents(string: "https://maps.apple.com/")
        else { return nil }
        components.setQuery([URLQueryItem(name: directions ? "daddr" : "q", value: venue)])
        return components.url
    }
}

/// The venue, drawn where it is.
///
/// Eventernote publishes an address and no coordinate, so the hall is looked up
/// in ``VenuePlaces`` — the same lookup, and the same kept answers, the calendar
/// mirror uses, so whichever of the three asks first pays for it. An event's
/// sheet and a hall's own page both do the asking, because the same answer is
/// what their Directions button opens.
///
/// Until that comes back the panel says it is looking, on plain ground: a map
/// that cannot say where the place is would be worse than not drawing one. Once
/// it has come back with nothing, the panel says so — which of the two it was,
/// since a hall nobody has is settled and a search that did not get through is
/// worth another try — rather than going on looking like the answer is still on
/// its way.
///
/// It takes the hall's name rather than the event at it: ``VenueView`` draws
/// the same map with no event in front of it, and the name is all the pin was
/// ever labelled with.
struct VenueMap: View {
    /// The hall as Eventernote names it, which is the pin's label.
    let venue: String
    /// How the lookup came out, and nil while it is still being asked.
    let lookup: VenuePlaces.Lookup?
    /// Opens the hall in Maps. A tap anywhere on the map does it, which is
    /// where panning around belongs.
    let open: () -> Void
    /// Asks again, after a search that did not get through.
    let retry: () -> Void

    /// Close enough to show which block the hall is on, far enough to show the
    /// station or the road that gets the reader there.
    /// How much ground the map shows. Wide enough that the hall and the
    /// streets naming it are both in the frame.
    private static let span: CLLocationDistance = 700

    var body: some View {
        Group {
            switch lookup {
            case .placed(let place):
                map(around: place.item.location.coordinate, uncertainty: place.uncertainty)
                    .accessibilityLabel("Venue map")
            case nil:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Finding the venue on the map…")
                        .scalingFont(size: 13, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
            case .unplaced:
                notice("Couldn't find this venue on the map")
            case .failed:
                notice("Couldn't load the venue's location", retrying: true)
            case .noHall:
                // Nothing was looked for, and the line under the map already
                // says why — the hall is still to be announced, or the event
                // is not at one.
                Image(systemName: "mappin.slash")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 150)
    }

    /// The panel once the lookup has come back with nothing: in place of the
    /// pin, a pin struck through and the reason under it — and, after a search
    /// that did not get through, a way to ask again.
    private func notice(_ message: LocalizedStringKey, retrying: Bool = false) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(message)
                .scalingFont(size: 13, weight: .semibold)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if retrying {
                Button(action: retry) {
                    Text("Try Again")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.brandTint)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .capsulePanel()
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary)
    }

    /// Fixed rather than scrollable: this sits inside a sheet that scrolls, and
    /// a map that swallowed the drag would trap it. A tap opens Maps proper,
    /// which is where panning around belongs.
    /// A hall placed by its address rather than by its own listing sits at the
    /// middle of its block, and the door can be three hundred metres off that
    /// — which at the ordinary span puts it against the edge of the frame or
    /// past it. So the frame opens up by what the placing is unsure of, twice
    /// over, and the hall stays in the picture. An exactly placed hall is
    /// unaffected: its uncertainty is zero.
    private func map(around coordinate: CLLocationCoordinate2D,
                     uncertainty: CLLocationDistance) -> some View {
        let span = Self.span + uncertainty * 2
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: span,
            longitudinalMeters: span
        )
        return Map(initialPosition: .region(region), interactionModes: []) {
            Annotation(venue, coordinate: coordinate) { pin }
                .annotationTitles(.hidden)
        }
        .allowsHitTesting(false)
        .overlay {
            Button(action: open) { Color.clear.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the venue in Maps")
        }
    }

    private var pin: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(Color.favorite)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A read from Eventernote that did not land, said underneath what is still on
/// screen rather than in place of it.
///
/// Two screens refresh on their own once what they hold is stale — the
/// Following tab and an event's sheet — and either can be refused, most often
/// for asking too often. Neither throws away what it had when that happens, so
/// the reader is told two things: why nothing new arrived, and that what they
/// are looking at is the last copy that did.
struct RefreshFailureNote: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .scalingFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.favorite)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: message)
                    .scalingFont(size: 12.5, weight: .semibold)
                Text("Showing what was read before.")
                    .scalingFont(size: 11.5)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .panel()
    }
}

extension View {
    /// An event's row in a grouped `List` of panels — My Events, Following,
    /// Record Tickets: set in at ``GroupHeader/rowInsets`` under its month, on
    /// the wash rather than a cell's background, and with no separator, since
    /// each row is a panel of its own.
    func groupedEventRow() -> some View {
        listRowInsets(GroupHeader.rowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
