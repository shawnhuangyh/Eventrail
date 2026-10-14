import Foundation
import Testing
@testable import Eventrail

struct VenueViewTests {
    /// A hall's phone is typed by the site's members, in either width and
    /// with whatever around it; the link dials the number alone.
    @Test(arguments: [
        ("03-3216-0555", "tel:0332160555"),
        ("０３－３２１６－０５５５", "tel:0332160555"),
        ("＋81 3-3216-0555", "tel:+81332160555"),
        ("TEL:03(3216)0555 (代表)", "tel:0332160555"),
    ])
    func aPhoneIsDialledAsItsNumber(_ phone: String, _ dialled: String) {
        #expect(VenueView.dialURL(for: phone)?.absoluteString == dialled)
    }

    /// Words where a number would be are printed, not dialled.
    @Test(arguments: ["非公開", "", "なし"])
    func noNumberIsNoLink(_ phone: String) {
        #expect(VenueView.dialURL(for: phone) == nil)
    }
}
