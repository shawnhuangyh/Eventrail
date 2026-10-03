import SwiftUI

/// The small uppercase label that stands over a group of cards, or over a list
/// of results.
///
/// Four screens wrote this out by hand — Settings over each of its four
/// headings, the Following filter over When and Where, Search over its result
/// count, and the account finder over Match — in four copies that happened to
/// agree down to the kerning. One of them drifting was only ever a matter of
/// which screen was edited next.
///
/// The horizontal inset belongs to the label rather than to the caller: it is
/// what lines the word up with the text inside the card beneath it, and that
/// relationship is the same wherever the label is used.
struct SectionLabel: View {
    let label: LocalizedStringKey

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.35)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
    }
}

/// The title a screen opens on, with the line under it saying what the screen
/// is for.
///
/// Shared by the welcome's steps and by the account sheet, which are the two
/// places in the app that introduce something rather than list it.
struct ScreenHeading: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .kerning(-0.84)
            Text(detail)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }
}

/// The line across the top of a card: what the card holds, how much of it there
/// is, and whatever way there is into the rest.
///
/// Five cards drew this themselves — the two on the Me tab, both halves of a
/// performer's listing, the same-bill card, and an event's billing — each with
/// its own idea of how a count sits beside a title. The padding is still the
/// caller's, because it belongs to the card rather than to the line.
struct CardHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    /// Shown small and dimmed after the title. Nil where there is nothing to
    /// count, or nothing worth counting yet — a heading that said "12" beside a
    /// listing still paging in would be counting the reading rather than the
    /// thing.
    var count: Int?
    /// A second line under the title, for a card that has to qualify what it is
    /// showing rather than count it.
    var caption: Text?
    /// A See All, usually. Empty where the card is the whole of it.
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                if let count {
                    Text(count.formatted())
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                trailing
            }
            if let caption {
                caption
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    /// A card whose whole contents are on screen, so there is nowhere to send
    /// the reader.
    init(title: LocalizedStringKey, count: Int? = nil, caption: Text? = nil) {
        self.init(title: title, count: count, caption: caption) { EmptyView() }
    }
}

/// The way into the whole of a list a card only samples.
///
/// The label rather than the link, because the two screens that show one reach
/// their destinations differently: the Me tab pushes a value onto its stack and
/// a performer's listing hands its already-read feed to the screen behind the
/// arrow. What the reader sees is the same either way, which is the part that
/// belongs here.
///
/// It sits on the words' baseline, so a header lines "See All" up with its
/// title. Centred on the words as it used to be, the label took its baseline
/// from the smaller chevron instead, and the words sat a point below the
/// title beside them.
struct SeeAllLabel: View {
    private static let font = UIFont.systemFont(ofSize: 13, weight: .semibold)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("See All")
                .font(Font(Self.font))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .centredOnLine(of: Self.font)
        }
        .foregroundStyle(Color.brandTint)
        .contentShape(.rect)
    }
}

extension View {
    /// Beside words set in `font`, in a row lined up by their baseline: an
    /// icon, a spinner or a badge, centred on the words' line as it would be
    /// if the two were centred on each other.
    ///
    /// Centred on each other outright, a row takes the topmost baseline of
    /// what is in it, and a smaller icon's sits higher than the words' — so
    /// the words of a label made that way sit a point low beside a title.
    /// This puts the icon's middle where the words' line has its middle,
    /// measured from their baseline, and leaves the baseline to the words.
    func centredOnLine(of font: UIFont) -> some View {
        alignmentGuide(.firstTextBaseline) {
            $0[VerticalAlignment.center] + (font.ascender + font.descender) / 2
        }
    }
}

/// The small print at the bottom of a screen: where the facts came from, and
/// what the app does and does not do with them.
///
/// Five screens carry one. The padding stays with each of them — a footnote
/// under a run of cards is inset to the cards, one under a full-width list to
/// the text — but nothing else about it should differ, and this is what stops
/// it.
///
/// It takes a `Text` rather than a key because one of them says two different
/// things depending on whether an import is still running.
struct Footnote: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

nonisolated extension String {
    /// This text with the web addresses written in it made tappable.
    ///
    /// Eventernote's members write an event's 概要 as plain text, and a ticket
    /// link in the middle of it is printed as the address itself. A `Text` does
    /// nothing with those, so they are detected and marked up here — which is
    /// the difference between a reader tapping through to the ticket agency and
    /// copying forty characters out by hand.
    ///
    /// Built by splicing the runs together rather than by attributing ranges in
    /// place: the two index spaces are not the same, and this one cannot put a
    /// link on the wrong words.
    var linkingURLs: AttributedString {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return AttributedString(self) }

        var attributed = AttributedString()
        var plain = startIndex
        for match in detector.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let url = match.url, let found = Range(match.range, in: self) else { continue }
            attributed += AttributedString(self[plain ..< found.lowerBound])
            var link = AttributedString(self[found])
            link.link = url
            attributed += link
            plain = found.upperBound
        }
        return attributed + AttributedString(self[plain...])
    }
}
