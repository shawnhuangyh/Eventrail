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
    /// what the page's close button does there. Nil everywhere else.
    @Entry var closeEventBeside: (() -> Void)?
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

    /// Whether the screen is parted: only by a fold running top to bottom.
    /// One running across leaves the list whole, and its events open as
    /// sheets — a list scrolls past a crease without anything sitting on it.
    private var isSplit: Bool { fold?.axis == .vertical }

    /// Whether `event` is shown as a sheet: while the list is on screen, and
    /// the screen is whole and staying so. Not while the Duo opens, where it
    /// would be drawn on the opened screen before its half was; and from a
    /// list out of sight, not until it is back.
    private var showsSheet: Bool { isShown && !isSplit && !isOpening }

    func body(content: Content) -> some View {
        FoldSplitLayout(fold: isSplit ? fold : nil) {
            if isSplit {
                pane
                    .castingShadowsToTheFold()
                    .standingAfterTheFold()
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
        .onDisappear { isShown = false }
        .onGeometryChange(for: CGRect.self) { proxy in
            let frame = proxy.frame(in: .global)
            let insets = proxy.safeAreaInsets
            return CGRect(x: frame.minX - insets.leading, y: frame.minY - insets.top,
                          width: frame.width + insets.leading + insets.trailing,
                          height: frame.height + insets.top + insets.bottom)
        } action: { canvas = $0 }
        .eventSheet(sheetItem)
        .onChange(of: event) { _, event in
            if showsSheet { sheetEvent = event }
        }
        // Nothing presented while the event has a half of its own to stand
        // in, or is about to: the sheet that was up goes as the Duo starts
        // to open, and its event moves across once the fold is read — and
        // back into a sheet as the half goes, or where the Duo opened onto
        // no half. At once, with no animation of its own.
        .onChange(of: showsSheet) { _, showsSheet in
            withTransaction(\.disablesAnimations, true) {
                sheetEvent = showsSheet ? event : nil
            }
        }
    }

    /// The sheet's item, which SwiftUI empties as a sheet goes: only where a
    /// sheet is up does that close the event. Where `sheetEvent` is already
    /// nil, the sheet was put away for the half, and it is only saying so.
    private var sheetItem: Binding<Event?> {
        Binding {
            sheetEvent
        } set: { item in
            guard item == nil, sheetEvent != nil else { return }
            sheetEvent = nil
            event = nil
        }
    }

    @ViewBuilder
    private var pane: some View {
        if let event {
            EventDetailView(event: event, presentation: .pane)
                // A sheet of its own each time, as a sheet would be: what one
                // event's page held — a translation, the clock picked on its
                // switch — is not carried over to the next.
                .id(event.id)
                .environment(\.closeEventBeside) {
                    withAnimation(.snappy) { self.event = nil }
                }
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
