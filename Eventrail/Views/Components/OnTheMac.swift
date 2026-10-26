import SwiftUI

/// Whether the app is running on a Mac — Mac Catalyst, where the iPad's
/// screens are laid out for a window as wide as the Mac design draws them.
/// See CLAUDE.md › *The Mac app*.
nonisolated let isMac: Bool = {
    #if targetEnvironment(macCatalyst)
    true
    #else
    false
    #endif
}()

extension View {
    /// The screen's title, large over its content on a Mac, where the iPad
    /// draws it under the tab bar.
    ///
    /// A Mac's window has no large title: its bar is the window's toolbar,
    /// and the title sits small beside the window's buttons, where the Mac
    /// design keeps nothing. So there the title is taken out of the toolbar
    /// and drawn at the head of the content instead, its subtitle under it,
    /// as every board draws it — in a bar of its own, which what scrolls
    /// under it blurs beneath as a bar does. The navigation title stays set
    /// for the window's name. On an iPhone and an iPad this is nothing: the
    /// system's bar draws both.
    ///
    /// The bar is made inline too. Taking the title out leaves a large
    /// title's row standing empty above this one, the bar's buttons pushed
    /// down a row, and in some states the system drew its own large title in
    /// it — two titles, one over the other.
    ///
    /// And the bar is drawn as an iPad draws it (``PadNavigationBar``).
    ///
    /// `trailing` stands beside the title — what the design keeps on its
    /// line, as the Passport's year chips.
    func largeTitleOnMac<Trailing: View>(
        _ title: Text, subtitle: Text? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(MacLargeTitle(title: title, subtitle: subtitle, trailing: trailing()))
    }
}

private struct MacLargeTitle<Trailing: View>: ViewModifier {
    let title: Text
    let subtitle: Text?
    let trailing: Trailing

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .padNavigationBarOnMac()
            .safeAreaBar(edge: .top, spacing: 0) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        title
                            .font(.system(size: 30, weight: .bold))
                            .kerning(-0.4)
                            .lineLimit(1)
                        if let subtitle {
                            subtitle
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    trailing
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 10)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isHeader)
            }
        #else
        content
        #endif
    }
}

extension View {
    /// On a Mac, a band of its own under the bar over a list whose month
    /// headers stay pinned, in place of the list's own edge there. Nothing on
    /// an iPhone or an iPad.
    ///
    /// The system runs a list's edge on under a pinned header, so that what
    /// scrolls behind the header blurs as it does under the bar. On a Mac it
    /// stayed run on once the list had been scrolled back to its head: the
    /// edge, a frosted band with a hard line under it, ended a header's
    /// depth below the bar, across the top of Following's chips. So there the
    /// list's own edge is hidden, and a band is drawn from the top of the
    /// window to the foot of the bar, ending in a hard line as the edge does.
    /// Not faded out: a pinned header stands on a backdrop of the Mac's own
    /// from the foot of the bar down, and between a fade and that backdrop
    /// the rows showed through. Only once the list has been scrolled in under
    /// the bar, as the system's own edge shows only over what passes beneath
    /// it.
    func bandUnderBarOnMac() -> some View {
        modifier(MacBarBand())
    }
}

private struct MacBarBand: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    /// How deep the bar reaches over the list: the window's toolbar and the
    /// title under it.
    @State private var barDepth: CGFloat = 0
    @State private var isUnderBar = false

    func body(content: Content) -> some View {
        if isMac {
            content
                .scrollEdgeEffectHidden(true, for: .top)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 0.5
                } action: { _, isUnder in
                    isUnderBar = isUnder
                }
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { barDepth = $0 }
                .overlay(alignment: .top) { band }
        } else {
            content
        }
    }

    private var band: some View {
        Rectangle()
            .fill(.bar)
            .frame(height: barDepth)
            // Just under the band, on the line a pinned header's backdrop
            // draws at its head, so the two fall on one another.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1 / displayScale)
                    .offset(y: 1 / displayScale)
            }
            .opacity(isUnderBar ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isUnderBar)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The sizes a sheet opens at on a Mac — see ``SwiftUI/View/macSheetSize(_:)``.
nonisolated struct MacSheetSize: Sendable {
    var width: CGFloat
    var height: CGFloat

    /// An event's page: wide enough for its two columns (see
    /// `EventDetailView.leastWideWidth`).
    static let event = MacSheetSize(width: 880, height: 820)
    /// A form or a list read top to bottom — Ticket Details, Settings, the
    /// account, a performer's or a hall's page, a Passport drawer.
    static let form = MacSheetSize(width: 620, height: 740)

    /// The most a sheet can take of the window in front, a margin in from
    /// its edges: asked for at a fixed size, a sheet opened in a window
    /// narrower than that ran past both of its sides.
    ///
    /// The window in front is the key window — the one the reader clicked
    /// in, or pressed a key in, to open the sheet — and only failing that
    /// whichever scene is active.
    @MainActor static var room: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.keyWindow?.isKeyWindow == true })
                ?? scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        else { return CGSize(width: CGFloat.infinity, height: .infinity) }
        let window = scene.effectiveGeometry.coordinateSpace.bounds.size
        return CGSize(width: max(320, window.width - 48), height: max(320, window.height - 72))
    }
}

extension View {
    /// The size a sheet opens at on a Mac: about the size the same sheet
    /// stands at on an iPad, where a Mac would otherwise open every sheet at
    /// a small form's size, 470 by 400 points, too small for any of this
    /// app's. Nothing on an iPhone or an iPad, whose sheets size themselves.
    ///
    /// Goes on the sheet's content, inside `.sheet`. A window smaller than
    /// the size asked for keeps the sheet inside it (``MacSheetSize/room``),
    /// as it stands when the sheet opens.
    func macSheetSize(_ size: MacSheetSize) -> some View {
        #if targetEnvironment(macCatalyst)
        modifier(MacSheetFrame(size: size))
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct MacSheetFrame: ViewModifier {
    let size: MacSheetSize
    /// The window's room as the sheet opened, read once. Read on every
    /// redraw, it was measured against whichever window was in front by
    /// then: the focus moved to a larger window and the sheet grew past the
    /// one it stood in.
    @State private var room = MacSheetSize.room

    func body(content: Content) -> some View {
        content
            .frame(idealWidth: min(size.width, room.width),
                   idealHeight: min(size.height, room.height))
            .presentationSizing(.fitted)
    }
}
#endif

extension View {
    /// A linear progress bar as an iPhone and an iPad draw it: a 4-point
    /// capsule, the tint filling it from its leading end, and nothing of the
    /// tint at all at nought.
    ///
    /// A Mac draws `ProgressView` as its own progress bar, which shows a cap
    /// of the tint at nought, so there the bar is drawn here instead — the
    /// track in `secondarySystemFill`, as the system's bar was measured on an
    /// iPad. The system's own `.linear` everywhere else.
    func linearProgressAsOnPad() -> some View {
        #if targetEnvironment(macCatalyst)
        progressViewStyle(PadLinearProgressStyle())
        #else
        progressViewStyle(.linear)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct PadLinearProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let value = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        Capsule()
            .fill(Color(uiColor: .secondarySystemFill))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.tint)
                        .frame(width: proxy.size.width * value)
                }
            }
            .clipShape(.capsule)
            .frame(height: 4)
    }
}
#endif

// MARK: - Picking rows

// A Mac's `List(selection:)` picks rows the Mac's way: a click picks that row
// alone, and only ⌘-click adds another — so on My Events each click moved the
// one pick along instead of adding to it. There the list is handed no
// selection and no edit mode, and each row draws the mark itself and is
// picked or put back by a click, as a tap does on an iPhone and an iPad,
// where the list's own edit mode does all of it.

extension Binding {
    /// The selection a picking `List` is handed: none on a Mac, where each row
    /// picks itself (``SwiftUI/View/pickedByClickOnMac(_:isPicked:toggle:)``).
    func listSelection<Element: Hashable>() -> Binding<Set<Element>>? where Value == Set<Element> {
        isMac ? nil : self
    }
}

extension View {
    /// Edit mode for a `List` while it picks rows — never on a Mac, where each
    /// row picks itself.
    func pickingEditMode(_ isPicking: Bool) -> some View {
        environment(\.editMode, .constant(isPicking && !isMac ? .active : .inactive))
    }

    /// A row of a picking `List` on a Mac: ``SelectionMark`` in front of it,
    /// and a click anywhere on it picks it or puts it back. Nothing on an
    /// iPhone or an iPad, or while the list is not picking.
    @ViewBuilder
    func pickedByClickOnMac(_ isPicking: Bool, isPicked: Bool, toggle: @escaping () -> Void) -> some View {
        if isMac, isPicking {
            HStack(spacing: 12) {
                SelectionMark(isSelected: isPicked)
                self
            }
            .contentShape(.rect)
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
        } else {
            self
        }
    }
}

extension View {
    /// The menu a right-click on a row opens on a Mac: what the row's swipes
    /// do, since a mouse has no swipe. Nothing on an iPhone or an iPad, which
    /// swipe.
    ///
    /// Always on the row, whatever `items` holds at the moment — so the row
    /// is not rebuilt as they come and go — and a menu with nothing in it
    /// opens nothing.
    @ViewBuilder
    func contextMenuOnMac<Items: View>(@ViewBuilder _ items: () -> Items) -> some View {
        if isMac {
            contextMenu(menuItems: items)
        } else {
            self
        }
    }
}

extension Set {
    /// Picks `element`, or puts it back where it was picked.
    mutating func toggle(_ element: Element) {
        if remove(element) == nil { insert(element) }
    }
}

extension View {
    /// Has the navigation bar of the stack this stands in drawn as an iPad
    /// draws it (``PadNavigationBar``) — on the root of every stack's first
    /// screen: a tab's, through ``largeTitleOnMac(_:subtitle:trailing:)``,
    /// and a sheet's own. Nothing on an iPhone or an iPad.
    func padNavigationBarOnMac() -> some View {
        #if targetEnvironment(macCatalyst)
        background(PadNavigationBar())
        #else
        self
        #endif
    }

    /// Hides a Mac window's own name from its toolbar: every screen draws its
    /// title over its content (``largeTitleOnMac(_:subtitle:trailing:)``), and
    /// a window narrowed past its tab bar wrote "Eventrail" beside its
    /// buttons. The name stays the window's, for the Window menu.
    func hidesWindowTitleOnMac() -> some View {
        #if targetEnvironment(macCatalyst)
        background(WindowTitleHider())
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Has the navigation bar of the stack this stands in drawn as an iPad draws
/// it, rather than moved into the window's toolbar.
///
/// Left to choose, a Mac moved it into the toolbar in some launches and not
/// in others, and there the Mac draws a bar's buttons its own way: a bezel
/// to each, where an iPad gathers them on one piece of glass; a tinted
/// button filled with its tint — a black ✕, a green ✓, and every other one
/// blue from the root's tint — where an iPad tints only the symbol; and an
/// arrow beside a menu's symbol. Drawn as on an iPad, the buttons stand in a
/// row of their own under the title bar.
private struct PadNavigationBar: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Finder() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Finder: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            let stack = sequence(first: self as UIResponder, next: \.next)
                .lazy.compactMap { $0 as? UINavigationController }.first
            stack?.navigationBar.preferredBehavioralStyle = .pad
        }
    }
}

/// Reaches the window this stands in, once it is in one, and hides its title.
private struct WindowTitleHider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Hider() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Hider: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.windowScene?.titlebar?.titleVisibility = .hidden
        }
    }
}
#endif
