import SwiftUI

extension Text {
    /// A time as the reader's locale writes it on `zone`'s clock, with the AM
    /// or PM a twelve-hour clock carries set small beside the digits — how an
    /// event's sheet and its Live Activity print one, so the two read the
    /// same. A dash where there is no time.
    static func clock(_ instant: Date?, in zone: TimeZone, size: CGFloat) -> Text {
        guard let instant else { return Text(verbatim: "—") }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        var time = instant.formatted(style.attributedStyle)
        let periods = time.runs[\.dateField].compactMap { field, range in
            field == .amPM ? range : nil
        }
        for range in periods {
            time[range].font = .system(size: size * 0.6, weight: .bold)
        }
        return Text(time)
    }
}
