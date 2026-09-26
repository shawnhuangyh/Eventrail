import CoreLocation
import Foundation
import Testing
@testable import Eventrail

struct VenueCountriesTests {
    @Test(arguments: [
        "上海市浦东新区世博大道1200号",
        "广东省深圳市南山区",
        "北京市朝阳区",
        "内蒙古自治区呼和浩特市",
        "1200 Shibo Avenue, Pudong, Shanghai",
    ])
    func theMainlandIsRecognised(_ address: String) {
        #expect(VenueCountries.isMainlandChina(address))
    }

    @Test(arguments: [
        // Taipei's streets are named for mainland cities.
        "台北市中山區南京東路二段",
        "臺北市中正區重慶南路一段",
        "香港北角英皇道",
        "澳門氹仔",
        "서울특별시 성북구 안암로 145",
        "Seoul",
    ])
    func elsewhereIsNotTheMainland(_ address: String) {
        #expect(!VenueCountries.isMainlandChina(address))
    }

    @Test func aCountryIsReadOnlyWhereItCannotBeMistaken() {
        #expect(VenueCountries.country(of: "서울특별시 성북구 안암로 145") == "kr")
        #expect(VenueCountries.country(of: "香港九龍尖沙咀") == "hk")
        #expect(VenueCountries.country(of: "臺北市信義區") == "tw")
        #expect(VenueCountries.country(of: "澳門路氹") == "mo")
        #expect(VenueCountries.country(of: "上海市浦东新区") == nil)
        #expect(VenueCountries.country(of: "Singapore") == nil)
    }

    @Test func aKoreanAddressWrittenInKanjiIsKorea() {
        #expect(VenueCountries.country(of: "畿道高陽市一山西区キンテックス路217-60") == "kr")
        #expect(VenueCountries.country(of: "釜山広域市海雲台区") == "kr")
        // Tokyo's 大田区 is not Daejeon.
        #expect(VenueCountries.country(of: "東京都大田区平和島") == nil)
    }

    @Test(arguments: [
        ("済州特別自治道済州市", "kr"), ("大邱広域市北区", "kr"), ("仁川広域市延寿区", "kr"),
        ("Busan Exhibition and Convention Center", "kr"),
        ("新北市林口區", "tw"), ("高雄市前鎮區", "tw"), ("桃園市中壢區", "tw"),
        ("灣仔博覽道1號", "hk"), ("AsiaWorld-Expo, Chek Lap Kok", "hk"),
        ("路氹金光大道", "mo"),
    ])
    func everyPlaceIsReadInTheFormsMembersWriteIt(_ address: String, _ country: String) {
        #expect(VenueCountries.country(of: address) == country)
    }

    @Test(arguments: ["東京都台東区浅草", "台東区浅草1丁目", "大田区平和島", "光が丘", "桃園台"])
    func aNameJapanSharesIsNotReadAsAbroad(_ address: String) {
        #expect(VenueCountries.country(of: address) == nil)
    }

    @Test(arguments: ["四川省成都市", "湖北省武汉市", "陕西省西安市", "哈尔滨市道里区", "Xi'an, Shaanxi"])
    func moreOfTheMainlandIsRecognised(_ address: String) {
        #expect(VenueCountries.isMainlandChina(address))
    }

    @Test func aTitleNamesTheCityOfAHallWithNoAddress() {
        #expect(VenueCountries.country(of: "林鼓子2026香港粉絲見面會（日場）") == "hk")
        #expect(VenueCountries.country(of: "Roselia ASIA TOUR「Neuweltfahrt」ソウル公演") == "kr")
        #expect(VenueCountries.country(of: "ワンマンライブ 東京公演") == nil)
    }

    @Test func hongKongIsSearchedByItsBoxNotByCountryCode() {
        // OpenStreetMap files Hong Kong under cn, so countrycodes=hk finds nothing.
        let hongKong = VenueCountries.searchScope(for: "hk").map(\.name)
        #expect(hongKong.contains("viewbox") && hongKong.contains("bounded"))
        #expect(!hongKong.contains("countrycodes"))
        #expect(VenueCountries.searchScope(for: "KR") == [URLQueryItem(name: "countrycodes", value: "kr")])
    }

    @Test func aCountryOnOneClockIsDated() {
        #expect(VenueCountries.timeZone(forCountry: "KR") == TimeZone(identifier: "Asia/Seoul"))
        #expect(VenueCountries.timeZone(forCountry: "hk") == TimeZone(identifier: "Asia/Hong_Kong"))
        // Several clocks: left to the one its members wrote.
        #expect(VenueCountries.timeZone(forCountry: "us") == nil)
    }
}

struct MainlandOffsetTests {
    @Test func aHallInHongKongIsShiftedAFewHundredMetres() {
        let hotel = CLLocationCoordinate2D(latitude: 22.2897423, longitude: 114.1926542)
        #expect(MainlandOffset.applies(at: hotel))
        let shifted = MainlandOffset.shifted(hotel)
        let metres = CLLocation(latitude: hotel.latitude, longitude: hotel.longitude)
            .distance(from: CLLocation(latitude: shifted.latitude, longitude: shifted.longitude))
        #expect((200...700).contains(metres))
    }

    @Test func tiananmenLandsWhereThePublishedTransformPutsIt() {
        let shifted = MainlandOffset.shifted(CLLocationCoordinate2D(latitude: 39.90872, longitude: 116.39748))
        #expect(abs(shifted.latitude - 39.91012) < 0.0003)
        #expect(abs(shifted.longitude - 116.40372) < 0.0003)
    }

    @Test func anAnswerIsShiftedByTheCountryItCameBackIn() {
        for code in ["cn", "HK", "mo", "tw"] { #expect(MainlandOffset.applies(toCountry: code)) }
        for code in ["kr", "jp", "us"] { #expect(!MainlandOffset.applies(toCountry: code)) }
    }

    @Test func taipeiIsShiftedToo() {
        #expect(MainlandOffset.applies(at: CLLocationCoordinate2D(latitude: 25.0516, longitude: 121.5515)))
    }

    @Test func koreaAndJapanAreLeftAlone() {
        // Seoul, Busan, Tokyo, Osaka, Fukuoka.
        for (latitude, longitude) in [(37.59, 127.03), (35.18, 129.08), (35.68, 139.77), (34.69, 135.50), (33.59, 130.40)] {
            #expect(!MainlandOffset.applies(at: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        }
    }
}

struct VenueNameTests {
    @Test func aHallInsideSomewhereIsTriedWithoutItsFirstWordFirst() {
        #expect(VenueBuildings.shortenings(of: "高麗大学校 化汀 体育館") == ["高麗大学校 化汀 体育館", "化汀 体育館", "高麗大学校"])
    }

    @Test func aRoomAfterADashIsCutOff() {
        #expect(VenueBuildings.shortenings(of: "歷山酒店-宴會廳") == ["歷山酒店-宴會廳", "歷山酒店"])
    }

    @Test func aLongVowelIsNotABreak() {
        #expect(VenueBuildings.shortenings(of: "ぴあアリーナMM") == ["ぴあアリーナMM"])
    }
}
