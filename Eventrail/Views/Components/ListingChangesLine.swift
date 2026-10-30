import SwiftUI

/// What an Updated row has new that it does not print already — a door or
/// end time, and who joined the bill — in one line under its date:
/// "開場 12:00 · +星守紗凪 +天野聡美". Only what it is now; what it was, and
/// who left, are on the sheet's card (``ListingChangesCard``). Nil where every
/// change is one the row shows in place (``EventRowContent``).
///
/// Everything an Updated row prints anew is in `ChangedListing`, a violet of
/// its own (Shawn): not the tag's and the billing caption's blue, nor the
/// ticket's amber, which the badge beside a My Events row already wears.
struct ListingChangesLine: View {
    /// Which clock the times are printed on — see ``TimeDisplay``.
    @AppStorage(TimeDisplay.storageKey) private var timeDisplay = TimeDisplay.venue
    let changes: ListingChanges

    var body: some View {
        if let line {
            line
                .scalingFont(size: 12, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(Color.changedListing)
                .lineLimit(1)
        }
    }

    private var line: Text? {
        let now = changes.shown(on: timeDisplay).now
        var phrases: [Text] = []
        if changes.changed(.time(.doorsOpen)) { phrases.append(Text("Doors \(now.doorsLine ?? "—")")) }
        if changes.changed(.time(.endsAt)) { phrases.append(Text("End \(now.endsLine ?? "—")")) }
        if !changes.added.isEmpty {
            phrases.append(Text(verbatim: changes.added.map { "+\($0)" }.joined(separator: " "))
                .accessibilityLabel(Text("\(Text("Performers Added")) \(Self.list(changes.added))")))
        }
        guard let first = phrases.first else { return nil }
        return phrases.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }

    /// "A, B, C", or "A、B、C" — run together in the reader's language.
    static func list(_ names: [String]) -> String {
        names.formatted(.list(type: .and, width: .narrow))
    }
}
