import SwiftUI

/// One row of a settings card: an icon in the gutter, a name, a status line
/// only when there is one, and whatever the row puts on the right — a switch,
/// a spinner, a chevron.
///
/// Settings draws every row this way, and the welcome draws the same switches
/// the same way, because they *are* the same switches — a reader who turned
/// iCloud on in one should recognise the row in the other. One view rather
/// than a shape per row also means a toggle and a button that share a card
/// line up down to the pixel: the icons sit in a gutter of one width, which is
/// what keeps the titles on one left edge.
///
/// The padding is left to the caller (``SwiftUI/View/settingRowPadding()``),
/// because it belongs to whatever is tappable — the whole `Toggle` for a
/// switch, the label alone inside a `Button`.
struct SettingRowLabel<Trailing: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    /// Said only when there is something to say *now* — a failure, a refresh
    /// under way. What a row does in general is not repeated here.
    var status: Text?
    var needsAttention = false
    var tint: Color = .secondary
    var titleTint: Color = .primary
    @ViewBuilder var trailing: Trailing

    init(_ symbol: String, _ title: LocalizedStringKey, status: Text? = nil,
         needsAttention: Bool = false, tint: Color = .secondary, titleTint: Color = .primary,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.status = status
        self.needsAttention = needsAttention
        self.tint = tint
        self.titleTint = titleTint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(titleTint)
                if let status {
                    status
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(needsAttention ? Color.favorite : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: 28)
    }
}

/// The hairline between two rows of one settings card, inset past the icon
/// gutter so it starts under the text rather than cutting the icons off.
///
/// A sibling in the stack rather than something laid over the row beneath it:
/// an overlay renders at the mercy of whatever the row is made of, and went
/// missing over the one row in Settings built from a `ShareLink`.
struct SettingRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 48)
    }
}

/// The current answer on the right of a row — a language, an appearance, a
/// version number — and the sign after it saying what a tap does.
///
/// Its colours are fixed label colours rather than the hierarchical
/// `.secondary`/`.tertiary`: those are worked out from whatever foreground the
/// row's container sets, and a `Menu` sets a different one from a `Link`, so
/// the same style drew two different greys on two neighbouring rows. The
/// answer is secondary-label grey, dark enough to read as an answer rather
/// than as a disabled control.
struct SettingRowValue: View {
    let text: Text
    /// An SF Symbol after the answer — an arrow for a link out, up-and-down
    /// chevrons for a menu, a chevron for a push. Nil for none.
    var accessory: String?

    init(_ text: Text, accessory: String? = nil) {
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 6) {
            text
                .font(.system(size: 14))
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            if let accessory {
                SettingRowAccessory(symbol: accessory)
            }
        }
    }
}

/// The sign at the end of a row saying what a tap does, in the one fixed grey
/// every row shares — see ``SettingRowValue`` for why it is not `.tertiary`.
struct SettingRowAccessory: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(uiColor: .tertiaryLabel))
    }
}

/// The chevron at the end of a row that opens something.
struct SettingRowChevron: View {
    var body: some View {
        SettingRowAccessory(symbol: "chevron.right")
    }
}

extension View {
    /// The inset every settings row shares, on whatever the reader taps.
    func settingRowPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
    }
}
