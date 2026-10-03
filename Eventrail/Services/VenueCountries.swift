import Foundation

/// Which country a hall abroad is in, read off the address Eventernote
/// published, and which clock a country keeps.
///
/// Needed only on a phone whose Maps is served by the provider for mainland
/// China — see ``VenuePlaces/search(_:mayAskOpenStreetMap:)``. That provider
/// answers well about the mainland and badly about everywhere else: it has no
/// Japanese venues, and asked about a hall in Seoul it offers whichever of its
/// own places shares a number with the address. So there the question "is this
/// hall on the mainland" decides who is asked at all, and it has to be answered
/// before anybody is — from the published text.
///
/// Heuristic, and deliberately one-sided. Members write these addresses by
/// hand, in whatever script the hall uses, so this is a reading and not a
/// parse; where it cannot tell, it says "not the mainland", which sends the hall
/// to OpenStreetMap — slower, but never the wrong country.
nonisolated enum VenueCountries {
    /// Whether `address` names somewhere on the mainland of China.
    ///
    /// A province or municipality *with its suffix* — 上海市, 广东省 — rather
    /// than the bare name: Taipei's streets are named for mainland cities, and
    /// 南京東路 or 重慶南路 is an address in Taiwan. And anything naming Hong
    /// Kong, Macau or Taiwan is none of the mainland whatever else it says.
    static func isMainlandChina(_ address: String) -> Bool {
        let text = address.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? address
        guard country(of: text) == nil else { return false }
        if text.contains("自治区") || text.contains("自治區") { return true }
        let named = mainlandProvinces.contains { text.contains($0 + "省") }
            || mainlandCities.contains { text.contains($0 + "市") }
        if named { return true }
        let lowered = text.lowercased()
        return mainlandRomanized.contains { lowered.contains($0) }
    }

    /// The ISO country code of a hall `address` plainly places outside Japan
    /// and off the mainland, or nil where it does not say.
    ///
    /// Only the places Eventernote's members actually write about, and only by
    /// what cannot be mistaken: Hangul is Korea, and Hong Kong, Macau and
    /// Taiwan are named by their own cities.
    static func country(of address: String) -> String? {
        if address.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
            return "kr"
        }
        let lowered = address.lowercased()
        for (code, names) in markers where names.contains(where: { lowered.contains($0) }) {
            return code
        }
        return nil
    }

    /// The clock a country keeps, where it keeps only one.
    ///
    /// OpenStreetMap answers with a country and no zone, and Maps — which does
    /// carry one — is not being asked. A country spanning several zones is left
    /// out rather than guessed at: the hall then stays on the clock its members
    /// wrote, and the sheet shows no offset beside its clock switch, which is true.
    static func timeZone(forCountry code: String) -> TimeZone? {
        singleZones[code.lowercased()].flatMap(TimeZone.init(identifier:))
    }

    /// Written in every form members use: the local script, kanji or hanzi as
    /// Japanese writes them, katakana, and English. Whole province-level
    /// divisions, and a city only where its name is Korea's or the region's
    /// alone. Matched in this order, first match wins.
    private static let markers: [(String, [String])] = [
        ("hk", ["香港", "九龍", "九龙", "新界", "hong kong", "kowloon", "ホンコン",
                "灣仔", "湾仔", "wan chai", "銅鑼灣", "铜锣湾", "causeway bay", "尖沙咀", "tsim sha tsui",
                "旺角", "mong kok", "紅磡", "红磡", "hung hom", "荃灣", "荃湾", "tsuen wan",
                "觀塘", "观塘", "kwun tong", "將軍澳", "将军澳", "tseung kwan o", "葵涌", "kwai chung",
                "屯門", "屯门", "tuen mun", "元朗", "yuen long", "沙田", "sha tin",
                "大嶼山", "大屿山", "lantau", "赤鱲角", "chek lap kok", "asiaworld"]),
        ("mo", ["澳門", "澳门", "macau", "macao", "マカオ", "氹仔", "taipa",
                "路氹", "cotai", "路環", "路环", "coloane"]),
        ("tw", ["台灣", "臺灣", "台湾", "taiwan", "タイワン",
                "台北", "臺北", "taipei", "タイペイ", "新北", "new taipei",
                "桃園市", "taoyuan", "台中", "臺中", "taichung", "タイチュン",
                "台南", "臺南", "tainan", "高雄", "kaohsiung", "カオシュン",
                "基隆", "keelung", "新竹市", "新竹縣", "hsinchu", "嘉義", "chiayi", "苗栗", "miaoli",
                "彰化", "changhua", "南投", "nantou", "雲林", "yunlin", "屏東", "pingtung",
                "宜蘭", "yilan", "花蓮", "hualien", "台東縣", "臺東縣", "taitung",
                "澎湖", "penghu", "金門縣", "kinmen", "連江縣", "matsu"]),
        // As Japanese titles write Korea — a title rather than an address is
        // where ``VenuePlaces`` reads these for a hall with no address — and
        // as members write a Korean address in kanji and katakana rather than
        // Hangul: 畿道高陽市一山西区キンテックス路 is KINTEX, and has none.
        // Not a bare name Japan shares — 大田 or 光州 without the 広域市 only
        // Korea's cities carry, and in Taiwan's list 台東 (Tokyo's 台東区),
        // 桃園 and 新竹 without their 市 or 縣.
        ("kr", ["韓国", "韓國", "大韓民国", "korea",
                "ソウル", "seoul", "釜山", "プサン", "busan", "pusan",
                "大邱", "daegu", "仁川", "インチョン", "incheon",
                "光州広域市", "光州廣域市", "gwangju", "大田広域市", "大田廣域市", "daejeon",
                "蔚山", "ulsan", "世宗", "sejong",
                "京畿", "畿道", "キョンギ", "gyeonggi", "江原道", "江原特別", "gangwon",
                "忠清", "chungcheong", "全羅", "全北特別", "jeolla", "慶尚", "gyeongsang",
                "済州", "濟州", "チェジュ", "jeju",
                "高陽市", "goyang", "イルサン", "ilsan", "水原市", "suwon",
                "広域市", "廣域市", "特別市", "特別自治"]),
    ]

    /// How OpenStreetMap is told to search only inside `code`.
    ///
    /// By country code wherever that works, and by a box where it does not:
    /// OpenStreetMap files Hong Kong and Macau under `cn`, so a search limited
    /// to `hk` comes back empty — and one limited to `cn` would reach the
    /// whole mainland, which is the namesake this is meant to keep out.
    static func searchScope(for code: String) -> [URLQueryItem] {
        if let box = boxes[code.lowercased()] {
            return [URLQueryItem(name: "viewbox", value: box), URLQueryItem(name: "bounded", value: "1")]
        }
        return [URLQueryItem(name: "countrycodes", value: code.lowercased())]
    }

    /// West, north, east, south — the order Nominatim's `viewbox` takes.
    private static let boxes = [
        "hk": "113.82,22.58,114.45,22.14",
        "mo": "113.52,22.22,113.61,22.10",
    ]

    /// Every province, in simplified, traditional and Japanese forms.
    private static let mainlandProvinces = [
        "河北", "山西", "辽宁", "遼寧", "吉林", "黑龙江", "黑龍江", "黒竜江",
        "江苏", "江蘇", "浙江", "安徽", "福建", "江西", "山东", "山東",
        "河南", "湖北", "湖南", "广东", "廣東", "広東", "海南", "四川",
        "贵州", "貴州", "云南", "雲南", "陕西", "陝西", "甘肃", "甘肅", "甘粛", "青海",
    ]

    /// The four municipalities, every provincial capital, and the other cities
    /// a tour stops in — each read with its 市, since Taipei's streets carry
    /// these names too.
    private static let mainlandCities = [
        "北京", "天津", "上海", "重庆", "重慶",
        "石家庄", "石家莊", "太原", "沈阳", "瀋陽", "长春", "長春", "哈尔滨", "哈爾濱",
        "南京", "杭州", "合肥", "福州", "南昌", "济南", "濟南", "済南", "郑州", "鄭州",
        "武汉", "武漢", "长沙", "長沙", "广州", "廣州", "広州", "海口", "成都",
        "贵阳", "貴陽", "昆明", "西安", "兰州", "蘭州", "西宁", "西寧",
        "呼和浩特", "南宁", "南寧", "拉萨", "拉薩", "银川", "銀川", "乌鲁木齐", "烏魯木齊",
        "深圳", "苏州", "蘇州", "厦门", "廈門", "厦門", "青岛", "青島", "大连", "大連",
        "宁波", "寧波", "无锡", "無錫", "佛山", "东莞", "東莞", "珠海", "温州", "溫州",
        "常州", "徐州", "烟台", "煙台", "洛阳", "洛陽", "南通", "泉州", "绍兴", "紹興",
    ]

    private static let mainlandRomanized = [
        "beijing", "shanghai", "guangzhou", "shenzhen", "chengdu", "hangzhou",
        "chongqing", "tianjin", "wuhan", "nanjing", "xi'an", "changsha", "suzhou",
        "xiamen", "qingdao", "dalian", "shenyang", "harbin", "zhengzhou", "kunming",
        "p.r. china", "people's republic of china", "中华人民共和国", "中華人民共和国", "中華人民共和國",
    ]

    private static let singleZones = [
        "kr": "Asia/Seoul", "hk": "Asia/Hong_Kong", "mo": "Asia/Macau",
        "tw": "Asia/Taipei", "cn": "Asia/Shanghai", "sg": "Asia/Singapore",
        "th": "Asia/Bangkok", "ph": "Asia/Manila", "my": "Asia/Kuala_Lumpur",
        "vn": "Asia/Ho_Chi_Minh", "gb": "Europe/London", "fr": "Europe/Paris",
        "de": "Europe/Berlin", "it": "Europe/Rome", "es": "Europe/Madrid",
        "nl": "Europe/Amsterdam", "be": "Europe/Brussels", "at": "Europe/Vienna",
        "ch": "Europe/Zurich", "se": "Europe/Stockholm", "fi": "Europe/Helsinki",
        "pl": "Europe/Warsaw", "ie": "Europe/Dublin",
    ]
}
