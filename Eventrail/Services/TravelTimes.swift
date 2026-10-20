import MapKit
import Observation
import os

/// How long Apple Maps says it takes to get from one hall to another, for two
/// events the reader keeps on one day (``SameDay``).
///
/// Asked from an event's sheet and nowhere else — one journey per pair of
/// events, asked because somebody is looking at it, as a hall is placed (see
/// ``VenuePlaces``): Maps throttles an app that asks it by the dozen, and My
/// Events holds hundreds. What a sheet found is kept in a file of this
/// device's own, which My Events' rows read and ask nothing of.
///
/// By public transport, the way a fan gets about in Japan; on foot between
/// two halls closer than ``walkingDistance``, which Maps may answer no
/// transport for; by car where it has no transport either — the answer says
/// which, since that changes what it means.
@Observable
final class TravelTimes {
    static let shared = TravelTimes()

    /// One journey, as Maps answered it.
    nonisolated struct Travel: Codable, Sendable, Hashable {
        let seconds: TimeInterval
        let mode: Mode
        /// When it sets off — the earlier event's end — which is what a
        /// timetable is read for, and what lets the answer go once it is past.
        let departs: Date
        let asked: Date
    }

    nonisolated enum Mode: String, Codable, Sendable {
        case transit, walking, driving
    }

    /// Asked again by the next sheet after a month: a timetable changes.
    nonisolated static let patience: TimeInterval = 30 * 24 * 60 * 60
    /// Two halls this close are walked between first.
    nonisolated static let walkingDistance: CLLocationDistance = 1500

    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "travel")

    /// Every journey found, by ``key(for:)``.
    private var known: [String: Travel]
    @ObservationIgnored private let file: KeptFile<String, Travel>

    private init() {
        let file = KeptFile<String, Travel>(named: "travelTimes.json", in: .caches, formerKey: "travelTimes")
        self.file = file
        var known = file.read()
        // A journey a day behind is for an event that is over.
        let gone = Date.now.addingTimeInterval(-24 * 60 * 60)
        let before = known.count
        known = known.filter { $0.value.departs > gone }
        if known.count != before { file.write(&known) }
        self.known = known
    }

    /// The pair's two events and halls and when it sets off, so a journey is
    /// asked again once either event's hall or times change.
    nonisolated static func key(for pair: SameDay) -> String {
        let departs = pair.departure.map { Int($0.timeIntervalSince1970 / 60) } ?? 0
        return "\(pair.earlier.id)>\(pair.later.id)@\(departs)\n\(pair.earlier.venue)\n\(pair.later.venue)"
    }

    /// What has already been found for the pair, however long ago. Asks
    /// nothing.
    func travel(for pair: SameDay) -> Travel? {
        known[Self.key(for: pair)]
    }

    /// Whether the pair's journey still needs asking about.
    func needsAsking(_ pair: SameDay) -> Bool {
        guard let held = travel(for: pair) else { return true }
        return held.asked.addingTimeInterval(Self.patience) < .now
    }

    /// Asks Maps how long the journey takes from `origin` to `destination`,
    /// setting off as the earlier event ends, and keeps the answer. Nil where
    /// it has none by any way it was asked, or refuses — written down as
    /// nothing, so the next sheet asks again.
    func ask(_ pair: SameDay, from origin: VenuePlaces.Placing, to destination: VenuePlaces.Placing) async -> Travel? {
        guard let departs = pair.departure else { return nil }
        let key = Self.key(for: pair)
        let distance = origin.item.location.distance(from: destination.item.location)
        let modes: [Mode] = distance < Self.walkingDistance ? [.walking, .transit] : [.transit, .driving]
        for mode in modes {
            do {
                let seconds = try await Self.eta(from: origin.item, to: destination.item, by: mode, departing: departs)
                let travel = Travel(seconds: seconds, mode: mode, departs: departs, asked: .now)
                Self.log.info("travel \(key, privacy: .public) → \(Int(seconds / 60))m by \(mode.rawValue, privacy: .public)")
                known[key] = travel
                file.write(&known)
                return travel
            } catch let error as MKError where error.code == .loadingThrottled {
                // The next way would be refused too.
                Self.log.error("travel \(key, privacy: .public) → throttled")
                return nil
            } catch {
                Self.log.error("travel \(key, privacy: .public) by \(mode.rawValue, privacy: .public) → \(error, privacy: .public)")
            }
        }
        return nil
    }


    private static func eta(
        from origin: MKMapItem, to destination: MKMapItem, by mode: Mode, departing: Date
    ) async throws -> TimeInterval {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = destination
        request.transportType = switch mode {
        case .transit: .transit
        case .walking: .walking
        case .driving: .automobile
        }
        // A timetable for a moment gone by is no timetable: from now instead.
        if departing > .now { request.departureDate = departing }
        return try await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}
