import SwiftUI

/// Flyer, title, venue and timing — the part every event row shares.
struct EventRowContent<Billing: View, Trailing: View>: View {
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let event: Event
    /// Shown after the date: the start time in the library, the listed head
    /// count in search results.
    let detail: Text
    /// The line under the title. Where the event is, in every list that could
    /// be about anywhere — and who is on it where the list is already one
    /// hall's, since there the venue is the one thing every row has in common.
    var caption: Text
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
                caption
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(event.shown(on: timeDisplay).dayLine)
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

extension EventRowContent {
    /// The venue under the title, which is what places a row in every list that
    /// is not already about one place.
    init(
        event: Event, detail: Text,
        @ViewBuilder billing: () -> Billing, @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(event: event, detail: detail, caption: Text(event.venue),
                  billing: billing, trailing: trailing)
    }
}

extension EventRowContent where Billing == EmptyView {
    /// A row about the event alone, which is every list but Following.
    init(event: Event, detail: Text, caption: Text? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(event: event, detail: detail, caption: caption ?? Text(event.venue),
                  billing: { EmptyView() }, trailing: trailing)
    }
}

extension Event {
    /// What a row says after the day.
    ///
    /// Eventernote routinely announces an event months before it publishes a
    /// start time, and a performer's own listing prints one for some rows and
    /// not others, so a row says so rather than inventing an hour. Three lists
    /// each said it in their own identical copy; a search result has one more
    /// thing to offer and says so for itself.
    var timeDetail: Text {
        timeLine.map { Text(verbatim: $0) } ?? Text("Time to be announced")
    }
}

/// A row in the reader's own library. Tapping it opens the event.
struct LibraryRow: View {
    @Environment(EventStore.self) private var store
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let event: Event
    /// Why the reader has not looked at this event yet, for the tag above the
    /// title — nil where they have, and on every event already past.
    var unread: FollowingUnread? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            EventRowContent(event: event, detail: event.shown(on: timeDisplay).timeDetail) {
                // Above the title, where Following carries it after the names:
                // a library row has no billing line to put it on the end of.
                if let unread { UnreadTag(unread: unread) }
            } trailing: {
                // Held apart over the row's full height rather than packed into
                // the middle of it: the badge belongs beside the title it
                // qualifies, and the chevron in the corner it points out of.
                VStack(alignment: .trailing, spacing: 0) {
                    StatusBadge(status: store.status(for: event))
                    Spacer(minLength: 7)
                    HStack(spacing: 7) {
                        // Only on the events still ahead, and so only in this
                        // row: the library is the one list the reader keeps
                        // because they mean to be there. Every other list on
                        // the app is somebody else's or somewhere else's, and
                        // counting down to a date nobody has kept would be the
                        // app deciding it mattered.
                        if let days = event.daysAway { DaysAway(days: days) }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            // The row is only as tappable as it is drawn: a title that fits on
            // one line leaves the gap between it and the badge column hittable
            // by nothing, which on an iPad is half the row. The panel behind it
            // is the row, so the whole rectangle opens the event.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassPanel(interactive: true)
        .accessibilityHint("Opens the event")
    }
}

/// One event out of a performer's or a hall's listing — on either page and on
/// the screen behind its See All. The badge appears only where the reader has
/// recorded something; an untracked row has nothing to say there.
struct AppearanceRow: View {
    @Environment(EventStore.self) private var store
    /// Which clock the day and times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue

    let event: Event
    /// Whose listing this row is in, which decides the line under the title:
    /// see ``EventRowContent/caption``.
    let subject: ListingSubject
    let open: () -> Void

    /// The bill, for a hall's own listing. Eventernote prints one name per
    /// line; a row has one line, so they are run together on it.
    private var caption: Text? {
        guard case .venue = subject, !event.performers.isEmpty else { return nil }
        return Text(verbatim: event.performers.map(\.name).joined(separator: "・"))
    }

    var body: some View {
        Button(action: open) {
            EventRowContent(event: event, detail: event.shown(on: timeDisplay).timeDetail, caption: caption) {
                let status = store.status(for: event)
                HStack(spacing: 8) {
                    if status != .untracked { StatusBadge(status: status) }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 5)
            // The whole row, not just the words on it — see `LibraryRow`.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
    .library(EventStore.preview)
}
