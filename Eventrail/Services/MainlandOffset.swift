import CoreLocation
import Foundation

/// The shift the map provider for mainland China draws its map with.
///
/// That provider publishes its tiles in GCJ-02, the coordinate system Chinese
/// law requires of maps there, which runs a few hundred metres off the WGS-84
/// every other source speaks. Its own search answers are already in GCJ-02 and
/// land on the right building. A coordinate from anywhere else — OpenStreetMap
/// — does not: MapKit draws it where it says, and the hall's pin sits across
/// the road from the hall.
///
/// So such a coordinate is shifted as it is *shown*, and only on a phone that
/// provider serves; what is written down stays WGS-84, which is what it is,
/// and the same answer drawn on the phone after a flight home lands where it
/// should.
///
/// The transform is the published one every open-source implementation
/// carries. Applied only where the provider shifts — see ``applies(at:)``.
nonisolated enum MainlandOffset {
    /// Where OpenStreetMap's answers are drawn shifted on that provider:
    /// Hong Kong, Macau and Taiwan, each seen off on a phone in Shanghai and
    /// seen right once shifted. The mainland's own halls are Maps' answers
    /// there, and already shifted.
    ///
    /// **Not Korea, and not Japan** — both checked on that phone, and both
    /// land right unshifted. Korea looked off once, and it was not the
    /// provider: the pin was on the middle of a university campus rather than
    /// the arena in it, and shifting it moved it further away.
    static func applies(at coordinate: CLLocationCoordinate2D) -> Bool {
        boxes.contains { box in
            box.latitudes.contains(coordinate.latitude) && box.longitudes.contains(coordinate.longitude)
        }
    }

    /// The same question for an answer that says which country it is in:
    /// the mainland, Hong Kong, Macau and Taiwan. OpenStreetMap files the
    /// first three under `cn`, and an address this app read as Hong Kong is
    /// `hk` here.
    static func applies(toCountry code: String) -> Bool {
        ["cn", "hk", "mo", "tw"].contains(code.lowercased())
    }

    private typealias Box = (latitudes: ClosedRange<Double>, longitudes: ClosedRange<Double>)

    private static let boxes: [Box] = [
        (22.14...22.58, 113.82...114.45),   // Hong Kong
        (22.10...22.22, 113.52...113.61),   // Macau
        (21.85...25.35, 119.30...122.10),   // Taiwan and Penghu
    ]

    /// `coordinate` as that provider's map places the same spot.
    static func shifted(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = coordinate.longitude - 105
        let y = coordinate.latitude - 35
        var dLat = latitudeShift(x, y)
        var dLon = longitudeShift(x, y)
        let radians = coordinate.latitude / 180 * .pi
        var magic = sin(radians)
        magic = 1 - eccentricity * magic * magic
        let root = magic.squareRoot()
        dLat = (dLat * 180) / ((axis * (1 - eccentricity)) / (magic * root) * .pi)
        dLon = (dLon * 180) / (axis / root * cos(radians) * .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat,
                                      longitude: coordinate.longitude + dLon)
    }

    private static let axis = 6378245.0
    private static let eccentricity = 0.00669342162296594323

    private static func latitudeShift(_ x: Double, _ y: Double) -> Double {
        var shift = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * abs(x).squareRoot()
        shift += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        shift += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        shift += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return shift
    }

    private static func longitudeShift(_ x: Double, _ y: Double) -> Double {
        var shift = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * abs(x).squareRoot()
        shift += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        shift += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        shift += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return shift
    }
}
