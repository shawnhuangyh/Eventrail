import SwiftUI

/// Flyer, title, venue and timing — the part every event row shares.
struct EventRowContent<Trailing: View>: View {
    let event: Event
    /// Shown after the date: the start time in the library, the listed head
    /// count in search results.
    let detail: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            FlyerThumbnail(url: event.imageURL)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.venue)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(event.dayLine)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 3, height: 3)
                    detail
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(12)
    }
}

/// A row in the reader's own library. Tapping it opens the event.
struct LibraryRow: View {
    @Environment(EventStore.self) private var store

    let event: Event
    let open: () -> Void

    /// Eventernote often announces an event months before it publishes a
    /// start time, so the row says so rather than inventing one.
    private var detail: Text {
        event.timeLine.map { Text(verbatim: $0) } ?? Text("Time to be announced")
    }

    var body: some View {
        Button(action: open) {
            EventRowContent(event: event, detail: detail) {
                VStack(alignment: .trailing) {
                    StatusBadge(status: store.status(for: event))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
        .accessibilityHint("Opens the event")
    }
}

#Preview {
    List {
        LibraryRow(event: PreviewData.events[0], open: {})
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .washBackground()
    .environment(EventStore.preview)
}
