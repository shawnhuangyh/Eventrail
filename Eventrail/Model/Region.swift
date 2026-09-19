import Foundation
import SwiftUI

/// The parts of the country Eventernote files its venues under.
///
/// The site's own areas, read off the `area_id` facet its event search offers,
/// so narrowing by area here answers the way narrowing there would. Only the
/// grouping is borrowed: the app never asks the site to filter for it, because
/// a followed performer's listing takes no area of its own.
///
/// The whole of that facet, as the `<select name="area_id">` on `/events`
/// spells it, so nobody has to fetch the page again to check a case against it:
///
/// | `area_id` | The site's own name | Here |
/// | --- | --- | --- |
/// | 1 | 関東 | ``kanto`` |
/// | 2 | 関西 | ``kansai`` |
/// | 3 | 東海 | ``tokai`` |
/// | 4 | 北海道・東北・甲信・北陸 | ``north`` |
/// | 5 | 中国・四国・九州・沖縄 | ``west`` |
/// | 6 | 海外 | — |
///
/// Five cases for six areas, and ``prefectures`` covers all 47 of them exactly
/// once. Splitting one further — 北海道 out of ``north``, say — would be free
/// to implement, since the area is worked out here from the prefecture at the
/// head of the address rather than asked of the site; it is not done because
/// an area that is not one of these six would stop answering the way the site
/// answers.
///
/// The sixth, 海外, is deliberately absent. Abroad is a *negative*
/// fact about an address — that no Japanese prefecture is named in it — and
/// this app never turns a field it could not read into one it claims to have.
/// A hall abroad is unplaced, which is the same thing as a hall whose page has
/// not been read yet: neither is put anywhere it might not belong.
enum Region: String, CaseIterable, Identifiable, Hashable {
    /// In the site's own order, which is the order they are offered in.
    case kanto, kansai, tokai, north, west

    var id: Self { self }

    /// Short enough to stand in a chip, which is why the last two are named
    /// rather than spelled out the way the site spells them: ``detail`` carries
    /// the site's own chain of place names, and ``prefectures`` the whole of it.
    var label: LocalizedStringKey {
        switch self {
        case .kanto: "Kantō"
        case .kansai: "Kansai"
        case .tokai: "Tōkai"
        case .north: "Northern Japan"
        case .west: "Western Japan"
        }
    }

    /// What the area amounts to, for the reader who has not learnt the site's
    /// groupings by heart.
    var detail: LocalizedStringKey {
        switch self {
        case .kanto: "Tokyo and the six prefectures around it"
        case .kansai: "Osaka, Kyoto, Kobe and around"
        case .tokai: "Nagoya, Shizuoka, Gifu and Mie"
        case .north: "Hokkaidō, Tōhoku, Kōshin and Hokuriku"
        case .west: "Chūgoku, Shikoku, Kyūshū and Okinawa"
        }
    }

    /// The prefectures the site groups under this area, spelled as Eventernote
    /// spells them — which is also how they are spelled at the head of every
    /// address it publishes, and why ``containing(address:)`` can match on them
    /// without a table of its own.
    var prefectures: [String] {
        switch self {
        case .kanto:
            ["茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県"]
        case .kansai:
            ["滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県"]
        case .tokai:
            ["岐阜県", "静岡県", "愛知県", "三重県"]
        case .north:
            ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
             "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県"]
        case .west:
            ["鳥取県", "島根県", "岡山県", "広島県", "山口県",
             "徳島県", "香川県", "愛媛県", "高知県",
             "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"]
        }
    }

    /// The area an address Eventernote published falls in.
    ///
    /// A Japanese address opens with its prefecture and a venue page prints the
    /// whole of it, so the name at the front settles the area. An address that
    /// names none — a hall abroad, or a line that turned out to be something
    /// other than an address — belongs to no area rather than to a guessed one.
    static func containing(address: String) -> Region? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { region in
            region.prefectures.contains { address.hasPrefix($0) }
        }
    }
}
