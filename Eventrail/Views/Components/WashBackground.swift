import SwiftUI

/// The soft three-corner colour wash the glass panels sit on.
///
/// Each blob mirrors one radial gradient from the design: the frame is twice the
/// gradient's radii scaled by the stop where it reaches transparent.
struct WashBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.washBase
                blob(.washOne, at: UnitPoint(x: 0.12, y: 0), radii: (0.58, 0.38), fade: 0.70, in: size)
                blob(.washTwo, at: UnitPoint(x: 0.92, y: 0.06), radii: (0.52, 0.34), fade: 0.70, in: size)
                blob(.washThree, at: UnitPoint(x: 0.48, y: 1.02), radii: (0.64, 0.40), fade: 0.72, in: size)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(
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

extension View {
    /// Places content over the wash, letting it run under the bars.
    func washBackground() -> some View {
        background(WashBackground())
    }

    /// The design's panel treatment: Liquid Glass in a soft-cornered rectangle.
    func glassPanel(cornerRadius: CGFloat = 26, interactive: Bool = false) -> some View {
        glassBackground(in: .rect(cornerRadius: cornerRadius, style: .continuous),
                        interactive: interactive)
    }

    func glassCapsule(interactive: Bool = false) -> some View {
        glassBackground(in: .capsule, interactive: interactive)
    }

    func glassCircle(interactive: Bool = false) -> some View {
        glassBackground(in: .circle, interactive: interactive)
    }

    /// The one place Liquid Glass is applied.
    ///
    /// visionOS renders app content on its own glass substrate and does not
    /// offer `glassEffect`, so panels fall back to the system material there.
    @ViewBuilder
    func glassBackground(in shape: some Shape, interactive: Bool = false) -> some View {
        #if os(visionOS)
        background(.regularMaterial, in: shape)
        #else
        glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        #endif
    }
}

#Preview {
    WashBackground()
}
