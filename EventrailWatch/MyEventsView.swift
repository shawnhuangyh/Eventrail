import SwiftUI
import WidgetKit

/// The watch app's front: the library's events still to come, soonest first,
/// and — through the list button every page carries — the event picked from
/// it, in three pages (``EventPagesView``).
///
/// A split view rather than a stack, as the design has it: the pages are the
/// app, and the list is where an event is loaded into them. Opened from the
/// Live Activity in the Smart Stack, it goes straight to that event's
/// Countdown.
struct MyEventsView: View {
    @Environment(WatchLibraryStore.self) private var store
    @State private var selection: WatchEvent.ID?
    @State private var page = EventPage.countdown

    var body: some View {
        NavigationSplitView {
            list
                .navigationTitle("My Events")
        } detail: {
            if let selection, let event = store.event(id: selection) {
                EventPagesView(event: event, showsLocalTime: store.showsLocalTime, page: $page)
            }
        }
        // A card tapped opens on the first page, wherever the last one was
        // left.
        .onChange(of: selection) { page = .countdown }
        // An event taken out of the library on the phone leaves nothing to
        // show.
        .onChange(of: store.library) {
            if let selection, store.event(id: selection) == nil { self.selection = nil }
        }
        .onOpenURL { url in show(Self.eventID(in: url)) }
        // What the system hands over where an activity carried no link —
        // every one of this app's does, so this is only a fallback.
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
            let moments = store.events(at: .now).map { EventMoment($0, showsLocalTime: store.showsLocalTime, at: .now) }
            let current = moments.first { $0.event.hasTicket && $0.stage != nil && $0.stage != .wrapped }
                ?? moments.first { $0.daysAway == 0 }
            show(current?.event.id)
        }
    }

    private var list: some View {
        let changes = store.events(at: .now)
            .flatMap { EventMoment($0, showsLocalTime: store.showsLocalTime, at: .now).changes }
        return TimelineView(StageSchedule(changes: changes, step: 60)) { context in
            let events = store.events(at: context.date)
            if store.library == nil {
                ContentUnavailableView("Open Eventrail on Your iPhone", systemImage: "iphone",
                                       description: Text("Your events come from the app on your iPhone."))
            } else if events.isEmpty {
                ContentUnavailableView("No Upcoming Events", systemImage: "calendar",
                                       description: Text("Events you add on your iPhone appear here."))
            } else {
                List(selection: $selection) {
                    ForEach(events) { event in
                        NavigationLink(value: event.id) {
                            EventCard(moment: EventMoment(event, showsLocalTime: store.showsLocalTime, at: context.date))
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(EventCard.background)
                                .strokeBorder(.white.opacity(event.id == selection ? 0.45 : 0), lineWidth: 1.5)
                        )
                    }
                }
            }
        }
    }

    private func show(_ id: WatchEvent.ID?) {
        guard let id, store.event(id: id) != nil else { return }
        selection = id
        page = .countdown
    }

    /// The event a link to its Eventernote page names — what the Live
    /// Activity carries.
    private static func eventID(in url: URL) -> WatchEvent.ID? {
        guard url.host() == "www.eventernote.com" else { return nil }
        let path = url.pathComponents
        guard path.count == 3, path[1] == "events", !path[2].isEmpty else { return nil }
        return path[2]
    }
}

/// One event in My Events: the title beside the flyer, the hall, on the day
/// what the event is doing, and the date.
struct EventCard: View {
    let moment: EventMoment

    static let background = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x26 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            HStack(alignment: .top, spacing: 6) {
                Text(verbatim: moment.event.title)
                    .font(.system(size: 15.5, weight: .medium))
                    .kerning(-0.155)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Flyer(event: moment.event)
                    .frame(width: 28, height: 28)
                    .clipShape(.circle)
            }
            Text(verbatim: moment.event.venue)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if let headline = moment.headline {
                headline
                    .font(.system(size: 14.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(moment.tint)
                    .lineLimit(1)
            }
            Text(verbatim: moment.dateLine)
                .font(.system(size: 13.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(EdgeInsets(top: 9, leading: 13, bottom: 12, trailing: 11))
    }
}

#if DEBUG
#Preview("My Events") {
    MyEventsView()
        .environment(WatchLibraryStore(library: .preview))
}

#Preview("Nothing sent yet") {
    MyEventsView()
        .environment(WatchLibraryStore(library: nil))
}
#endif
