import SwiftUI

/// What the app has been asked to open from outside it — an event, from its
/// Live Activity tapped or handed off from another device (``EventHandoff``);
/// a lottery round, from its results-day reminder; an event, a performer or a
/// hall found in Spotlight or asked for through Siri or Shortcuts
/// (``SpotlightIndex``, ``IntentOpens``) — and where it is opened: over
/// whatever the reader has up.
///
/// A sheet presented from the root while another sheet is up is one SwiftUI
/// does not present at all: a reminder tapped with an event's sheet open, as
/// eight in the evening often finds the reader, opened nothing, and left its
/// request standing. So the root and every sheet stand ready to present
/// (``View/opensFromOutside()``), each at the depth it was presented at, and
/// the frontmost takes the request — ranked as ``RefreshNotices`` ranks its
/// overlays. What the reader had up stays under it, where they left it.
///
/// A request stands until its sheet is on screen, not only until a presenter
/// has asked for it: a presenter knows the sheets in front of it and nothing
/// else, and a sheet asked for while an alert, a popover, Quick Look, a share
/// sheet or the Welcome screen replayed from Settings is up is one SwiftUI
/// does not present either. Let go of as it was asked for, that request
/// opened nothing once whatever stood in front was put away. So the frontmost
/// presenter asks again each second until the sheet appears.
@Observable
final class OutsideOpens {
    /// What is waiting to be opened, until the frontmost presenter takes it.
    fileprivate(set) var waiting: OutsideOpen?

    /// Every presenter on screen, by how many sheets deep it stands.
    @ObservationIgnored fileprivate var standing: [UUID: Int] = [:]
    /// The presenter that has asked for ``waiting`` and not yet seen it on
    /// screen. One at a time: the sheet it asked for holds a presenter of its
    /// own, which stands in front as it appears and would otherwise open the
    /// same request again over it.
    @ObservationIgnored fileprivate var claimant: UUID?

    func open(_ request: OutsideOpen) {
        // The same request tapped twice is still the one being presented.
        if waiting?.id != request.id { claimant = nil }
        waiting = request
    }

    /// The presenter that takes a request: the deepest, and one of two at a
    /// depth — a sheet going as another comes — by a fixed rule.
    fileprivate var front: UUID? {
        standing.max { ($0.value, $0.key.uuidString) < ($1.value, $1.key.uuidString) }?.key
    }

    /// `open`, on screen: the request is answered.
    fileprivate func delivered(_ open: OutsideOpen) {
        guard waiting?.id == open.id else { return }
        claimant = nil
        waiting = nil
    }
}

/// One thing opened from outside the app.
enum OutsideOpen: Identifiable {
    /// The event's sheet.
    case event(Event)
    /// The ticket sheet, on the round's own page.
    case round(LotteryRow)
    /// A performer's page, from Spotlight or Siri, in a sheet of its own.
    case performer(PerformerLink)
    /// A hall's page, the same way.
    case venue(VenueLink)

    var id: String {
        switch self {
        case .event(let event): "event/\(event.id)"
        case .round(let row): "round/\(row.id)"
        case .performer(let link): "performer/\(link)"
        case .venue(let link): "venue/\(link)"
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

    /// How long a sheet asked for has to appear before it is asked for again.
    private static let retry: Duration = .seconds(1)

    func body(content: Content) -> some View {
        content
            .onAppear {
                opens?.standing[id] = depth
                take()
            }
            .onDisappear {
                opens?.standing[id] = nil
                if opens?.claimant == id { opens?.claimant = nil }
            }
            .task(id: opens?.waiting?.id) { await keepTaking() }
            .sheet(item: $shown) { open in
                Group {
                    switch open {
                    case .event(let event):
                        EventDetailView(event: event)
                    case .round(let row):
                        TicketDetailsView(event: row.event, tracking: store?.tracking(for: row.event) ?? Tracking(),
                                          opening: row.entry)
                    case .performer(let link):
                        OutsidePage { PerformerView(link: link) }
                    case .venue(let link):
                        OutsidePage { VenueView(link: link) }
                    }
                }
                .onAppear { opens?.delivered(open) }
            }
            // Outermost, so what this holds and what it presents both stand
            // a sheet deeper than it does.
            .environment(\.outsideOpenDepth, depth + 1)
    }

    private func take() {
        guard let opens, let waiting = opens.waiting, opens.claimant == nil, opens.front == id else { return }
        opens.claimant = id
        shown = waiting
    }

    /// Asks for the waiting request, and again each ``retry`` until it is on
    /// screen. Asked for and not there a second later, something this cannot
    /// see stood in front — an alert, a popover, a share sheet — and the
    /// request is let go of here and asked for afresh, by whichever presenter
    /// is frontmost by then.
    private func keepTaking() async {
        while let opens, opens.waiting != nil, !Task.isCancelled {
            take()
            try? await Task.sleep(for: Self.retry)
            guard !Task.isCancelled else { return }
            if opens.waiting != nil, opens.claimant == id {
                opens.claimant = nil
                shown = nil
                // A moment with nothing asked for, so SwiftUI sees the
                // request go and come back: put back in the same turn, it
                // would see no change and ask for nothing.
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

/// A performer's or a hall's page opened from outside the app, as a sheet with
/// a stack of its own — as an event's sheet holds one for a performer billed
/// on it, so a name or an event on the page opens inside it.
///
/// The pages draw their own notices above their bars; the See All behind
/// either has no bar and draws none, so the stack draws them there.
private struct OutsidePage<Page: View>: View {
    @ViewBuilder let page: Page

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            page
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
                .venueDestination()
        }
        .refreshNotices(showing: !path.isEmpty)
        .refreshNoticesInSheet()
        .presentationDragIndicator(.visible)
        .opensFromOutside()
    }
}
