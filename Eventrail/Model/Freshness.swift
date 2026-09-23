import SwiftUI

/// How long anything read from Eventernote — or from the host its flyers live
/// on — stands before the app reads it again by itself.
///
/// One window for all of it, so "how fresh is this" has one answer wherever
/// the reader looks: the Following tab's listings (``FollowedDates``), an
/// event's own page (``PageReads``), a performer's or a hall's page
/// (``ListingCache``) and every flyer (``ImageCache``). Past it, a screen reads
/// again as it opens or as the app comes back to the foreground; inside it,
/// nothing is asked. A manual refresh is never held to it, and starts it
/// again from the moment it lands.
///
/// Where each hall *is* is deliberately not on this clock — see
/// ``VenuePlaces`` and ``VenueRegions``. A hall does not move, and asking
/// about every one of them every few hours is the run of lookups that once
/// got this app throttled into placing nothing at all.
nonisolated enum Freshness {
    static let window: TimeInterval = 6 * 60 * 60
}

extension EnvironmentValues {
    /// When the screen around a flyer was last refreshed by hand. Any flyer on
    /// it whose host was last asked before then is asked again as it draws —
    /// see ``CachedImage`` — so a pull refreshes the artwork on the screen as
    /// well as the rows, and each flyer is asked once, not once per scroll.
    @Entry var imagesCheckedSince: Date? = nil
}
