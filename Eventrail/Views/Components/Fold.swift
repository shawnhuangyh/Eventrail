import SwiftUI

/// Where the fold of an open iPhone Duo crosses a view, if it does.
///
/// Read from the system's own answer to the question — the `division` reserved
/// region iOS 27.1 publishes "where content should split into separate
/// regions, such as at the fold of a hinge" — rather than from a screen size,
/// so nothing here knows the Duo's dimensions, and an iPhone or an iPad,
/// which publish no division, never sees one. Read with the inactive regions
/// too: the design parts its screens at the fold whether the Duo is opened
/// flat or held half open like a book, and a list beside its event reads as
/// well either way.
///
/// A fold that runs top to bottom (`axis == .vertical`, the Duo open on its
/// side) puts two halves side by side, which is where a list and its event,
/// the Me cards' two columns and the Passport's two pages go. One that runs
/// across (the Duo turned upright) stacks them, which only the Me tab lays
/// out against.
nonisolated struct Fold: Equatable, Sendable {
    /// The strip content keeps out of, in the view's own coordinates —
    /// the crease and the margins the system keeps around it for anything a
    /// finger would have to land on.
    var frame: CGRect
    /// Which way the crease runs.
    var axis: Axis

    /// How narrow a half may be and still be laid out as one. A view smaller
    /// than the screen — a sheet, a popover — is crossed by the fold off
    /// centre or not at all, and parting it into a sliver and the rest would
    /// help nobody.
    static let leastHalf: CGFloat = 240

    /// The fold crossing the view `proxy` measures from one edge to the
    /// other, if one does.
    static func crossing(_ proxy: GeometryProxy) -> Fold? {
        guard #available(iOS 27.1, *) else { return nil }
        let bounds = CGRect(origin: .zero, size: proxy.size)
        for region in proxy.reservedRegions(kind: .division, options: .includeInactive) {
            if let fold = Fold(region.frame, in: bounds) { return fold }
        }
        return nil
    }

    /// The fold `frame` makes of a view of `bounds`, if it parts it into two
    /// halves of a usable size.
    init?(_ frame: CGRect, in bounds: CGRect) {
        if frame.height > frame.width {
            // Running top to bottom, it has to reach both edges to part the
            // view, and leave room on either side of it.
            guard frame.minY <= bounds.minY + 1, frame.maxY >= bounds.maxY - 1,
                  frame.minX - bounds.minX >= Self.leastHalf,
                  bounds.maxX - frame.maxX >= Self.leastHalf
            else { return nil }
            self.init(frame: frame, axis: .vertical)
        } else {
            guard frame.minX <= bounds.minX + 1, frame.maxX >= bounds.maxX - 1,
                  frame.minY - bounds.minY >= Self.leastHalf,
                  bounds.maxY - frame.maxY >= Self.leastHalf
            else { return nil }
            self.init(frame: frame, axis: .horizontal)
        }
    }

    init(frame: CGRect, axis: Axis) {
        self.frame = frame
        self.axis = axis
    }
}

extension View {
    /// Keeps `fold` up to date with the fold crossing this view — nil while
    /// none does.
    ///
    /// With animations off: a fold comes and goes as the Duo opens, folds
    /// and turns, which the system animates, and what the screen does about
    /// it — a sheet put away as its event moves into a half, or brought up
    /// as the half goes — happens at once rather than as a second animation
    /// after the system's. Seen sliding away on the opened screen, the
    /// sheet read as the event being closed and opened again.
    func readingFold(into fold: Binding<Fold?>) -> some View {
        onGeometryChange(for: Fold?.self) { Fold.crossing($0) } action: { new in
            withTransaction(\.disablesAnimations, true) { fold.wrappedValue = new }
        }
    }
}

extension View {
    /// Keeps `isOpening` true while an iPhone Duo opens: from the moment its
    /// hinge leaves closed, on a screen with no fold, until the screen it
    /// opens onto says where its fold is — or the hinge closes again, or a
    /// few seconds go by with neither.
    ///
    /// The fold is published only once the opened screen is laid out, well
    /// over a second after the hinge starts to move, and a sheet still up by
    /// then is drawn on the opened screen first — a form sheet in the middle
    /// of it, put away a moment later as its event took the half beside the
    /// list. A sheet that is to become a half is put away while this is true
    /// instead, as the Duo starts to open.
    func readingDuoOpening(into isOpening: Binding<Bool>, fold: Fold?) -> some View {
        modifier(DuoOpening(isOpening: isOpening, fold: fold))
    }
}

private struct DuoOpening: ViewModifier {
    @Binding var isOpening: Bool
    let fold: Fold?

    /// How long an opening is waited out without a fold: the Duo opened
    /// part of the way and held there, or a screen that publishes none.
    private static let patience: Duration = .seconds(3)

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .onHingeChange { old, new in
                    guard let hinge = new.hinge else { return }
                    if hinge.status == .closed {
                        isOpening = false
                    } else if old.hinge?.status == .closed, fold == nil {
                        isOpening = true
                    }
                }
                .onChange(of: fold) { _, fold in
                    if fold != nil { isOpening = false }
                }
                .task(id: isOpening) {
                    guard isOpening else { return }
                    try? await Task.sleep(for: Self.patience)
                    if !Task.isCancelled { isOpening = false }
                }
        } else {
            content
        }
    }
}

/// Two views either side of a fold that runs top to bottom: the **last** in
/// the half before it, the one before that in the half after, and nothing in
/// the strip between. With no fold the last takes the whole of the room and
/// the other none, so a view can stay last through a fold opening and closing
/// without losing its state.
///
/// Last, because a navigation bar over two scroll views follows only one of
/// them — the last laid out — and on the Duo's rail the title over the screen
/// shrinks away as that one scrolls, taking the top of everything under the
/// bar with it. The half before the fold is the one the title stands over,
/// so it is the one the bar follows; the half after keeps clear of the bar
/// (``View/standingAfterTheFold()``), or scrolling one half moved the other.
///
/// Leading and trailing, rather than left and right: the system mirrors a
/// reserved region's frame for a right-to-left language, and a `Layout`'s
/// placements are mirrored with it.
struct FoldSplitLayout: Layout {
    /// Where the fold crosses, in the coordinates of the view laid out — see
    /// ``Fold/crossing(_:)``. Nil, or a fold running across, lays out one view.
    var fold: Fold?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let last = subviews.last else { return }
        let others = subviews.dropLast()
        guard let fold, fold.axis == .vertical, let after = others.last else {
            last.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            for other in others {
                other.place(at: bounds.origin, proposal: .zero)
            }
            return
        }
        last.place(at: bounds.origin,
                   proposal: ProposedViewSize(width: max(0, fold.frame.minX), height: bounds.height))
        after.place(at: CGPoint(x: bounds.minX + fold.frame.maxX, y: bounds.minY),
                    proposal: ProposedViewSize(width: max(0, bounds.width - fold.frame.maxX),
                                               height: bounds.height))
    }
}

extension View {
    /// Lets a half's cards cast their shadows as far as the crease. A scroll
    /// view clips what it holds to its frame, and a half's frame ends at the
    /// strip around the fold, closer to its cards than their shadows reach:
    /// cut there, a shadow ended in a hard grey edge beside the crease.
    func castingShadowsToTheFold() -> some View {
        scrollClipDisabled()
    }

    /// Keeps the half after the fold clear of the navigation bar — see
    /// ``FoldSplitLayout``: on the Duo's rail, where the bar holds only the
    /// title over the half before the fold (the status bar and the buttons
    /// are in the rail), the half after runs from the top of the screen, its
    /// head level with the title as the boards draw it, and stays there
    /// whatever the title does. Without the rail it is left under the bar.
    func standingAfterTheFold() -> some View {
        modifier(AfterTheFold())
    }
}

private struct AfterTheFold: ViewModifier {
    @Environment(\.verticalBarEdge) private var barEdge

    /// From the top of the screen to the head of the half, the title's own
    /// margin.
    static let top: CGFloat = 16

    func body(content: Content) -> some View {
        if barEdge != nil {
            content
                .safeAreaPadding(.top, Self.top)
                .ignoresSafeArea(.container, edges: .top)
                // The bar's soft edge is as tall as the bar, and would lie
                // over the head of the half at rest.
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// The edge the system keeps its vertical bar on — the iPhone Duo's rail,
    /// which takes the tab bar and a screen's bar buttons — or nil where it
    /// keeps none. Read through here rather than as `toolbarVerticalEdge`,
    /// which iOS 26 does not have.
    var verticalBarEdge: HorizontalEdge? {
        if #available(iOS 27.1, *) { toolbarVerticalEdge } else { nil }
    }
}
