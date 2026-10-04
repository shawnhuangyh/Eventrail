import SwiftUI

/// The currencies a menu offers, laid out the one way every currency menu in
/// the app lays them out — the ticket sheet's, the Passport's and Settings'.
///
/// Each a row of its code over its name, checked as a menu checks a choice.
/// The reader's default and the currency of the hall's country, where the
/// menu has either, stand above a divider and say which they are; the rest of
/// ``Currencies/offered`` follows in its own order, and a currency the
/// selection holds that the list does not is added to it rather than lost.
struct CurrencyChoices: View {
    @Binding var selection: String
    /// Set apart at the top and marked Default. Nil where the menu is the
    /// one that chooses it.
    var defaultCurrency: String?
    /// Set apart at the top and marked Venue — see ``Currencies/atVenue(of:)``.
    var venue: String?

    var body: some View {
        let first = [defaultCurrency, venue].compactMap(\.self).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let rest = Currencies.options(including: [selection]).filter { !first.contains($0) }
        if !first.isEmpty {
            Section {
                ForEach(first, id: \.self, content: option)
            }
        }
        Section {
            ForEach(rest, id: \.self, content: option)
        }
    }

    private func option(_ code: String) -> some View {
        Toggle(isOn: menuChoice($selection, code)) {
            Text(verbatim: code)
            subtitle(of: code)
        }
    }

    /// "New Taiwan Dollar", with "Default" or "Venue" after it where the
    /// currency is either.
    private func subtitle(of code: String) -> Text {
        let name = Text(verbatim: Currencies.name(of: code))
        switch (code == defaultCurrency, code == venue) {
        case (true, true): return Text("\(name) · Default · Venue")
        case (true, false): return Text("\(name) · Default")
        case (false, true): return Text("\(name) · Venue")
        case (false, false): return name
        }
    }
}
