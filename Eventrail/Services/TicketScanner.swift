import Foundation
import ImageIO
import Vision

/// What a ticket says about the seat it sold, read off a picture of it: where
/// the seat is, the class it was sold as, its price and the day it is for.
///
/// Built for the e+ スマチケ screen first of all — a screenshot of the ticket
/// in e+'s app, which prints the class, the seat over one or two lines and
/// the price in one column of the ticket's card, beside the 未使用 stamp:
///
///     A席（特製グッズ付き）
///     アリーナ B5ブロック
///     12列 34番
///     ¥16,500(税込)
///
/// So the column the price is printed in is read upwards from it, line by
/// line while the lines stay close (``column(above:in:)``). Read top to
/// bottom across the card instead, the stamp falls between the seat and the
/// price. Where a ticket labels its answers (座席, 席種), the labels are
/// believed first; where neither finds a seat — a paper ticket, laid out
/// every way a promoter likes — the first line naming a seat number is taken,
/// with the lines over it that name a part of the hall. A seat found by
/// layout always carries a number (列, 番, 整理番号), and never the hall's
/// own name, which a paper ticket prints over the seat and which names a part
/// of a hall by its words (ぴあアリーナMM). A changed layout yields a missing
/// answer rather than a wrong one where it can, and every answer is shown to
/// the reader before it is written anywhere.
///
/// Nothing else on the ticket is read into anything: not the holder's name,
/// not the ticket number, not the picture itself.
nonisolated struct TicketScan: Hashable, Sendable {
    /// Where the seat is, on one line: アリーナ B5ブロック 12列 34番.
    var seat: String?
    /// The class, as ``Tracking/seatClass`` keeps one — see
    /// ``seatClass(printed:)``.
    var seatClass: String?
    /// The face value, in yen: a ticket printed in Japan prints no other.
    var price: Money?
    /// The day the ticket is for, as printed.
    var day: Day?

    /// Whether the picture said nothing the ticket sheet asks.
    var isEmpty: Bool { seat == nil && seatClass == nil && price == nil }

    /// One line of text on the picture, as Vision found it.
    nonisolated struct Line: Equatable, Sendable {
        var text: String
        /// Where it stands, in fractions of the picture's width and height
        /// measured from its lower-left corner, as Vision gives it.
        var frame: CGRect
    }

    /// A day as a ticket prints it: e+ prints the year on a line of its own
    /// over 7/18（土）, and a ticket may leave it out altogether.
    nonisolated struct Day: Hashable, Sendable {
        var year: Int?
        var month: Int
        var day: Int

        init?(year: Int?, month: Int, day: Int) {
            guard (1...12).contains(month), (1...31).contains(day) else { return nil }
            if let year, !(2000...2100).contains(year) { return nil }
            self.year = year
            self.month = month
            self.day = day
        }

        /// Whether this is `other`, by the month and day — and by the year,
        /// where one is printed.
        func isSame(as other: CalendarDay) -> Bool {
            month == other.month && day == other.day && (year ?? other.year) == other.year
        }

        /// The day, in `fallback` where the ticket printed no year.
        func calendarDay(orIn fallback: Int) -> CalendarDay {
            CalendarDay(year: year ?? fallback, month: month, day: day)
        }
    }
}

nonisolated extension TicketScan {
    /// What `recognized` says about the ticket for an event at `hall` — see
    /// ``TicketScan``.
    init(reading recognized: [Line], hall: String? = nil) {
        let lines = recognized.compactMap(Self.cleaned).sorted {
            $0.frame.midY != $1.frame.midY ? $0.frame.midY > $1.frame.midY : $0.frame.minX < $1.frame.minX
        }
        let hall = hall.map(Self.squeezed).flatMap { $0.count >= 2 ? $0 : nil }
        let namesHall = { (text: String) in Self.names(hall, in: text) }
        day = Self.printedDay(in: lines)

        // A ticket that labels its answers says which is which outright. The
        // label and the answer can be two lines on one row, so a row is read
        // from each line rightwards. A label is set off from its answer, and
        // a seat carries a number, so 座席はお選びいただけません is neither.
        for line in lines where !Self.isFinePrint(line.text) {
            let row = Self.row(from: line, in: lines)
            if seat == nil,
               let answer = row.firstMatch(of: /^(?:お?座席(?:番号)?|席番)(?:\s*:\s*|\s+)(.+)$/)?.1,
               answer.contains(where: \.isNumber) {
                seat = Self.seat(from: [Self.withoutPrice(String(answer))])
            }
            if seatClass == nil,
               let answer = row.firstMatch(of: /^(?:席種(?:名)?|券種)(?:\s*:\s*|\s+)(.+)$/)?.1 {
                seatClass = Self.seatClass(printed: Self.withoutPrice(String(answer)))
            }
        }

        let priceLine = lines.first { !Self.isFinePrint($0.text) && Self.yen(in: $0.text) != nil }
        price = priceLine.flatMap { Self.yen(in: $0.text) }.map { Money(amount: $0, currency: Currencies.yen) }

        // The column the price heads the foot of: the class, then the seat.
        if let priceLine, seat == nil || seatClass == nil {
            let block = Self.column(above: priceLine, in: lines).map { Self.row(from: $0, in: lines) }
            if let index = block.firstIndex(where: Self.namesClass) {
                var printed = block[index]
                var rest = block[(index + 1)...]
                // A long class whose brackets run onto the next line.
                while Self.leavesBracketOpen(printed), let next = rest.first {
                    printed += next
                    rest = rest.dropFirst()
                }
                if seatClass == nil { seatClass = Self.seatClass(printed: printed) }
                if seat == nil { seat = Self.numberedSeat(from: rest.filter { !namesHall($0) }) }
            } else if seat == nil {
                // No class to start from: the lines straight over the price
                // that name a part of the hall.
                let run = block.reversed().prefix { Self.namesSeat($0) && !namesHall($0) }
                seat = Self.numberedSeat(from: run.reversed())
            }
        }

        // Laid out some other way: the first line naming a seat number — and
        // what stands beside it on its row, where 12列 and 34番 are printed
        // apart — with up to two lines over it that say which part of the
        // hall: アリーナ over B5ブロック over 12列 34番.
        if seat == nil,
           let line = lines.first(where: {
               !Self.isFinePrint($0.text) && Self.namesSeatNumber($0.text) && !namesHall($0.text)
           }) {
            var parts = [Self.seatRow(from: line, in: lines, hall: hall)]
            for above in Self.column(above: line, in: lines).reversed().prefix(2) {
                guard Self.namesPartOfHall(above.text), !namesHall(above.text) else { break }
                parts.insert(above.text, at: 0)
            }
            seat = Self.seat(from: parts)
        }
        if seatClass == nil,
           let line = lines.first(where: {
               let name = Self.withoutBrackets(Self.withoutPrice($0.text))
               return Self.namesClass($0.text) && name.hasSuffix("席") && name.count <= 12
           }) {
            seatClass = Self.seatClass(printed: Self.withoutPrice(line.text))
        }
    }

    /// A class as the app keeps one: one of ``SeatClass`` as the ticket
    /// prints it — S席, A席, and 一般席 for any 一般 class (一般指定席) — or
    /// otherwise as printed (SS席, VIP席), what the brackets add (特製グッズ付き)
    /// left off. Nil for a line about the whole house, 全席指定.
    static func seatClass(printed: String) -> String? {
        let name = withoutBrackets(printed)
        guard !name.isEmpty, !name.hasPrefix("全席") else { return nil }
        if let known = SeatClass(rawValue: name) { return known.rawValue }
        if name.hasPrefix("一般") { return SeatClass.general.rawValue }
        return name
    }

    // MARK: - Reading lines

    /// The text with full-width letters, digits and signs made plain (Ｂ５
    /// is B5, ￥ is ¥) and its spaces closed up; nil where nothing is left.
    private static func cleaned(_ line: Line) -> Line? {
        let text = line.text.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : Line(text: text, frame: line.frame)
    }

    /// The notes under a ticket rather than its answers: a ※ line, a link,
    /// or anything as long as a sentence.
    private static func isFinePrint(_ text: String) -> Bool {
        text.hasPrefix("※") || text.hasPrefix("*") || text.contains("http") || text.count > 40
    }

    /// The lines printed straight over `line` in its column, top first, for
    /// as long as no gap wider than a line opens between them.
    static func column(above line: Line, in lines: [Line]) -> [Line] {
        let above = lines
            .filter { $0 != line && abs($0.frame.minX - line.frame.minX) <= 0.03 && $0.frame.midY > line.frame.maxY }
            .sorted { $0.frame.midY < $1.frame.midY }
        var block: [Line] = []
        var under = line
        for next in above {
            guard block.count < 6,
                  next.frame.minY - under.frame.maxY <= max(next.frame.height, under.frame.height) * 1.5
            else { break }
            block.insert(next, at: 0)
            under = next
        }
        return block
    }

    /// `line` and whatever stands to its right on the same row — a value
    /// beside its label, or a line Vision cut in two at a wide space.
    private static func row(from line: Line, in lines: [Line]) -> String {
        ([line] + beside(line, in: lines)).map(\.text).joined(separator: " ")
    }

    /// What stands to the right of `line` on its row, nearest first, for as
    /// long as each piece is near the one before it and `belongs` — a value
    /// beside its label, a line cut in two at a wide space — but not the
    /// stub across a paper ticket, which prints the seat again at its far
    /// edge, nor the notes.
    private static func beside(_ line: Line, in lines: [Line],
                               where belongs: (String) -> Bool = { _ in true }) -> [Line] {
        let candidates = lines
            .filter { $0 != line && $0.frame.minX > line.frame.minX && sharesRow($0, line) && !isFinePrint($0.text) }
            .sorted { $0.frame.minX < $1.frame.minX }
        var row: [Line] = []
        var last = line
        for next in candidates {
            guard next.frame.minX - last.frame.maxX <= 0.3, belongs(next.text) else { break }
            row.append(next)
            last = next
        }
        return row
    }

    private static func sharesRow(_ a: Line, _ b: Line) -> Bool {
        let overlap = min(a.frame.maxY, b.frame.maxY) - max(a.frame.minY, b.frame.minY)
        return overlap > min(a.frame.height, b.frame.height) / 2
    }

    // MARK: - Reading answers

    /// A price in yen: ¥16,500 — or \16,500, as a Japanese font draws the
    /// backslash — or 16,500円.
    static func yen(in text: String) -> Decimal? {
        let figures = text.firstMatch(of: /[¥\\]\s*([0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,7})(?![0-9])/)?.1
            ?? text.firstMatch(of: /([0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,7})\s*円/)?.1
        return figures.flatMap { Decimal(string: $0.filter(\.isNumber)) }
    }

    /// The text with any price in it, and the 税込 after one, taken out.
    private static func withoutPrice(_ text: String) -> String {
        text.replacing(/[¥\\]\s*[0-9][0-9,]*|[0-9][0-9,]*\s*円/, with: "")
            .replacing(/\(税込\)|税込/, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The text with what its brackets add taken out — A席（特製グッズ付き）
    /// is A席 — and an unclosed bracket's tail with them.
    private static func withoutBrackets(_ text: String) -> String {
        text.replacing(/\([^)]*\)?|【[^】]*】?|<[^>]*>?/, with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func leavesBracketOpen(_ text: String) -> Bool {
        text.filter { $0 == "(" }.count > text.filter { $0 == ")" }.count
            || text.filter { $0 == "【" }.count > text.filter { $0 == "】" }.count
    }

    /// Whether a line names a class of seat: short, with 席 in it and no row
    /// or number — A席（特製グッズ付き）, 一般指定席, 全席指定.
    private static func namesClass(_ text: String) -> Bool {
        let name = withoutBrackets(withoutPrice(text))
        return name.contains("席") && name.count <= 16 && !isFinePrint(text)
            && !name.contains(/[0-9]+\s*(?:列|番)/)
    }

    /// Whether a line names a part of the hall or a place in it.
    private static func namesSeat(_ text: String) -> Bool {
        text.contains(/[0-9]+\s*(?:列|番(?!号|目|地)|段|階|F(?![A-Za-z]))|ブロック|扉|ゲート|スタンド|バルコニー|アリーナ|エリア|整理番号|(?i:block|row|gate)/)
    }

    /// Whether a line names a seat's number — 12列 34番, 整理番号 A123 — and
    /// not an address, which numbers its blocks with 番 too.
    private static func namesSeatNumber(_ text: String) -> Bool {
        text.count <= 30
            && text.contains(/[0-9]+\s*(?:列|番(?!号|目|地))|整理番号/)
            && !text.contains(/丁目|番地|〒|[0-9]+\s*番\s*[0-9]+\s*号/)
    }

    /// Whether a line says which part of the hall a seat is in — アリーナ,
    /// B5ブロック, 3階スタンド — and nothing else: no number, class, price.
    private static func namesPartOfHall(_ text: String) -> Bool {
        text.count <= 16 && namesSeat(text) && !namesSeatNumber(text) && !namesClass(text) && yen(in: text) == nil
    }

    /// A seat-number line and whatever stands to its right on its row that
    /// is part of the seat — 34番 printed apart from 12列 — but not the class
    /// or the price printed on the same row.
    private static func seatRow(from line: Line, in lines: [Line], hall: String?) -> String {
        let pieces = beside(line, in: lines) {
            namesSeat($0) && !namesClass($0) && yen(in: $0) == nil && !names(hall, in: $0)
        }
        return ([withoutPrice(line.text)] + pieces.map(\.text)).joined(separator: " ")
    }

    /// Whether `text` names the hall — `hall` as ``squeezed(_:)`` leaves it,
    /// or none.
    private static func names(_ hall: String?, in text: String) -> Bool {
        hall.map { squeezed(text).contains($0) } ?? false
    }

    /// The text with its letters made plain and its spaces taken out, to
    /// tell whether a line names the hall however its spaces fell.
    private static func squeezed(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
    }

    /// ``seat(from:)``, where one of the lines carries a seat's number: a
    /// part of the hall alone is not a seat, and may be the hall itself.
    private static func numberedSeat(from lines: some Sequence<String>) -> String? {
        let lines = Array(lines)
        return lines.contains(where: namesSeatNumber) ? seat(from: lines) : nil
    }

    /// The seat's lines as one, spaced as a ticket spaces them: 12列 34番, not
    /// the 12列34番 Vision tends to read.
    private static func seat(from lines: [String]) -> String? {
        let seat = lines.joined(separator: " ")
            .replacing(/(列|ブロック|扉|ゲート|階)(?=[0-9A-Za-z])/) { "\($0.1) " }
            .split(separator: " ").joined(separator: " ")
        return seat.isEmpty ? nil : seat
    }

    /// The day the ticket is for: 2026年7月18日 or 2026/7/18 on one line, or
    /// e+'s 2026年 over 7/18（土）.
    private static func printedDay(in lines: [Line]) -> Day? {
        let texts = lines.map(\.text).filter { !isFinePrint($0) }
        for text in texts {
            if let match = text.firstMatch(of: /([0-9]{4})\s*[年\/.\-]\s*([0-9]{1,2})\s*[月\/.\-]\s*([0-9]{1,2})/),
               let day = Day(year: Int(match.1), month: Int(match.2) ?? 0, day: Int(match.3) ?? 0) {
                return day
            }
        }
        let year = texts.lazy.compactMap { $0.firstMatch(of: /([0-9]{4})\s*年/).flatMap { Int($0.1) } }.first
        for text in texts {
            if let match = text.firstMatch(of: /(?:^|[^0-9\/])([0-9]{1,2})\s*(?:\/|月)\s*([0-9]{1,2})(?:$|[^0-9\/:])/),
               let day = Day(year: year, month: Int(match.1) ?? 0, day: Int(match.2) ?? 0) {
                return day
            }
        }
        return nil
    }
}

nonisolated extension TicketScan.Line {
    /// Lines as Vision found them on a picture lying any way up — each by
    /// its text and its corners, top left, top right, bottom right and
    /// bottom left as the text reads — set the way most of the text reads.
    ///
    /// Vision reads text at any angle: a paper ticket photographed with the
    /// phone held upright, its lines running up the picture, or one upside
    /// down. But it boxes each line as the picture lies, and ``TicketScan``
    /// reads a ticket by its layout — a column, a row, what is over what — so
    /// read upside down every line came in reverse, and on its side the whole
    /// ticket stood in one row. The way from a line's top-left corner to its
    /// top-right one is the way it reads, and the picture is turned until
    /// most of its text, by the character, reads rightwards.
    static func upright(_ found: [(text: String, corners: [CGPoint])]) -> [TicketScan.Line] {
        // Right, up, left, down.
        var ways = [0, 0, 0, 0]
        for (text, corners) in found where corners.count == 4 {
            let dx = corners[1].x - corners[0].x
            let dy = corners[1].y - corners[0].y
            ways[abs(dx) >= abs(dy) ? (dx >= 0 ? 0 : 2) : (dy >= 0 ? 1 : 3)] += text.count
        }
        let way = ways.indices.max { ways[$0] < ways[$1] } ?? 0
        // In fractions of the picture from its lower-left corner, which a
        // quarter turn carries onto the turned picture's.
        func turned(_ point: CGPoint) -> CGPoint {
            switch way {
            case 1: CGPoint(x: point.y, y: 1 - point.x)
            case 2: CGPoint(x: 1 - point.x, y: 1 - point.y)
            case 3: CGPoint(x: 1 - point.y, y: point.x)
            default: point
            }
        }
        return found.compactMap { text, corners in
            let points = corners.map(turned)
            guard let left = points.map(\.x).min(), let right = points.map(\.x).max(),
                  let bottom = points.map(\.y).min(), let top = points.map(\.y).max()
            else { return nil }
            return TicketScan.Line(text: text, frame: CGRect(x: left, y: bottom, width: right - left, height: top - bottom))
        }
    }
}

/// Reads a picture of a ticket on the device, with Apple's Vision: the
/// picture never leaves the phone and is not kept once read.
nonisolated enum TicketScanner {
    /// What the pictures — a screenshot from Photos, or the pages the
    /// document camera took — say about the ticket for an event at `hall`:
    /// the first that says anything.
    @concurrent static func scan(_ pictures: [Data], hall: String? = nil) async throws -> TicketScan {
        for picture in pictures {
            let scan = TicketScan(reading: try await lines(in: picture), hall: hall)
            if !scan.isEmpty { return scan }
        }
        return TicketScan()
    }

    /// The lines of text on the picture, Japanese first, set upright
    /// (``TicketScan/Line/upright(_:)``) — read once, whichever way up the
    /// picture was taken.
    @concurrent static func lines(in imageData: Data) async throws -> [TicketScan.Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: imageData, orientation: orientation(of: imageData))
        return TicketScan.Line.upright(observations.compactMap { observation in
            observation.topCandidates(1).first.map {
                (text: $0.string, corners: [observation.topLeft.cgPoint, observation.topRight.cgPoint,
                                            observation.bottomRight.cgPoint, observation.bottomLeft.cgPoint])
            }
        })
    }

    /// Which way up a photo was taken, as its file says.
    private static func orientation(of imageData: Data) -> CGImagePropertyOrientation? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32
        else { return nil }
        return CGImagePropertyOrientation(rawValue: raw)
    }
}
