import Testing
@testable import Eventrail

struct RegionTests {
    @Test func coversAll47PrefecturesExactlyOnce() {
        let all = Region.allCases.flatMap(\.prefectures)
        #expect(all.count == 47)
        #expect(Set(all).count == 47)
    }

    @Test(arguments: [
        ("東京都千代田区北の丸公園2-3", Region.kanto),
        ("神奈川県横浜市西区みなとみらい6-2-14", .kanto),
        ("大阪府大阪市中央区大阪城3-1", .kansai),
        ("愛知県名古屋市東区大幸南1-1-1", .tokai),
        ("北海道札幌市豊平区羊ケ丘1", .north),
        ("  福岡県福岡市中央区地行浜2-2-2", .west),
        ("沖縄県沖縄市八重島3-1-1", .west),
    ])
    func placesAnAddressByItsPrefecture(address: String, region: Region) {
        #expect(Region.containing(address: address) == region)
    }

    @Test(arguments: [
        "台北市信義區忠孝東路四段515號",
        "8,028席",
        "",
        // A prefecture that is not at the head of the line is not the hall's.
        "Hall near 東京都",
    ])
    func leavesAnythingElseUnplaced(address: String) {
        #expect(Region.containing(address: address) == nil)
    }
}
