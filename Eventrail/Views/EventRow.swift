import SwiftUI

/// Flyer, title, venue and timing — the part every event row shares.
struct EventRowContent<Billing: View, Trailing: View>: View {
    let event: Event
    /// Shown after the date: the start time in the library, the listed head
    /// count in search results.
    let detail: Text
    /// Shown above the title where the row belongs to somebody rather than
    /// standing on its own — whose date this is, on the Following list. Empty
    /// everywhere the list is already about one thing.
    @ViewBuilder var billing: Billing
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // Centred, not top-aligned: the flyer is a fixed 5:7 block and the text
        // beside it is one line shorter whenever the title fits on one line, so
        // pinning both to the top left the row ragged along the bottom.
        HStack(alignment: .center, spacing: 13) {
            FlyerThumbnail(url: event.imageURL)

            VStack(alignment: .leading, spacing: 5) {
                billing
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

extension EventRowContent where Billing == EmptyView {
    /// A row about the event alone, which is every list but Following.
    init(event: Event, detail: Text, @ViewBuilder trailing: () -> Trailing) {
        self.init(event: event, detail: detail, billing: { EmptyView() }, trailing: trailing)
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
                // Held apart over the row's full height rather than packed into
                // the middle of it: the badge belongs beside the title it
                // qualifies, and the chevron in the corner it points out of.
                VStack(alignment: .trailing, spacing: 0) {
                    StatusBadge(status: store.status(for: event))
                    Spacer(minLength: 7)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 4)
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
