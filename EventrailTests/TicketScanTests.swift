import CoreGraphics
import Foundation
import Testing
@testable import Eventrail

struct TicketScanTests {
    /// A line as Vision gives it: the text, then its box in fractions of the
    /// picture from the lower-left corner.
    private func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.3, h: CGFloat = 0.019) -> TicketScan.Line {
        TicketScan.Line(text: text, frame: CGRect(x: x, y: y, width: w, height: h))
    }

    /// An e+ スマチケ screenshot as Vision read it, line for line and box
    /// for box — the seat, the holder and the ticket number made up.
    private func eplusTicket(day: String, seatClass: String, seat: [String], price: String) -> [TicketScan.Line] {
        [
            line("15:00", x: 0.121, y: 0.954, w: 0.121, h: 0.019),
            line("入場画面に進む", x: 0.583, y: 0.893, w: 0.342, h: 0.025),
            line("Lこのチケットは分配できません。", x: 0.029, y: 0.831, w: 0.555, h: 0.023),
            line("2026年", x: 0.046, y: 0.775, w: 0.142, h: 0.019),
            line(day, x: 0.054, y: 0.729, w: 0.225, h: 0.031),
            line("MyGO！！！！！", x: 0.050, y: 0.700, w: 0.238, h: 0.020),
            line("ぴあアリーナMM", x: 0.050, y: 0.685, w: 0.233, h: 0.013),
            line("16:30開場", x: 0.300, y: 0.754, w: 0.196, h: 0.017),
            line("18:00開演", x: 0.304, y: 0.729, w: 0.192, h: 0.020),
            line("- 9th LIVE「つなぎ目の向こうに」", x: 0.316, y: 0.699, w: 0.601, h: 0.025),
            line("山田 太郎様", x: 0.054, y: 0.620, w: 0.221, h: 0.025),
            line("1枚目", x: 0.858, y: 0.624, w: 0.083, h: 0.017),
            line("未使用", x: 0.104, y: 0.497, w: 0.104, h: 0.017),
            line(seatClass, x: 0.308, y: 0.568, w: 0.446, h: 0.023),
            line(seat[0], x: 0.308, y: 0.541, w: 0.375, h: 0.019),
            line(seat[1], x: 0.308, y: 0.516, w: 0.142, h: 0.019),
            line(price, x: 0.308, y: 0.487, w: 0.259, h: 0.022),
            line("MyGO！！！！！ 9th LIVE「つなぎ目の向こうに」", x: 0.050, y: 0.453, w: 0.550, h: 0.013),
            line("主催：株式会社ブシロードミュージック", x: 0.046, y: 0.432, w: 0.492, h: 0.017),
            line("お問合せ：ブシロードミュージック https://bushiroad-", x: 0.054, y: 0.415, w: 0.679, h: 0.015),
            line("music.com/contact/", x: 0.050, y: 0.397, w: 0.275, h: 0.012),
            line("※見切れ席は、一部ステージ・演出が見えにくい場合がございま", x: 0.050, y: 0.374, w: 0.804, h: 0.017),
            line("す。", x: 0.050, y: 0.355, w: 0.046, h: 0.017),
            line("※2F後方立ち見エリアは、チケット記載の番号の立ち位置にて", x: 0.046, y: 0.336, w: 0.804, h: 0.019),
            line("ご観覧いただきます。", x: 0.050, y: 0.317, w: 0.271, h: 0.019),
            line("（通称：UOグルグル等）は禁止します。", x: 0.050, y: 0.280, w: 0.463, h: 0.017),
            line("https://bushiroad-music.com/news/321/", x: 0.050, y: 0.246, w: 0.546, h: 0.013),
            line("イープラス 050-3185-6483", x: 0.050, y: 0.173, w: 0.375, h: 0.013),
            line("チケット裏面情報＞", x: 0.046, y: 0.150, w: 0.275, h: 0.017),
            line("チケット番号：0000000000000", x: 0.050, y: 0.113, w: 0.479, h: 0.017),
        ]
    }

    // MARK: - e+

    /// The 未使用 stamp beside the seat stands between it and the price by
    /// height; read across the card, it was read into the seat.
    @Test func anEplusTicketGivesItsSeatClassPriceAndDay() {
        let scan = TicketScan(reading: eplusTicket(
            day: "7/18（土）", seatClass: "A席（特製グッズ付き）",
            seat: ["アリーナ B5ブロック", "12列34番"], price: "¥16,500（税込）"))
        #expect(scan.seat == "アリーナ B5ブロック 12列 34番")
        #expect(scan.seatClass == "A席")
        #expect(scan.price == Money(amount: 16500, currency: "JPY"))
        #expect(scan.day == TicketScan.Day(year: 2026, month: 7, day: 18))
    }

    @Test func aGeneralReservedSeatIsTheGeneralClass() {
        let scan = TicketScan(reading: eplusTicket(
            day: "7/19（日）", seatClass: "一般指定席（特製グッズ付き）",
            seat: ["L12扉 3階スタンド", "5列 120番"], price: "¥13,200（税込）"))
        #expect(scan.seat == "L12扉 3階スタンド 5列 120番")
        #expect(scan.seatClass == "一般席")
        #expect(scan.price == Money(amount: 13200, currency: "JPY"))
        #expect(scan.day == TicketScan.Day(year: 2026, month: 7, day: 19))
    }

    /// The day is how the sheet tells the 18th's ticket from the 19th's,
    /// which print the same title, hall and times.
    @Test func theDayTellsOneNightsTicketFromTheNext() {
        let scan = TicketScan(reading: eplusTicket(
            day: "7/18（土）", seatClass: "A席", seat: ["アリーナ B5ブロック", "12列34番"], price: "¥16,500"))
        #expect(scan.day?.isSame(as: CalendarDay(year: 2026, month: 7, day: 18)) == true)
        #expect(scan.day?.isSame(as: CalendarDay(year: 2026, month: 7, day: 19)) == false)
        #expect(scan.day?.isSame(as: CalendarDay(year: 2027, month: 7, day: 18)) == false)
    }

    @Test func aClassWhoseBracketsRunOntoTheNextLineIsReadWhole() {
        let scan = TicketScan(reading: [
            line("一般指定席（特製グッ", x: 0.31, y: 0.594),
            line("ズ付き）", x: 0.31, y: 0.568),
            line("L12扉 3階スタンド", x: 0.31, y: 0.541),
            line("5列 120番", x: 0.31, y: 0.516),
            line("¥13,200（税込）", x: 0.31, y: 0.487, h: 0.022),
        ])
        #expect(scan.seatClass == "一般席")
        #expect(scan.seat == "L12扉 3階スタンド 5列 120番")
    }

    @Test func aLineCutInTwoAtAWideSpaceIsReadAsOne() {
        let scan = TicketScan(reading: [
            line("A席", x: 0.31, y: 0.568),
            line("アリーナ", x: 0.31, y: 0.541, w: 0.15),
            line("B5ブロック", x: 0.52, y: 0.541, w: 0.15),
            line("12列34番", x: 0.31, y: 0.516),
            line("¥16,500", x: 0.31, y: 0.487),
        ])
        #expect(scan.seat == "アリーナ B5ブロック 12列 34番")
    }

    @Test func fullWidthFiguresAreReadPlain() {
        let scan = TicketScan(reading: [
            line("Ｓ席", x: 0.31, y: 0.568),
            line("Ａブロック　５列　１２番", x: 0.31, y: 0.541),
            line("￥１２，０００", x: 0.31, y: 0.516),
        ])
        #expect(scan.seatClass == "S席")
        #expect(scan.seat == "Aブロック 5列 12番")
        #expect(scan.price == Money(amount: 12000, currency: "JPY"))
    }

    /// A standing ticket prints an entry number and no class.
    @Test func aStandingTicketGivesItsEntryNumber() {
        let scan = TicketScan(reading: [
            line("Zepp Haneda(TOKYO)", x: 0.05, y: 0.70),
            line("1Fスタンディング", x: 0.31, y: 0.568),
            line("整理番号 A123", x: 0.31, y: 0.541),
            line("¥7,700(税込)", x: 0.31, y: 0.516),
        ])
        #expect(scan.seat == "1Fスタンディング 整理番号 A123")
        #expect(scan.seatClass == nil)
        #expect(scan.price == Money(amount: 7700, currency: "JPY"))
    }

    // MARK: - Other layouts

    @Test func labelledAnswersAreBelieved() {
        let scan = TicketScan(reading: [
            line("座席はお選びいただけません", x: 0.05, y: 0.80, w: 0.5),
            line("座席", x: 0.05, y: 0.60, w: 0.1),
            line("1階 L列 23番", x: 0.30, y: 0.60),
            line("席種", x: 0.05, y: 0.55, w: 0.1),
            line("S席", x: 0.30, y: 0.55, w: 0.1),
            line("料金", x: 0.05, y: 0.50, w: 0.1),
            line("¥9,900(税込)", x: 0.30, y: 0.50),
        ])
        #expect(scan.seat == "1階 L列 23番")
        #expect(scan.seatClass == "S席")
        #expect(scan.price == Money(amount: 9900, currency: "JPY"))
    }

    /// With no column over the price, the first seat number is taken — and
    /// the hall's address, numbered with 番 too, is not one.
    @Test func aSeatNumberElsewhereIsFoundAndAnAddressIsNot() {
        let scan = TicketScan(reading: [
            line("東京都大田区羽田空港1丁目1番4号", x: 0.05, y: 0.80, w: 0.6),
            line("2026年7月18日(土)", x: 0.05, y: 0.75, w: 0.5),
            line("1階", x: 0.05, y: 0.60, w: 0.1),
            line("L列 23番", x: 0.05, y: 0.575, w: 0.2),
            line("S席 8,800円", x: 0.60, y: 0.40),
        ])
        #expect(scan.seat == "1階 L列 23番")
        #expect(scan.seatClass == "S席")
        #expect(scan.price == Money(amount: 8800, currency: "JPY"))
        #expect(scan.day == TicketScan.Day(year: 2026, month: 7, day: 18))
    }

    /// A paper ticket set flush left prints the hall over the seat, and
    /// ぴあアリーナMM names a part of a hall by its words.
    @Test func aPaperTicketsHallIsNotPartOfItsSeat() {
        let lines = [
            line("MyGO!!!!! 9th LIVE「つなぎ目の向こうに」", x: 0.05, y: 0.80, w: 0.8, h: 0.03),
            line("2026年7月18日(土) 開場16:30 開演18:00", x: 0.05, y: 0.76, w: 0.8, h: 0.03),
            line("ぴあアリーナMM", x: 0.05, y: 0.72, h: 0.03),
            line("アリーナ B5ブロック", x: 0.05, y: 0.68, h: 0.03),
            line("12列 34番", x: 0.05, y: 0.64, h: 0.03),
            line("A席 ¥16,500(税込)", x: 0.05, y: 0.60, h: 0.03),
        ]
        let scan = TicketScan(reading: lines, hall: "ぴあアリーナ MM")
        #expect(scan.seat == "アリーナ B5ブロック 12列 34番")
        #expect(scan.seatClass == "A席")
        #expect(scan.price == Money(amount: 16500, currency: "JPY"))
        #expect(scan.day == TicketScan.Day(year: 2026, month: 7, day: 18))
    }

    /// Printed with wide gaps, 12列 and 34番 are two lines to Vision.
    @Test func aSeatPrintedApartAlongItsRowIsReadWhole() {
        let scan = TicketScan(reading: [
            line("1階", x: 0.05, y: 0.60, w: 0.1, h: 0.03),
            line("12列", x: 0.05, y: 0.56, w: 0.1, h: 0.03),
            line("34番", x: 0.25, y: 0.56, w: 0.1, h: 0.03),
            line("S席", x: 0.60, y: 0.40, w: 0.1, h: 0.03),
            line("¥9,900", x: 0.60, y: 0.36, w: 0.2, h: 0.03),
        ])
        #expect(scan.seat == "1階 12列 34番")
        #expect(scan.seatClass == "S席")
    }

    /// A part of a hall with no number is no seat — and may be the hall.
    @Test func aPartOfAHallAloneIsNoSeat() {
        let scan = TicketScan(reading: [
            line("ぴあアリーナMM", x: 0.3, y: 0.60),
            line("¥16,500", x: 0.3, y: 0.56),
        ])
        #expect(scan.seat == nil)
        #expect(scan.price == Money(amount: 16500, currency: "JPY"))
    }

    @Test func aPriceInTheFinePrintIsNotTheTicketsPrice() {
        let scan = TicketScan(reading: [
            line("※別途システム利用料¥330がかかります", x: 0.05, y: 0.80, w: 0.6),
            line("A席", x: 0.31, y: 0.568),
            line("12列34番", x: 0.31, y: 0.541),
            line("¥16,500", x: 0.31, y: 0.516),
        ])
        #expect(scan.price == Money(amount: 16500, currency: "JPY"))
    }

    @Test func aPictureWithNoTicketOnItSaysNothing() {
        let scan = TicketScan(reading: [
            line("MyGO!!!!! 9th LIVE", x: 0.05, y: 0.8),
            line("16:30開場 18:00開演", x: 0.05, y: 0.7),
            line("チケット番号:1234567890123", x: 0.05, y: 0.6),
        ])
        #expect(scan.isEmpty)
    }

    // MARK: - Which way up

    /// `lines` as Vision gives them for a picture lying turned `way` — 1 on
    /// its side reading up, 2 upside down, 3 on its side reading down — each
    /// by its text and its corners as the text reads.
    private func lying(_ lines: [TicketScan.Line], way: Int) -> [(text: String, corners: [CGPoint])] {
        func laid(_ point: CGPoint) -> CGPoint {
            switch way {
            case 1: CGPoint(x: 1 - point.y, y: point.x)
            case 2: CGPoint(x: 1 - point.x, y: 1 - point.y)
            case 3: CGPoint(x: point.y, y: 1 - point.x)
            default: point
            }
        }
        return lines.map { line in
            let frame = line.frame
            let corners = [CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY),
                           CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.minX, y: frame.minY)]
            return (text: line.text, corners: corners.map(laid))
        }
    }

    /// Vision reads a ticket photographed on its side or upside down, but
    /// boxes its lines as the picture lies; read as they lay, the e+ seat
    /// came out reversed, and with the notes in it.
    @Test(arguments: [0, 1, 2, 3]) func aTicketReadsTheSameWhicheverWayUpItLies(way: Int) {
        let upright = eplusTicket(day: "7/18（土）", seatClass: "A席（特製グッズ付き）",
                                  seat: ["アリーナ B5ブロック", "12列34番"], price: "¥16,500（税込）")
        let scan = TicketScan(reading: TicketScan.Line.upright(lying(upright, way: way)))
        #expect(scan == TicketScan(reading: upright))
        #expect(scan.seat == "アリーナ B5ブロック 12列 34番")
    }

    /// A paper ticket's stub prints the seat again across the ticket, level
    /// with the seat; joined along the row, the seat came out twice.
    @Test func aStubAcrossTheTicketIsNotPartOfTheSeat() {
        let scan = TicketScan(reading: [
            line("ぴあアリーナMM", x: 0.03, y: 0.735, w: 0.13, h: 0.045),
            line("アリーナ B5ブロック", x: 0.03, y: 0.587, w: 0.28, h: 0.069),
            line("12列34番", x: 0.79, y: 0.600, w: 0.07, h: 0.045),
            line("12列 34番", x: 0.03, y: 0.467, w: 0.14, h: 0.086),
            line("A席 ¥16,500(税込)", x: 0.03, y: 0.350, w: 0.18, h: 0.059),
        ], hall: "ぴあアリーナMM")
        #expect(scan.seat == "アリーナ B5ブロック 12列 34番")
    }

    // MARK: - Pieces

    @Test func aClassIsKeptAsTheAppKeepsOne() {
        #expect(TicketScan.seatClass(printed: "S席") == "S席")
        #expect(TicketScan.seatClass(printed: "A席(特製グッズ付き)") == "A席")
        #expect(TicketScan.seatClass(printed: "一般指定席") == "一般席")
        #expect(TicketScan.seatClass(printed: "SS席") == "SS席")
        #expect(TicketScan.seatClass(printed: "VIP席【グッズ付】") == "VIP席")
        #expect(TicketScan.seatClass(printed: "全席指定") == nil)
    }

    @Test func aPriceIsReadInYen() {
        #expect(TicketScan.yen(in: "¥16,500(税込)") == 16500)
        #expect(TicketScan.yen(in: "\\8,800") == 8800)
        #expect(TicketScan.yen(in: "8,800円") == 8800)
        #expect(TicketScan.yen(in: "¥0") == 0)
        #expect(TicketScan.yen(in: "チケット番号:1234567890123") == nil)
        #expect(TicketScan.yen(in: "¥12345678") == nil)
    }

    @Test func aDayWithNoYearIsAnyYears() {
        let day = TicketScan.Day(year: nil, month: 7, day: 18)
        #expect(day?.isSame(as: CalendarDay(year: 2027, month: 7, day: 18)) == true)
        #expect(day?.calendarDay(orIn: 2027) == CalendarDay(year: 2027, month: 7, day: 18))
        #expect(TicketScan.Day(year: 2026, month: 13, day: 1) == nil)
    }
}
