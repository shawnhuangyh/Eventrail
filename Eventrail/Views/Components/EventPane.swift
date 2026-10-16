import SwiftUI

extension EnvironmentValues {
    /// The event open beside the list on an open iPhone Duo, for its row to
    /// be marked — see ``View/marksEventBeside(_:cornerRadius:)``. Nil
    /// everywhere else, where an event opens as a sheet over the list.
    @Entry var eventBeside: Event.ID?
    /// Whether a list stands in the half before an open iPhone Duo's fold,
    /// its events opening in the half after — where nothing the list puts in
    /// the bar may reach across the fold. See Search's scopes.
    @Entry var opensEventsBeside = false
    /// Puts away the event open beside the list, leaving its half empty —
    /// what the page's close button does there. Nil everywhere else, and
    /// while the page is tucked away (see ``EventPanePresenter``), where it
    /// puts nothing in the bar.
    @Entry var closeEventBeside: EnvironmentAction?
    /// Where an event's page says it has a sheet of its own up — see
    /// ``EventSheetsHold``. Set by every screen whose layout can take an
    /// event's page away: a list beside its event, and the Passport.
    @Entry var eventSheetsHold: EventSheetsHold?
}

/// An action handed down the environment, compared by who handed it down
/// rather than by what it does.
///
/// A closure cannot be compared, so one stored in the environment as it is
/// reads as changed with every update of the view that set it, and every view
/// reading it is drawn again — SwiftUI warns of it. This is the same action
/// for as long as its `id` is: whoever hands it down makes a new `id` only
/// when what it does changes.
nonisolated struct EnvironmentAction: Equatable, Sendable {
    let id: UUID
    let run: @MainActor () -> Void

    static func == (lhs: EnvironmentAction, rhs: EnvironmentAction) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor func callAsFunction() { run() }
}

/// The sheets the event's pages under one screen have up over themselves —
/// Ticket Details, the ticket stub — which a change of layout waits for.
///
/// A sheet goes with the view that presented it, and an event's page moves
/// between a sheet and a half as an iPad turns or a Duo opens, folds and
/// turns: the page goes, and the sheet over it with it. Ticket Details holds
/// a copy that only its checkmark writes back, so whatever had been changed
/// on it went too, with no word. So each page says here while it has one up
/// (``EventDetailView``), and the screen holds its layout still until it is
/// put away — see ``View/eventPane(_:)``.
@Observable
final class EventSheetsHold {
    private var holders: Set<UUID> = []

    /// Whether anything under the screen has a sheet up.
    var isHeld: Bool { !holders.isEmpty }

    /// Says whether the page or presenter `id` has a sheet up.
    func set(_ id: UUID, holding: Bool) {
        guard holders.contains(id) != holding else { return }
        if holding { holders.insert(id) } else { holders.remove(id) }
    }
}

extension View {
    /// Opens an event beside this screen where the iPhone Duo's fold runs down
    /// it, or an iPad held on its side is parted down its middle (``Fold``) —
    /// the list in the half before the fold, the event in the half after,
    /// as `DuoOpenEvents.dc.html` draws My Events — and as the sheet every list ends in
    /// everywhere else (``eventSheet(_:)``).
    ///
    /// For a screen that is a list of events and nothing wider: its rows fit
    /// one half, and the other is where they open. The Me tab and the Passport
    /// part themselves at the fold in their own ways instead.
    ///
    /// One source of truth either way, so the event in front stays in front
    /// as the Duo folds, opens and turns: the sheet showing `event` goes, and
    /// the half beside the list shows it, and the other way round — handed
    /// across with no animation of its own, since the screen changing is
    /// the system's to animate, and a sheet seen sliding away on the opened
    /// screen read as the event being closed and opened again.
    ///
    /// Not while the event's page has a sheet of its own up (``EventSheetsHold``):
    /// the page stays where it is until that is put away — a sheet stays a
    /// sheet over a screen that has parted, and a half going stays in place,
    /// out of sight, under the list laid out whole — and only then moves.
    ///
    /// Until a row is chosen the half is empty, and its close button empties
    /// it again: not the list's first event, as the design draws it, on
    /// Shawn's word. Shown there unchosen, it looked open, and folding the
    /// Duo — which carries over only what was chosen — put it away.
    func eventPane(_ event: Binding<Event?>) -> some View {
        modifier(EventPanePresenter(event: event))
    }

    /// Marks a row as the one whose event is open beside the list — the
    /// design's tinted panel with its ring. Goes before the row's glass, so
    /// the tint lies under the row's words rather than over them.
    func marksEventBeside(_ id: Event.ID, cornerRadius: CGFloat = 26) -> some View {
        modifier(BesideMark(id: id, cornerRadius: cornerRadius))
    }
}

private struct EventPanePresenter: ViewModifier {
    @Binding var event: Event?

    @State private var fold: Fold?
    /// The event the sheet shows: `event`, while the screen is whole.
    ///
    /// Kept apart from `event` because SwiftUI says a sheet has gone by
    /// writing nil through the binding it was presented with, however it
    /// went, and a moment after: a sheet put away as the half took its event
    /// over said so once the event was in the half, and emptied it. Only the
    /// reader putting away a sheet that is up closes its event — see
    /// ``sheetItem``.
    @State private var sheetEvent: Event?
    /// Whether a sheet this put away has yet to say so — see ``sheetItem``.
    @State private var awaitsReceipt = false
    /// Whether the Duo is opening, from closed, onto a screen whose fold is
    /// not known yet — see ``View/readingDuoOpening(into:fold:)``.
    @State private var isOpening = false
    /// Whether the list is on screen: not in a tab out of sight, nor under a
    /// page pushed over it. A sheet presented from a tab out of sight is
    /// drawn over the tab in front, and a list there is told nothing of the
    /// fold: one whose event was open beside it put the event up as a sheet
    /// over the Passport as the Duo folded and opened.
    @State private var isShown = false
    /// The whole screen in global coordinates, for the two halves' washes to
    /// draw one picture between them — see ``EnvironmentValues/washCanvas``.
    @State private var canvas: CGRect?
    /// The sheets the event's page has up over itself, and where it stood as
    /// the first went up: held there until the last is put away.
    @State private var sheetsHold = EventSheetsHold()
    @State private var held: Presentation?
    /// The hold of a screen this one stands inside — the list beside whose
    /// event's sheet this is pushed — which is held too while this has an
    /// event's sheet up: put away, it would take this one with it.
    @Environment(\.eventSheetsHold) private var outerHold
    @State private var id = UUID()

    /// Where the event stands: beside the list, or as a sheet over it.
    private struct Presentation: Equatable {
        var beside: Bool
        var sheet: Bool
    }

    /// Whether the screen is parted: only by a fold running top to bottom.
    /// One running across leaves the list whole, and its events open as
    /// sheets — a list scrolls past a crease without anything sitting on it.
    private var isParted: Bool { fold?.axis == .vertical }

    /// Where the screen as it stands puts the event: beside the list where it
    /// is parted; as a sheet while the list is on screen, and whole and
    /// staying so. Not while the Duo opens, where a sheet would be drawn on
    /// the opened screen before its half was; and from a list out of sight,
    /// not until it is back.
    private var wanted: Presentation {
        Presentation(beside: isParted, sheet: isShown && !isParted && !isOpening)
    }

    /// Where the event stands: where the screen puts it, or where it stood
    /// as its page put a sheet up, until that is put away.
    private var presentation: Presentation { held ?? wanted }

    /// Whether the screen is laid out in two halves: parted, with the event
    /// beside the list. A screen parted while the event's sheet holds one of
    /// its own up stays whole under it until it is put away.
    private var isSplit: Bool { isParted && presentation.beside }

    /// Whether the page beside the list is there but out of sight: the screen
    /// has gone whole while the page holds a sheet up, which goes with the
    /// page. It stays, at no size, until that sheet is put away.
    private var isTucked: Bool { presentation.beside && !isParted }

    private var showsSheet: Bool { presentation.sheet }

    func body(content: Content) -> some View {
        FoldSplitLayout(fold: isSplit ? fold : nil) {
            if presentation.beside {
                pane
                    .castingShadowsToTheFold()
                    .standingAfterTheFold()
                    .opacity(isTucked ? 0 : 1)
                    .allowsHitTesting(!isTucked)
                    .accessibilityHidden(isTucked)
            }
            // Last, and there whether or not the screen is parted, so the
            // list keeps its place and its state as the Duo opens and folds,
            // and the bar follows the list rather than the event.
            content
                .environment(\.eventBeside, isSplit ? event?.id : nil)
                .environment(\.opensEventsBeside, isSplit)
        }
        // The strip at the fold, between the halves' own washes.
        .background {
            if isSplit { WashBackground() }
        }
        .environment(\.washCanvas, isSplit ? canvas : nil)
        .readingFold(into: $fold)
        .readingDuoOpening(into: $isOpening, fold: fold)
        .onAppear { isShown = true }
        .onDisappear {
            isShown = false
            outerHold?.set(id, holding: false)
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            let frame = proxy.frame(in: .global)
            let insets = proxy.safeAreaInsets
            return CGRect(x: frame.minX - insets.leading, y: frame.minY - insets.top,
                          width: frame.width + insets.leading + insets.trailing,
                          height: frame.height + insets.top + insets.bottom)
        } action: { canvas = $0 }
        // The screen this stands inside is let go of once the sheet has
        // gone, not as it begins to go, for the reason an event's page lets
        // go of its own (``EventDetailView``).
        .eventSheet(sheetItem) {
            if sheetEvent == nil { outerHold?.set(id, holding: false) }
        }
        // Outside the sheet, so the page in it says here as well as the page
        // in the half.
        .environment(\.eventSheetsHold, sheetsHold)
        .onChange(of: event) { _, event in
            if showsSheet, !awaitsReceipt { sheetEvent = event }
        }
        // Nothing presented while the event has a half of its own to stand
        // in, or is about to: the sheet that was up goes as the Duo starts
        // to open, and its event moves across once the fold is read — and
        // back into a sheet as the half goes, or where the Duo opened onto
        // no half. At once, with no animation of its own.
        .onChange(of: showsSheet) { _, showsSheet in
            withTransaction(\.disablesAnimations, true) {
                if !showsSheet {
                    if sheetEvent != nil { awaitsReceipt = true }
                    sheetEvent = nil
                } else if !awaitsReceipt {
                    sheetEvent = event
                }
            }
        }
        .onChange(of: sheetsHold.isHeld) { _, isHeld in
            held = isHeld ? presentation : nil
        }
        .onChange(of: sheetEvent != nil) { _, isUp in
            if isUp { outerHold?.set(id, holding: true) }
        }
        // A receipt that never comes is not waited for long: SwiftUI has
        // been seen to send it up to a second late.
        .task(id: awaitsReceipt) {
            guard awaitsReceipt else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            receive()
        }
    }

    /// The sheet's item, which SwiftUI empties as a sheet goes: only where a
    /// sheet is up does that close the event.
    ///
    /// Where this put the sheet away itself, the nil is only SwiftUI saying
    /// so — up to a second later. A sheet brought back meanwhile, as an iPad
    /// is turned and turned back, or a Duo folded and opened again, would
    /// take it for the reader putting that one away, and close the event. So
    /// a sheet put away here is brought back only once the nil it is owed
    /// has come (``awaitsReceipt``), or a moment has passed without it.
    private var sheetItem: Binding<Event?> {
        Binding {
            sheetEvent
        } set: { item in
            guard item == nil else { return }
            if awaitsReceipt {
                receive()
                return
            }
            guard sheetEvent != nil else { return }
            sheetEvent = nil
            event = nil
        }
    }

    /// The sheet put away has said so: brought back if the screen wants it
    /// again by now.
    private func receive() {
        awaitsReceipt = false
        guard showsSheet, sheetEvent == nil, event != nil else { return }
        withTransaction(\.disablesAnimations, true) { sheetEvent = event }
    }

    @ViewBuilder
    private var pane: some View {
        if let event {
            EventDetailView(event: event, presentation: .pane)
                // A sheet of its own each time, as a sheet would be: what one
                // event's page held — a translation, the clock picked on its
                // switch — is not carried over to the next.
                .id(event.id)
                // Tucked away, it puts nothing in the bar.
                .environment(\.closeEventBeside, isTucked ? nil : EnvironmentAction(id: id) {
                    withAnimation(.snappy) { self.event = nil }
                })
        } else {
            ContentUnavailableView {
                Label("No Event Selected", systemImage: "calendar")
            } description: {
                Text("Choose an event to see it here.")
            }
        }
    }
}

private struct BesideMark: ViewModifier {
    @Environment(\.eventBeside) private var beside
    let id: Event.ID
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let isMarked = beside == id
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if isMarked { shape.fill(Color.brandTint.opacity(0.12)) }
            }
            .overlay {
                if isMarked {
                    shape.strokeBorder(Color.brandTint.opacity(0.55), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityAddTraits(isMarked ? .isSelected : [])
    }
}
