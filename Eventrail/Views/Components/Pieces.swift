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
    let tint: Color
    /// A formatted number or time, so not a localizable key.
    let value: String
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
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 15)
        .glassPanel(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}

/// The section header pill on the Events list.
struct GroupHeader: View {
    /// A formatted month, an imported artist name, or the filter's own name.
    let label: Text
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            label
                .font(.system(size: 12, weight: .bold))
                .kerning(0.24)
                .textCase(nil)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassCapsule()
            Text("^[\(count) event](inflect: true)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .textCase(nil)
                .foregroundStyle(.tertiary)
        }
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
