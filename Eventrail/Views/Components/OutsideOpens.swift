import SwiftUI

/// What the app has been asked to open from outside it — an event, from its
/// Live Activity tapped; a lottery round, from its results-day reminder — and
/// where it is opened: over whatever the reader has up.
///
/// A sheet presented from the root while another sheet is up is one SwiftUI
/// does not present at all: a reminder tapped with an event's sheet open, as
/// eight in the evening often finds the reader, opened nothing, and left its
/// request standing. So the root and every sheet stand ready to present
/// (``View/opensFromOutside()``), each at the depth it was presented at, and
/// the frontmost takes the request — ranked as ``RefreshNotices`` ranks its
/// overlays. What the reader had up stays under it, where they left it.
@Observable
final class OutsideOpens {
    /// What is waiting to be opened, until the frontmost presenter takes it.
    fileprivate(set) var waiting: OutsideOpen?

    /// Every presenter on screen, by how many sheets deep it stands.
    @ObservationIgnored fileprivate var standing: [UUID: Int] = [:]

    func open(_ request: OutsideOpen) {
        waiting = request
    }

    /// The presenter that takes a request: the deepest, and one of two at a
    /// depth — a sheet going as another comes — by a fixed rule.
    fileprivate var front: UUID? {
        standing.max { ($0.value, $0.key.uuidString) < ($1.value, $1.key.uuidString) }?.key
    }

    fileprivate func take() -> OutsideOpen? {
        defer { waiting = nil }
        return waiting
    }
}

/// One thing opened from outside the app.
enum OutsideOpen: Identifiable {
    /// The event's sheet.
    case event(Event)
    /// The ticket sheet, on the round's own page.
    case round(LotteryRow)

    var id: String {
        switch self {
        case .event(let event): "event/\(event.id)"
        case .round(let row): "round/\(row.id)"
        }
    }
}

extension EnvironmentValues {
    /// How many sheets deep a view stands — raised by every presenter
    /// (``View/opensFromOutside()``) for what it holds and what it presents.
    @Entry var outsideOpenDepth = 0
}

extension View {
    /// Stands ready to open what the app is asked to open from outside it
    /// (``OutsideOpens``), where this is the frontmost thing on screen.
    ///
    /// On the root, and on the root of every view shown as a sheet: one left
    /// without it is a sheet a Live Activity or a reminder tapped while it is
    /// up opens nothing over.
    func opensFromOutside() -> some View {
        modifier(OutsideOpenPresenter())
    }
}

private struct OutsideOpenPresenter: ViewModifier {
    @Environment(OutsideOpens.self) private var opens: OutsideOpens?
    @Environment(EventStore.self) private var store: EventStore?
    @Environment(\.outsideOpenDepth) private var depth

    @State private var id = UUID()
    /// What this presenter took, held here rather than read off ``opens``:
    /// the sheet it presents stands in front of it the moment it appears,
    /// and a sheet bound to whoever is frontmost would close as it opened.
    @State private var shown: OutsideOpen?

    func body(content: Content) -> some View {
        content
            .onAppear {
                opens?.standing[id] = depth
                take()
            }
            .onDisappear { opens?.standing[id] = nil }
            .onChange(of: opens?.waiting?.id) { take() }
            .sheet(item: $shown) { open in
                switch open {
                case .event(let event):
                    EventDetailView(event: event)
                case .round(let row):
                    TicketDetailsView(event: row.event, tracking: store?.tracking(for: row.event) ?? Tracking(),
                                      opening: row.entry)
                }
            }
            // Outermost, so what this holds and what it presents both stand
            // a sheet deeper than it does.
            .environment(\.outsideOpenDepth, depth + 1)
    }

    private func take() {
        guard let opens, opens.waiting != nil, opens.front == id else { return }
        shown = opens.take()
    }
}
