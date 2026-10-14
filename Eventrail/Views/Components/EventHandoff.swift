import SwiftUI

/// The event open in front of the reader, offered to their other devices
/// through Handoff — and an event another device offered, opened here.
///
/// The activity carries the event's Eventernote page as its `webpageURL`, so a
/// device without Eventrail — and a Mac — continues it in the browser, on the
/// page the event was read from. A device with the app opens the event's sheet
/// over whatever it has up (``OutsideOpens``), as a Live Activity tapped does.
///
/// Advertised once per window, from the root, rather than by each sheet: an
/// event's sheet can stand over another's — a billed performer's page pushed
/// in it, and one of their dates opened from there — and two views in a scene
/// advertising one activity type leave it to SwiftUI which of them is heard.
/// So every event sheet on screen stands here at the depth it was presented at
/// (``View/advertisesHandoff(of:)``), as ``RefreshNotices`` ranks its
/// overlays, and the frontmost is the one offered.
@Observable
final class EventHandoff {
    /// The activity's type, as `NSUserActivityTypes` in Info.plist claims it —
    /// the one thing a device checks to decide whether the app can take it.
    nonisolated static let activityType = "moe.shawn.Eventrail.event"

    /// The event in the frontmost sheet, or nil while no event's sheet is up.
    private(set) var shown: Event?

    /// Every event sheet on screen, by how many sheets deep it stands.
    @ObservationIgnored private var standing: [UUID: (depth: Int, event: Event)] = [:]

    fileprivate func stand(_ id: UUID, at depth: Int, showing event: Event) {
        standing[id] = (depth, event)
        settle()
    }

    fileprivate func leave(_ id: UUID) {
        standing[id] = nil
        settle()
    }

    /// The deepest sheet's event, and one of two at a depth — a sheet going as
    /// another comes — by a fixed rule.
    private func settle() {
        let front = standing
            .max { ($0.value.depth, $0.key.uuidString) < ($1.value.depth, $1.key.uuidString) }?
            .value.event
        if front != shown { shown = front }
    }

    // MARK: - The activity

    private nonisolated static let eventKey = "event"

    /// Makes `activity` the offer of `event`.
    nonisolated static func fill(_ activity: NSUserActivity, with event: Event) {
        activity.title = event.title
        activity.webpageURL = event.sourceURL
        activity.isEligibleForHandoff = true
        activity.userInfo = payload(for: event).map { [eventKey: $0] } ?? [:]
    }

    /// The event as a listing row carries it, so the other device can open a
    /// sheet on an event it does not hold — one found in Search, or a date
    /// from Following — with its flyer, day and hall drawn at once.
    ///
    /// The page's free-written parts stay behind: 概要 alone runs to kilobytes,
    /// and Handoff asks for a payload of a few. Its `detailFormat` goes with
    /// them, so the sheet that opens on the copy reads the page for the rest
    /// (``Event/isFullyDetailed``) — and a copy added to the library before
    /// that read lands is read again the next time it is opened.
    nonisolated static func payload(for event: Event) -> Data? {
        var row = event
        row.summary = nil
        row.relatedLinks = nil
        row.hashtags = nil
        row.editedBy = nil
        row.editedAt = nil
        row.detailFormat = nil
        row.readAt = nil
        return try? JSONEncoder().encode(row)
    }

    /// The copy of the event a continued activity carried, if this build can
    /// read it: the phone and the iPad are updated apart, and one a build
    /// behind may send an event this one cannot decode.
    nonisolated static func event(in activity: NSUserActivity) -> Event? {
        guard let data = activity.userInfo?[eventKey] as? Data else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }
}

extension View {
    /// Offers `event` to the reader's other devices for as long as this view
    /// is on screen and no event's sheet stands in front of it — see
    /// ``EventHandoff``. On the root of an event's sheet.
    func advertisesHandoff(of event: Event) -> some View {
        modifier(EventHandoffStand(event: event))
    }
}

private struct EventHandoffStand: ViewModifier {
    let event: Event

    @Environment(EventHandoff.self) private var handoff: EventHandoff?
    @Environment(\.outsideOpenDepth) private var depth
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { handoff?.stand(id, at: depth, showing: event) }
            // Again with every new copy, so a title or a start time the page
            // brings in is what the other device opens.
            .onChange(of: event) { handoff?.stand(id, at: depth, showing: event) }
            .onDisappear { handoff?.leave(id) }
    }
}
