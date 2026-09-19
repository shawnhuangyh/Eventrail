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
                AsyncImage(url: url) { image in
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
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }
}

/// One cell of a three-up statistics row.
struct StatTile: View {
    /// The two arrangements the design draws this tile in.
    enum Layout {
        /// A number with its caption under it. Three of these read as one row
        /// of counts, which is what the Me and performer screens show.
        case caption
        /// The name on top beside the dot, the value under it, and a line
        /// under that qualifying the value. An event's facts are three
        /// different things rather than three counts, so each one is named
        /// before it is read.
        case field
    }

    let tint: Color
    /// A formatted number or time, so not a localizable key.
    let value: String
    /// A second line under the value, for a fact that only qualifies it — the
    /// hour a performance ends under the hour it starts. Nil where the public
    /// page published nothing to put there.
    var sub: Text?
    let label: LocalizedStringKey
    var layout: Layout = .caption

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 15)
            .glassPanel(cornerRadius: 24)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .caption:
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
        case .field:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(value)
                    .font(.system(size: 25, weight: .bold))
                    .kerning(-0.75)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // The three tiles stand as one row, so a tile with nothing to
                // qualify its value keeps the line rather than standing shorter
                // than the two beside it.
                (sub ?? Text(verbatim: " "))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// The section header pill that stands over a month of events.
///
/// It reads the same wherever it is used, which takes saying twice: a `List`
/// section header arrives with the system's own uppercased, secondary styling,
/// and a header pinned over a scrolling list has the rows passing behind it.
/// Both are answered here rather than at each call site, so the Events tab and
/// the Following tab cannot drift apart again.
struct GroupHeader: View {
    /// A formatted month, an imported artist name, or the filter's own name.
    let label: Text
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            label
                .font(.system(size: 12, weight: .bold))
                .kerning(0.24)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassCapsule()
                // Under the glass rather than over it: the pill refracts an
                // opaque slice of the wash, so a flyer scrolling behind a
                // pinned header cannot darken the month it is covering.
                .background(Color.washBase, in: .capsule)
            Text("^[\(count) event](inflect: true)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .textCase(nil)
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
    }
}

/// Lays chips out left to right, wrapping to a new line when they run out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
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
            y += row.height + spacing
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
/// The heart is a sibling of the row's own button rather than a button inside
/// its label. Nested, the row's tap target covers it and a tap on the heart
/// opens the event instead of un-favoriting it. It is the same circular glass
/// control the Following tab's rows carry, so the one gesture that takes a row
/// out of a list looks the same wherever the list is.
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
    /// Drawn above the row rather than below it, so a list ends on a row and
    /// not on a line.
    var showsDivider = false
    /// While the screen is picking rows, the mark stands in front of the flyer
    /// and the heart stands down: a tap anywhere on the row is the choice, and
    /// a heart that still un-favorited would be a second, contradictory way to
    /// take the same event out.
    var isSelecting = false
    var isSelected = false
    var open: () -> Void

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
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(verbatim: "\(event.dayLine) · \(event.venue)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !isSelecting {
                Button {
                    withAnimation(.snappy) { store.toggleFavorite(event) }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.favorite)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .accessibilityLabel("Remove from favorites")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 66) }
        }
    }
}

/// One followed performer: who they are, what they have coming, and the mark
/// that stops following them.
///
/// Shared by the Me card and the full list behind its See All. The unfollow
/// button sits beside the link rather than inside it, and wears the same
/// circular glass, for the reasons ``FavoriteEventRow`` gives.
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

                Button {
                    withAnimation(.snappy) { store.unfollow(performer) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.trackAttended)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .accessibilityLabel("Stop following")
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
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            detail
                .font(.system(size: 11.5))
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

    /// The hall by name, for Maps to find for itself.
    private static func searchURL(_ venue: String, directions: Bool) -> URL? {
        guard !venue.isEmpty,
              let query = venue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://maps.apple.com/?\(directions ? "daddr" : "q")=\(query)")
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
/// Until that comes back, and for a hall Maps does not have, the panel is the
/// pin on plain ground it has always been: a map that cannot say where the place
/// is would be worse than not drawing one.
///
/// It takes the hall's name rather than the event at it: ``VenueView`` draws
/// the same map with no event in front of it, and the name is all the pin was
/// ever labelled with.
struct VenueMap: View {
    /// The hall as Eventernote names it, which is the pin's label.
    let venue: String
    let place: VenuePlaces.Placing?
    /// Opens the hall in Maps. A tap anywhere on the map does it, which is
    /// where panning around belongs.
    let open: () -> Void

    /// Close enough to show which block the hall is on, far enough to show the
    /// station or the road that gets the reader there.
    /// How much ground the map shows. Wide enough that the hall and the
    /// streets naming it are both in the frame.
    private static let span: CLLocationDistance = 700

    var body: some View {
        Group {
            if let place {
                map(around: place.item.location.coordinate, uncertainty: place.uncertainty)
            } else {
                pin.background(.quaternary)
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Venue map")
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
