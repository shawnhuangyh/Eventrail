import SwiftUI

/// The soft three-corner colour wash the glass panels sit on.
///
/// Each blob mirrors one radial gradient from the design: the frame is twice the
/// gradient's radii scaled by the stop where it reaches transparent.
struct WashBackground: View {
    /// The screen this wash is a piece of, where a screen parted at the fold
    /// draws one in each half — see ``EnvironmentValues/washCanvas``.
    @Environment(\.washCanvas) private var canvas

    var body: some View {
        GeometryReader { proxy in
            if let canvas {
                // One piece of a wider picture: the blobs stand where they
                // stand on that picture, and each piece shows its own part of
                // it and no more — the blobs that reach past it are drawn by
                // the piece beside it, and drawn twice over they darken.
                let own = proxy.frame(in: .global)
                let picture = canvas.offsetBy(dx: -own.minX, dy: -own.minY)
                ZStack(alignment: .topLeading) {
                    Color.washBase
                    Self.blobs(in: picture.size)
                        .frame(width: picture.width, height: picture.height)
                        .offset(x: picture.minX, y: picture.minY)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
            } else {
                ZStack {
                    Color.washBase
                    Self.blobs(in: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
        // Something to look at, never to touch. A piece of a wider picture
        // keeps its blobs' whole frames for hit-testing however it is
        // clipped, so the list beside an open iPhone Duo's fold — laid out
        // over the event beside it — took every touch meant for the event.
        .allowsHitTesting(false)
    }

    private static func blobs(in size: CGSize) -> some View {
        ZStack {
            blob(.washOne, at: UnitPoint(x: 0.12, y: 0), radii: (0.58, 0.38), fade: 0.70, in: size)
            blob(.washTwo, at: UnitPoint(x: 0.92, y: 0.06), radii: (0.52, 0.34), fade: 0.70, in: size)
            blob(.washThree, at: UnitPoint(x: 0.48, y: 1.02), radii: (0.64, 0.40), fade: 0.72, in: size)
        }
    }

    /// One radial gradient of the design's, in a frame of `size`: centred at
    /// `center`, its radii fractions of the frame, transparent at `fade`. The
    /// ticket stub's canvas is drawn from the same — see ``TicketCanvas``.
    static func blob(
        _ color: Color, at center: UnitPoint,
        radii: (x: CGFloat, y: CGFloat), fade: CGFloat, in size: CGSize
    ) -> some View {
        EllipticalGradient(
            stops: [.init(color: color, location: 0), .init(color: color.opacity(0), location: 1)],
            center: .center
        )
        .frame(width: size.width * radii.x * 2 * fade,
               height: size.height * radii.y * 2 * fade)
        .position(x: size.width * center.x, y: size.height * center.y)
    }
}

extension EnvironmentValues {
    /// The whole screen, in global coordinates, where a screen is drawn as
    /// halves either side of the iPhone Duo's fold and each half draws its own
    /// wash — set by ``View/eventPane(_:)``. Nil everywhere else,
    /// where a wash is drawn to its own frame.
    ///
    /// A sheet presented from inside a parted screen inherits it, and a wash
    /// drawn in that sheet would be the middle of the screen's picture rather
    /// than its own. None does today — every list's sheets hang outside its
    /// ``View/eventPane(_:)``, and the page's own draw no wash — but one that
    /// does should set it back to nil.
    @Entry var washCanvas: CGRect?
}

extension View {
    /// Places content over the wash, letting it run under the bars.
    func washBackground() -> some View {
        background(WashBackground())
    }

    /// The design's panel, in a soft-cornered rectangle: a veil of white over
    /// the wash and a hairline round it — what its Liquid Glass showed in
    /// front of the wash, drawn without the glass.
    ///
    /// Every card, row and pill on a page is drawn this way; glass is kept
    /// for the controls that float over a page (``glassBackground(in:interactive:tint:)``).
    /// Glass is drawn afresh in every frame it moves in, and a row is never
    /// still while its list scrolls. Measured on My Events in the iPad
    /// simulator with seven hundred events, rows in glass — or with a glass
    /// pill on them — dropped about one frame in six and kept the main thread
    /// a fifth busier; the same rows in flat colour dropped almost none, and
    /// the hairline cost too little to tell apart. A blur or a shadow under
    /// the panel cost nearly as much as the glass, so there is neither.
    ///
    /// `tint` washes the panel in a colour of its own — what the timeline
    /// card wears while its event is under way.
    func panel(cornerRadius: CGFloat = 26, tint: Color? = nil) -> some View {
        background(PanelBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                   tint: tint))
    }

    /// A pill drawn as ``panel(cornerRadius:tint:)`` draws a card.
    func capsulePanel() -> some View {
        background(PanelBackground(shape: Capsule(), tint: nil))
    }

    /// A round button drawn as ``panel(cornerRadius:tint:)`` draws a card.
    func circlePanel() -> some View {
        background(PanelBackground(shape: Circle(), tint: nil))
    }

    /// A pill of Liquid Glass, for a control that floats over a page — the
    /// capsule at the foot of a list, the Passport's year chips.
    func glassCapsule(interactive: Bool = false) -> some View {
        glassBackground(in: .capsule, interactive: interactive)
    }

    /// A round button of Liquid Glass, for a close or back button over a page.
    func glassCircle(interactive: Bool = false) -> some View {
        glassBackground(in: .circle, interactive: interactive)
    }

    /// The one place Liquid Glass is applied.
    ///
    /// visionOS renders app content on its own glass substrate and does not
    /// offer `glassEffect`, so panels fall back to the system material there.
    ///
    /// `tint` colours the glass itself rather than laying a colour over it —
    /// what a refresh notice that failed wears, so the glass says so before a
    /// word of it is read.
    @ViewBuilder
    func glassBackground(in shape: some Shape, interactive: Bool = false,
                         tint: Color? = nil) -> some View {
        #if os(visionOS)
        background(.regularMaterial, in: shape)
        #else
        glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        #endif
    }
}

/// What ``View/panel(cornerRadius:tint:)`` and its pill and circle draw
/// behind their content.
private struct PanelBackground<S: InsettableShape>: View {
    let shape: S
    let tint: Color?

    var body: some View {
        shape.fill(Color.panelFill)
            .overlay {
                if let tint { shape.fill(tint) }
            }
            .overlay(shape.strokeBorder(Color.panelRim, lineWidth: 1))
    }
}

#Preview {
    WashBackground()
}
