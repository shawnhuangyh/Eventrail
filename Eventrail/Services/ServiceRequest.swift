import Foundation

/// A GET of one of the free services the app asks besides Eventernote — the
/// register's address search (``JapanAddresses``), OpenStreetMap
/// (``VenueBuildings``) and Frankfurter (``ExchangeRates``) — read from the
/// JSON it answers with.
///
/// One request the way all three put one: asking for JSON, the query's `+`
/// written as `%2B` (``Foundation/URLComponents/setQuery(_:)``), anything but
/// a 200 a failure, and an answer of another shape a failure too — a changed
/// service should cost an answer, never a wrong one.
nonisolated enum ServiceRequest {
    /// The request did not come back as JSON of the shape asked for.
    struct Failure: Error {
        /// Whom it was put to, so a caller can tell one service turning it
        /// away from another — see ``VenueBuildings/turnedAway(_:)``.
        let host: String?
        /// The status where the service answered with something other than
        /// 200; nil where its answer could not be read.
        let status: Int?
    }

    /// `endpoint`'s answer, with `query` added to whatever query it carries.
    @concurrent static func json<Value: Decodable & Sendable>(
        _ type: Value.Type, from endpoint: URL, query: [URLQueryItem] = [],
        userAgent: String? = nil, timeout: TimeInterval? = nil, session: URLSession = .shared
    ) async throws -> Value {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            let held = components?.queryItems ?? []
            components?.setQuery(held + query)
        }
        guard let url = components?.url else { throw Failure(host: endpoint.host(), status: nil) }

        var request = URLRequest(url: url)
        if let timeout { request.timeoutInterval = timeout }
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw Failure(host: url.host(), status: status)
        }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw Failure(host: url.host(), status: nil)
        }
        return value
    }
}
