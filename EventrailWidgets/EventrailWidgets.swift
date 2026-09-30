import SwiftUI
import WidgetKit

/// Everything the app draws outside itself. Only the Live Activity so far.
@main struct EventrailWidgets: WidgetBundle {
    var body: some Widget {
        EventLiveActivity()
    }
}
