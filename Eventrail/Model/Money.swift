import SwiftUI

/// What a ticket cost: an amount, and the currency it was paid in.
///
/// The amount is a `Decimal` because it is what the reader typed — 9,900 yen,
/// 49.99 dollars — and is kept exactly; only a figure *worked out* from it,
/// a conversion or an average, is ever rounded, and only as it is printed.
nonisolated struct Money: Hashable, Sendable {
    var amount: Decimal
    /// The ISO 4217 code: JPY, TWD, USD.
    var currency: String

    /// As every price in the app is written — see ``Currencies/format(_:in:)``.
    var formatted: String { Currencies.format(amount, in: currency) }
}

/// The currencies a ticket can be written in, and how each one is printed.
///
/// Named by code and nothing else. The symbol and the name come from the
/// reader's own locale as each is drawn, so CNY is CN¥ to a reader in English
/// and ¥ to one in Simplified Chinese, whose yen is then JP¥ — which is what
/// every other app on their phone calls them too.
nonisolated enum Currencies {
    /// Settings › Locale › Default Currency: what the Event Passport adds its
    /// tickets up in, and what a cost typed on a ticket with none starts in.
    ///
    /// Per device, as Time Zone is: it is how this reader reads money on this
    /// phone, not something about the library.
    static let storageKey = "defaultCurrency"

    /// Yen: what Eventernote's own events are priced in, what every cost
    /// written before a ticket had a currency was in, and so the default until
    /// the reader picks another.
    static let yen = "JPY"

    /// Offered on the ticket sheet, the Passport and in Settings, in this
    /// order: Japan, then the places Eventernote's members file halls in —
    /// the mainland, Hong Kong, Macau, Taiwan, Korea and the region around
    /// them — then the currencies a reader abroad is likeliest to be paid in.
    ///
    /// A choice, not a whitelist: a record holding any other code reads back
    /// in it, and every list below carries that code too.
    static let offered = ["JPY", "CNY", "HKD", "MOP", "TWD", "KRW", "SGD", "THB",
                          "USD", "EUR", "GBP", "AUD", "CAD"]

    /// ``offered``, with any of `extra` it does not already hold after it.
    static func options(including extra: some Sequence<String>) -> [String] {
        var options = offered
        for code in extra where !code.isEmpty && !options.contains(code) { options.append(code) }
        return options
    }

    /// The symbol the reader's locale prints the currency with — ¥, CN¥, NT$.
    static func symbol(of code: String) -> String {
        formatter(for: code).currencySymbol ?? code
    }

    /// The currency's name in the reader's language — "New Taiwan Dollar".
    static func name(of code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    /// How many digits may follow the decimal point: none for yen or won,
    /// two for most others.
    static func fractionDigits(of code: String) -> Int {
        formatter(for: code).maximumFractionDigits
    }

    /// An amount as the reader wrote it: with its cents where it has any, and
    /// without a row of zeroes where it has none — ¥9,900, NT$3,800, $49.99.
    static func format(_ amount: Decimal, in code: String) -> String {
        amount.formatted(style(for: amount, in: code))
    }

    /// A figure worked out from amounts — a conversion, an average, a total
    /// across currencies — to the nearest whole unit: "about CN¥462" is what
    /// it means, and CN¥461.87 would claim a precision no rate has.
    static func format(whole amount: Double, in code: String) -> String {
        Decimal(amount.rounded()).formatted(style(for: 0, in: code))
    }

    /// The same, cut into the symbol and the figures, so a headline can draw
    /// the symbol smaller and dimmed — on whichever side the locale puts it:
    /// ("CN¥", "6,000", "") in English, ("", "6.000", "€") in German.
    static func parts(whole amount: Double, in code: String)
        -> (before: String, figures: String, after: String) {
        let formatted = Decimal(amount.rounded()).formatted(style(for: 0, in: code).attributed)
        var before = "", figures = "", after = ""
        for run in formatted.runs {
            let text = String(formatted[run.range].characters)
            if run.numberSymbol == .currency {
                if figures.isEmpty { before += text } else { after += text }
            } else {
                figures += text
            }
        }
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (trimmed(before), trimmed(figures), trimmed(after))
    }

    private static func style(for amount: Decimal, in code: String) -> Decimal.FormatStyle.Currency {
        var rounded = Decimal()
        var value = amount
        NSDecimalRound(&rounded, &value, 0, .plain)
        let hasFraction = rounded != amount && fractionDigits(of: code) > 0
        return .currency(code: code).precision(.fractionLength(hasFraction ? 2 : 0))
    }

    private static func formatter(for code: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter
    }

    /// The currency a country pays in — the region's own, as Foundation has it.
    static func ofCountry(_ code: String) -> String? {
        Locale(components: .init(languageCode: nil, script: nil,
                                 languageRegion: .init(code.uppercased()))).currency?.identifier
    }

    /// The currency of the country the event's hall stands in, where its
    /// published address says — the one the ticket sheet marks "Venue".
    ///
    /// A hint, never the answer: a date in Taipei is as often paid for in yen
    /// through a fan club in Tokyo as in Taiwan dollars at the door, so the
    /// sheet starts a cost in the reader's default and only labels this one.
    /// Read off the address the way the rest of the app reads it — a Japanese
    /// prefecture at its head, or ``VenueCountries``' reading of one abroad.
    static func atVenue(of event: Event) -> String? {
        guard let address = (event.venueAddress ?? event.venueDetail)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty
        else { return nil }
        if Region.containing(address: address) != nil { return yen }
        if let country = VenueCountries.country(of: address) { return ofCountry(country) }
        if VenueCountries.isMainlandChina(address) { return "CNY" }
        return nil
    }
}

/// Rates between currencies, as one table read from one pivot.
///
/// Frankfurter's rates are against the euro; any two other currencies are
/// read through it, which is how a central bank's own cross rates are made.
/// The pivot is asked for every currency at once rather than for the pairs a
/// screen needs, so one read answers any pair a ticket can be written in.
nonisolated struct CurrencyRates: Codable, Hashable, Sendable {
    /// The currency every rate here is quoted against.
    var base: String
    /// How much of each currency one unit of ``base`` buys.
    var rates: [String: Double]
    /// The latest day the rates were published for — what the Passport says
    /// it converted at.
    var published: Date
    /// When this device read them, which is what stale is measured from.
    var readAt: Date

    /// What one unit of `from` is worth in `to`, or nil where the table
    /// carries neither currency.
    func rate(from: String, to: String) -> Double? {
        if from == to { return 1 }
        let units = from == base ? 1 : rates[from]
        let other = to == base ? 1 : rates[to]
        guard let units, let other, units > 0 else { return nil }
        return other / units
    }
}

nonisolated extension Money {
    /// This amount in `currency`, or nil where the rates cannot say.
    ///
    /// Exact where nothing needs converting, so a library kept in one
    /// currency adds up to the yen it was written in, rates or none.
    func converted(to currency: String, at rates: CurrencyRates?) -> Double? {
        if currency == self.currency { return amount.doubleValue }
        guard let rate = rates?.rate(from: self.currency, to: currency) else { return nil }
        return amount.doubleValue * rate
    }
}

nonisolated extension Decimal {
    /// As a `Double`, for arithmetic that is rounded before it is printed.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Writes an amount of money into a text field, and reads one back out.
///
/// Without its symbol, which the field draws beside it, and with as many
/// decimals as its currency has — none for yen. `TextField(value:format:)`
/// insists the value and the style agree on a type, and no built-in style
/// takes an optional — an emptied field has to read back as nil, "not written
/// down", rather than as 0, which is a free ticket.
///
/// Parsing reads the digits out of whatever is in the field and the locale's
/// decimal point among them, and ignores the rest, so the separators the
/// style itself wrote survive an edit, and a full-width １２３４ from a
/// Japanese keyboard is the same number as 1234.
nonisolated struct MoneyAmount: ParseableFormatStyle {
    /// How many decimals the currency has — see ``Currencies/fractionDigits(of:)``.
    var fractionDigits: Int
    var locale: Locale = .autoupdatingCurrent

    var parseStrategy: Strategy {
        Strategy(fractionDigits: fractionDigits, decimalSeparator: locale.decimalSeparator ?? ".")
    }

    func format(_ value: Decimal?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0 ... fractionDigits)).locale(locale)) } ?? ""
    }

    nonisolated struct Strategy: ParseStrategy {
        var fractionDigits: Int
        var decimalSeparator: String

        /// Nine digits before the point is 999,999,999. Past that the reader
        /// is leaning on a key rather than recording a ticket.
        func parse(_ value: String) -> Decimal? {
            let text = value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value
            var whole = "", fraction = "", pastPoint = false
            for character in text {
                if let digit = character.wholeNumberValue, (0 ... 9).contains(digit) {
                    if pastPoint {
                        if fraction.count < fractionDigits { fraction.append(String(digit)) }
                    } else if whole.count < 9 {
                        whole.append(String(digit))
                    }
                } else if String(character) == decimalSeparator, fractionDigits > 0, !pastPoint {
                    pastPoint = true
                }
            }
            guard !whole.isEmpty || !fraction.isEmpty else { return nil }
            let number = (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
            return Decimal(string: number, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}

nonisolated extension FormatStyle where Self == MoneyAmount {
    static func money(in currency: String) -> MoneyAmount {
        MoneyAmount(fractionDigits: Currencies.fractionDigits(of: currency))
    }
}
