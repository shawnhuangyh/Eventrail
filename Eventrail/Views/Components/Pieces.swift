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
