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
struct SeeAllLabel: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("See All")
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.brandTint)
        .contentShape(.rect)
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
