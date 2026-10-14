import SwiftUI
import WidgetKit

/// Everything the app draws outside itself: the event's Live Activity, and
/// the home and Lock Screen widgets — the next event, the lotteries waiting
/// on their results, and On This Day.
@main struct EventrailWidgets: WidgetBundle {
    var body: some Widget {
        EventLiveActivity()
        NextEventWidget()
        LotteriesWidget()
        OnThisDayWidget()
    }
}
