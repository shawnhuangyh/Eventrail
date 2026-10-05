import Foundation
import Observation
import OSLog

/// What one currency is worth in another, read from Frankfurter
/// (`api.frankfurter.dev`) — the one place the app asks about money.
///
/// Frankfurter publishes the reference rates of a hundred-odd central banks,
/// free and with no key, the European Central Bank's among them. Its v2 API
/// rather than the v1 most examples name: v1 carries only the ECB's thirty
/// currencies, which leaves out the Taiwan dollar and the pataca — two of the
/// places Eventernote's members actually file halls in.
///
/// **Asked only when a screen has something to convert**: the Passport, when
/// a ticket is in a currency other than the one it is adding up in, and the
/// ticket sheet, when a cost is in a currency other than the default. One GET
/// for every currency at once, kept in a file, and not asked again for
/// ``window``: the rates move once a working day, and a figure "about CN¥462"
/// does not need them any fresher. A failed read keeps the rates already held.
///
/// Converted at today's rates rather than at each event's, deliberately: a
/// spending total is read as "what these tickets come to in my money", and a
/// rate per event would be a request per date for a precision nobody reading
/// a rounded figure can see. The Passport says which day's rates it used.
@Observable
final class ExchangeRates {
    static let shared = ExchangeRates()

    /// The rates last read on this device, or nil before any read has landed.
    private(set) var rates: CurrencyRates?
    /// Whether a read is under way, so a screen waiting on one can say so
    /// rather than call its tickets unconvertible.
    private(set) var isReading = false

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private let file: URL?

    /// Twelve hours: rates are published once a working day, so a copy is
    /// never more than a day behind and is asked for about twice a day at
    /// most — and only on a day the reader opens something that converts.
    static let window: TimeInterval = 12 * 60 * 60

    nonisolated static let endpoint = URL(string: "https://api.frankfurter.dev/v2/rates?base=EUR")!

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "rates")

    /// In Caches: the rates are re-readable, and a device short of room is
    /// welcome to take them back.
    init(file: URL? = ExchangeRates.defaultFile) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file) {
            rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        }
    }

    private static let defaultFile: URL = {
        let directory = URL.cachesDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "exchangeRates.json")
    }()

    /// Reads the rates again where the copy held is older than ``window``, or
    /// there is none. Joins a read already running rather than starting a
    /// second.
    func refreshIfStale() async {
        if let rates, Date.now.timeIntervalSince(rates.readAt) < Self.window { return }
        if let running { return await running.value }
        let task = Task { await read() }
        running = task
        await task.value
        running = nil
    }

    private func read() async {
        isReading = true
        defer { isReading = false }
        do {
            let rates = try await Self.fetch()
            self.rates = rates
            if let file {
                let data = try JSONEncoder().encode(rates)
                Task.detached(priority: .utility) { try? data.write(to: file, options: .atomic) }
            }
        } catch {
            Self.log.error("Exchange rates could not be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One row of Frankfurter's answer: `{"date":"2026-10-03","base":"EUR",
    /// "quote":"JPY","rate":178.3}`. A currency whose bank has not published
    /// today carries the last day it did.
    private nonisolated struct Row: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Double
    }

    enum Failure: Error {
        case http(Int)
        case unreadable
    }

    @concurrent nonisolated private static func fetch() async throws -> CurrencyRates {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw Failure.http(status)
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        let days = DateFormatter()
        days.locale = Locale(identifier: "en_US_POSIX")
        days.timeZone = TimeZone(identifier: "UTC")
        days.dateFormat = "yyyy-MM-dd"
        var rates: [String: Double] = [:]
        var published = Date.distantPast
        for row in rows where row.base == "EUR" && row.rate > 0 {
            rates[row.quote] = row.rate
            if let day = days.date(from: row.date) { published = max(published, day) }
        }
        guard !rates.isEmpty else { throw Failure.unreadable }
        return CurrencyRates(base: "EUR", rates: rates, published: published, readAt: .now)
    }
}
