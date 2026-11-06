import SwiftUI

/// What had changed in an Updated date the reader has just read, on its sheet:
/// each change with what it was and what it is now, the bill's names whole.
/// The row it was read from printed only what is new, in
/// ``Color/changedListing``; this says what it replaced, and who left. See
/// ``EventStore/changesRead(in:)``.
struct ListingChangesCard: View {
    let changes: ListingChanges
    /// The clock the sheet prints its times on.
    let clock: TimeDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            CardHeader(title: "What Changed", caption: Text("Since you last looked"))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(changes.changes, id: \.self) { change in
                    row(change)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panel(cornerRadius: 28)
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private func row(_ change: ListingChanges.Change) -> some View {
        let (was, now) = changes.shown(on: clock)
        switch change {
        case .day:
            pair("Date", was: was.dayLine, now: now.dayLine)
        case .time(let stop):
            switch stop {
            case .doorsOpen: pair("Doors", was: was.doorsLine, now: now.doorsLine)
            case .startsAt: pair("Start", was: was.timeLine, now: now.timeLine)
            case .endsAt: pair("End", was: was.endsLine, now: now.endsLine)
            }
        case let .venue(old, new):
            pair("changes.venue", was: old, now: new)
        case let .performers(added, removed):
            if !added.isEmpty {
                labelled("Performers Added") {
                    Text(verbatim: ListingChangesLine.list(added))
                        .scalingFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.changedListing)
                }
            }
            if !removed.isEmpty {
                labelled("Performers Removed") {
                    Text(verbatim: ListingChangesLine.list(removed))
                        .strikethrough()
                        .scalingFont(size: 14)
                        .foregroundStyle(.secondary)
                }
            }
        case .billingOrder:
            labelled("Performers") {
                Text("Billing order changed")
                    .scalingFont(size: 14, weight: .semibold)
            }
        case let .title(old, new):
            pair("Title", was: old, now: new)
        }
    }

    /// What it was, struck through, and what it is now: on one line where
    /// both fit, the one over the other where they do not — a title never
    /// does. A dash for a time not printed then, or no longer.
    private func pair(_ label: LocalizedStringKey, was: String?, now: String?) -> some View {
        let old = Text(verbatim: was ?? "—")
            .strikethrough(was != nil)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Was \(was ?? "—")"))
        let new = Text(verbatim: now ?? "—")
            .fontWeight(.semibold)
            .foregroundStyle(Color.changedListing)
            .accessibilityLabel(Text("Now \(now ?? "—")"))
        return labelled(label) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    old
                    Image(systemName: "arrow.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    new
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    old
                    new
                }
            }
            .scalingFont(size: 14)
            .monospacedDigit()
        }
    }

    private func labelled<Value: View>(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .scalingFont(size: 11.5, weight: .semibold)
                .foregroundStyle(.secondary)
            value()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
