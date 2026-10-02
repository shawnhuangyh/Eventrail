#if DEBUG
import SwiftUI
import WidgetKit

/// Debug only: drawn on the Lock Screen in place of the card for an activity
/// the app's Test Live Activity bench started with diagnostics on, so what
/// each renderer — the phone, the Mac's menu bar, the watch — makes of the
/// pieces ``Gate`` is built from can be read off one picture.
///
/// Each swatch tests one thing, against the answer the phone should give:
///
/// - A, B, C — the bar as drawn: not yet begun (track only), over (full),
///   and running for two minutes from the start (should be moving).
/// - D — red masked by clear: should be invisible (is a mask honoured?).
/// - E — red masked by white at 30 %: faint red (is a mask's alpha used?).
/// - F, G — red masked by the stretched bar not yet begun (near invisible:
///   the track's alpha) and over (solid red).
/// - H — red masked by the cut bar not yet begun: invisible.
/// - I — red masked by the whole ``Gate``, opening in an hour: invisible.
/// - J — black put through `luminanceToAlpha` over red: red where the filter
///   is drawn, black where it is not.
/// - K, k — 70 % white through `contrast(4)` (white where the filter is
///   drawn), and the same grey untouched beside it.
/// - L, M — red behind a ``Gate`` a minute after the start, opening and
///   closing: L should appear and M disappear as the timer beside them runs
///   out.
struct GateDiagnostics: View {
    static let prefix = "test-diag-"

    /// When the activity was asked for.
    let since: Date

    var body: some View {
        let future = since.addingTimeInterval(3600)
        let past = since.addingTimeInterval(-3600)
        let soon = since.addingTimeInterval(60)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                swatch("A", width: 70) { plainBar(future...future.addingTimeInterval(60)) }
                swatch("B", width: 70) { plainBar(past...past.addingTimeInterval(60)) }
                swatch("C", width: 70) { plainBar(since...since.addingTimeInterval(120)) }
            }
            HStack(spacing: 10) {
                swatch("D") { Color.red.mask { Color.clear } }
                swatch("E") { Color.red.mask { Color.white.opacity(0.3) } }
                swatch("F") { Color.red.mask { Gate(at: future, opening: true).bar(at: future) } }
                swatch("G") { Color.red.mask { Gate(at: past, opening: true).bar(at: past) } }
                swatch("H") { Color.red.mask { Gate(at: future, opening: true).exact(at: future) } }
                swatch("I") { Color.red.mask { Gate(at: future, opening: true) } }
            }
            HStack(spacing: 10) {
                swatch("J") { ZStack { Color.red; Color.black.luminanceToAlpha() } }
                swatch("K") { Color(white: 0.7).contrast(4) }
                swatch("k") { Color(white: 0.7) }
                swatch("L") { Color.red.mask { Gate(at: soon, opening: true) } }
                swatch("M") { Color.red.mask { Gate(at: soon, opening: false) } }
                Text(timerInterval: since...soon, countsDown: true)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 50)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plainBar(_ interval: ClosedRange<Date>) -> some View {
        ProgressView(timerInterval: interval, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(.white)
    }

    private func swatch(_ name: String, width: CGFloat = 22,
                        @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 2) {
            content()
                .frame(width: width, height: 22)
                .clipped()
            Text(verbatim: name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
#endif
