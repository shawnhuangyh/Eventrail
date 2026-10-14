import CoreLocation
import Testing
@testable import Eventrail

/// Which coordinates are in Japan: the last guard on every answer about a hall
/// the site files there, and what puts a hall on Tokyo's clock unasked.
struct JapanAddressesTests {
    nonisolated static let japan: [(String, Double, Double)] = [
        ("Tokyo", 35.68, 139.77), ("Sapporo", 43.06, 141.35), ("Fukuoka", 33.59, 130.40),
        ("Naha", 26.21, 127.68), ("Yonaguni", 24.47, 123.00), ("Hateruma", 24.06, 123.78),
        ("Tsushima", 34.20, 129.29), ("Fukue, Goto", 32.70, 128.84), ("Oki", 36.20, 133.30),
        ("Sado", 38.02, 138.37), ("Okushiri", 42.15, 139.47), ("Rebun", 45.30, 141.04),
        ("Cape Soya", 45.52, 141.94), ("Nemuro", 43.33, 145.58), ("Chichijima", 27.09, 142.19),
        ("Minamitorishima", 24.28, 153.98), ("Okinotorishima", 20.42, 136.07),
    ]

    nonisolated static let abroad: [(String, Double, Double)] = [
        ("Seoul", 37.57, 126.98), ("Busan", 35.16, 129.16), ("Ulsan", 35.54, 129.44),
        ("Pohang", 36.08, 129.57), ("Jeju", 33.50, 126.53), ("Geoje", 34.70, 128.62),
        ("Ulleungdo", 37.48, 130.90), ("Shenyang", 41.80, 123.43), ("Harbin", 45.80, 126.53),
        ("Dalian", 38.91, 121.61), ("Weihai", 37.51, 122.12), ("Shanghai", 31.23, 121.47),
        ("Zhoushan", 30.00, 122.30), ("Taipei", 25.03, 121.57), ("Keelung", 25.13, 121.74),
        ("Vladivostok", 43.12, 131.89), ("Yuzhno-Sakhalinsk", 46.96, 142.73),
        ("Cape Crillon", 45.90, 141.92), ("Batanes", 20.45, 121.97), ("Farallon de Pajaros", 20.55, 144.90),
    ]

    @Test(arguments: japan)
    func aPlaceInJapanIsInJapan(_ place: (String, Double, Double)) {
        #expect(JapanAddresses.isInJapan(CLLocationCoordinate2D(latitude: place.1, longitude: place.2)), "\(place.0)")
    }

    /// Korea, the mainland's northeast and Vladivostok all sat inside the
    /// box Japan once was.
    @Test(arguments: abroad)
    func aPlaceAcrossTheSeaIsNot(_ place: (String, Double, Double)) {
        #expect(!JapanAddresses.isInJapan(CLLocationCoordinate2D(latitude: place.1, longitude: place.2)), "\(place.0)")
    }
}
