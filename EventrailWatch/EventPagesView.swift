import SwiftUI

enum EventPage: Hashable {
    case countdown, seat, times
}

/// One night in three pages turned with the Crown — the countdown, the seat,
/// the times — each washed in the colour of where the night stands.
struct EventPagesView: View {
    let event: WatchEvent
    let showsLocalTime: Bool
    @Binding var page: EventPage

    var body: some View {
        let changes = Night(event, showsLocalTime: showsLocalTime, at: .now).changes
        TimelineView(NightSchedule(changes: changes, step: 1)) { context in
            let night = Night(event, showsLocalTime: showsLocalTime, at: context.date)
            TabView(selection: $page) {
                CountdownPage(night: night)
                    .containerBackground(for: .tabView) { night.wash }
                    .tag(EventPage.countdown)
                SeatPage(night: night)
                    .navigationTitle(night.shortDate)
                    .containerBackground(for: .tabView) { night.wash }
                    .tag(EventPage.seat)
                TimesPage(night: night)
                    .navigationTitle(night.shortDate)
                    .containerBackground(for: .tabView) { night.wash }
                    .tag(EventPage.times)
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

/// A page laid out as the design lays it out: on the whole screen, under the
/// clock and the list button, measured on a 46 mm watch's 208 × 248 points
/// and scaled to the watch it is on.
private struct DesignCanvas<Content: View>: View {
    @ViewBuilder let content: (_ size: CGSize, _ scale: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(proxy.size, min(proxy.size.width / 208, proxy.size.height / 248))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }
}

/// The yellow the design picks out what matters next with: the seat, and the
/// next of the three times.
private let highlight = Color(red: 1, green: 0xD6 / 255, blue: 0x0A / 255)

// MARK: - 1 · Countdown

/// A gauge from the doors to the end, the start at its top, with the count to
/// whatever is next inside it and the two times it runs between beneath.
struct CountdownPage: View {
    let night: Night

    var body: some View {
        DesignCanvas { size, s in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let span = night.span
            ZStack(alignment: .top) {
                NightGauge(fraction: night.fraction, tint: night.tint, lineWidth: 20 * s)
                    .frame(width: 132 * s, height: 132 * s)
                    .position(center)
                VStack(spacing: 4 * s) {
                    night.gaugeLabel
                        .font(.system(size: 12.5 * s, weight: .semibold))
                        .foregroundStyle(night.tint)
                        // Higher up, where the ring closes in: "On now · ends
                        // in" ran into it at the block's own width.
                        .frame(maxWidth: 92 * s)
                    night.gaugeValue
                        .font(.system(size: 25 * s, weight: .bold))
                        .kerning(-0.5 * s)
                        .monospacedDigit()
                    Text(verbatim: night.dayLine)
                        .font(.system(size: 14 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(width: 112 * s)
                .position(center)
                HStack(alignment: .top) {
                    time(span.from.label, span.from.time, alignment: .leading, scale: s)
                    Spacer(minLength: 6 * s)
                    time(span.to.label, span.to.time, alignment: .trailing, scale: s)
                }
                .padding(.horizontal, 17 * s)
                .padding(.top, 180 * s)
            }
        }
    }

    private func time(_ label: LocalizedStringKey, _ time: String, alignment: HorizontalAlignment,
                      scale s: CGFloat) -> some View {
        VStack(alignment: alignment, spacing: 3 * s) {
            Text(label)
                .font(.system(size: 16.5 * s, weight: .bold))
            Text(verbatim: time)
                .font(.system(size: 15.5 * s, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.62))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Two thirds of a ring, open at the foot: the doors at its left end, the
/// start at its top — marked with a dot — and the end at its right.
struct NightGauge: View {
    let fraction: Double
    let tint: Color
    let lineWidth: CGFloat

    private static let sweep = 240.0 / 360

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.sweep)
                .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // A round cap with nothing behind it is still a dot, so an empty
            // fill is not drawn at all.
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: Self.sweep * fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        // From the lower left, over the top, to the lower right.
        .rotationEffect(.degrees(150))
        .overlay(alignment: .top) {
            Circle()
                .fill(.black.opacity(0.4))
                .frame(width: lineWidth / 4, height: lineWidth / 4)
                .offset(y: -lineWidth / 8)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 2 · Seat

/// The class the seat was sold as, what it cost and whether the ticket is in
/// hand, and the seat itself picked out to be read off at the door.
struct SeatPage: View {
    let night: Night

    var body: some View {
        DesignCanvas { _, s in
            VStack(alignment: .leading, spacing: 10 * s) {
                VStack(alignment: .leading, spacing: 3 * s) {
                    night.seatHeading
                        .font(.system(size: 30 * s, weight: .bold))
                        .kerning(-0.6 * s)
                    Text(verbatim: night.event.venue)
                        .font(.system(size: 14 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                VStack(alignment: .leading, spacing: 3 * s) {
                    night.costLine
                        .font(.system(size: 22 * s, weight: .semibold))
                        .monospacedDigit()
                    night.ticketLine.text
                        .font(.system(size: 17.5 * s, weight: .medium))
                        .foregroundStyle(night.ticketLine.color)
                }
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("Seat")
                        .font(.system(size: 14 * s, weight: .medium))
                    Text(verbatim: night.event.seat.isEmpty ? "--" : night.event.seat)
                        .font(.system(size: 18 * s, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9 * s)
                        .frame(minWidth: 38 * s, minHeight: 34 * s)
                        .background(highlight, in: .rect(cornerRadius: 9 * s))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, 53 * s)
            .padding(.leading, 16 * s)
            .padding(.trailing, 21 * s)
        }
    }
}

// MARK: - 3 · Times

/// What the night is doing, and its doors, start and end — what has gone by
/// greyed, what is next picked out.
struct TimesPage: View {
    let night: Night

    var body: some View {
        DesignCanvas { _, s in
            VStack(alignment: .leading, spacing: 8 * s) {
                VStack(alignment: .leading, spacing: 3 * s) {
                    night.timesHeading
                        .font(.system(size: 19 * s, weight: .semibold))
                        .kerning(-0.19 * s)
                        .monospacedDigit()
                        .foregroundStyle(night.timesHeadingIsLive ? night.tint : .white.opacity(0.55))
                    Text(verbatim: night.event.venue)
                        .font(.system(size: 14 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                VStack(spacing: 0) {
                    row("Doors", night.doors, index: 0, scale: s)
                    row("Start", night.starts, index: 1, scale: s)
                    row("End", night.ends, index: 2, scale: s)
                }
                night.timesFooter
                    .font(.system(size: 13 * s, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, 53 * s)
            .padding(.leading, 16 * s)
            .padding(.trailing, 21 * s)
        }
    }

    private func row(_ label: LocalizedStringKey, _ time: Date?, index: Int, scale s: CGFloat) -> some View {
        let isNext = night.nextTime == index
        return HStack(spacing: 6 * s) {
            Text(label)
                .font(.system(size: 15 * s, weight: .medium))
            Spacer(minLength: 0)
            Text(verbatim: night.time(time))
                .font(.system(size: 18 * s, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isNext ? Color.black : Color.white)
                .padding(.horizontal, 7 * s)
                .frame(height: 24 * s)
                .background(isNext ? highlight : .clear, in: .rect(cornerRadius: 7 * s))
                .padding(.trailing, -7 * s)
        }
        .frame(height: 30 * s)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 0.5)
        }
        .opacity(night.hasPassed(index) ? 0.45 : 1)
    }
}

#if DEBUG
#Preview("Pages") {
    @Previewable @State var page = EventPage.countdown
    NavigationStack {
        EventPagesView(event: WatchLibrary.preview.events[0], showsLocalTime: false, page: $page)
    }
}
#endif
