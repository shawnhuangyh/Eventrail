import SwiftUI

/// What one refresh says when it is done: that it worked, or that it did not
/// and why.
///
/// **A refresh the reader asked for always says how it went; one the app
/// started by itself speaks only when it failed.** A pull, the Me card's
/// Refresh, Settings' venue refresh and a Try Again are the reader asking, and
/// a pull that visibly changed nothing needs "Updated" to say it worked. Opening
/// a page for the first time, opening one that has gone stale, and coming back
/// to the app are the app keeping itself current — an "Updated" there would be
/// on every other page opened, saying nothing the page does not already show.
/// A failure is worth saying either way: it is why the page is older than it
/// looks. See ``RefreshNotices/report(_:byHand:)``.
///
/// Deliberately two words and a reason. What a refresh brought in is on the
/// screen behind the notice already; the notice only has to say whether to
/// trust it.
struct RefreshNotice: Identifiable, Equatable {
    let id = UUID()
    /// Why the refresh failed, in the words of whatever refused it. Nil for one
    /// that went through.
    let failure: String?

    var succeeded: Bool { failure == nil }

    static var updated: RefreshNotice { RefreshNotice(failure: nil) }

    static func failed(_ reason: String) -> RefreshNotice { RefreshNotice(failure: reason) }
}

/// The one notice on screen, shared by every screen that refreshes.
///
/// In the environment rather than held by each screen, because a refresh can
/// outlive the screen that started it: the Welcome screen's first import is
/// still running long after the Welcome screen has gone.
@Observable
final class RefreshNotices {
    private(set) var current: RefreshNotice?

    /// Every place on screen able to draw a notice now, with how far in front
    /// it stands — see ``RefreshNoticeOverlay/rank``. Only the frontmost
    /// draws, or the same notice would show twice: once in a sheet and once
    /// again behind it, which an iPad's form sheet leaves in view, or once
    /// above a page's bar and once again over it.
    fileprivate var standing: [UUID: Int] = [:]

    fileprivate var front: Int? { standing.values.max() }

    @ObservationIgnored private var dismissal: Task<Void, Never>?

    func post(_ notice: RefreshNotice) {
        // The same news twice in a row — two screens that joined one read, each
        // reporting it — keeps the notice already up rather than sliding a copy
        // of it in over itself. Its time on screen starts again.
        if current == nil || current?.failure != notice.failure { current = notice }
        let notice = current ?? notice
        dismissal?.cancel()
        // A failure stays up longer: it is the one with a reason worth reading
        // to the end.
        let shownFor: Duration = notice.succeeded ? .seconds(3) : .seconds(5)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: shownFor)
            guard !Task.isCancelled else { return }
            self?.dismiss(notice)
        }
    }

    /// Posts what a refresh came to — all of it for one the reader asked for,
    /// and only a failure for one the app started by itself.
    func report(_ notice: RefreshNotice, byHand: Bool) {
        guard byHand || !notice.succeeded else { return }
        post(notice)
    }

    func dismiss(_ notice: RefreshNotice) {
        guard current?.id == notice.id else { return }
        current = nil
    }
}

// MARK: - What each refresh says

extension RefreshNotice {
    /// The Following tab, or the Me card reading the same listings. A run that
    /// fell short anywhere is a failure: some of the dates on screen were not
    /// refreshed, and "Updated" would say they all were.
    static func following(_ outcome: FollowedDates.Outcome) -> RefreshNotice {
        outcome.failure.map { .failed($0) } ?? .updated
    }

    /// One event's sheet.
    static func event(_ read: EventStore.PageRead) -> RefreshNotice {
        switch read {
        case .updated: .updated
        case .failed(let reason): .failed(reason)
        }
    }

    /// The library, after Refresh on the Me card or the Welcome screen's first
    /// import.
    static func library(failure: String?) -> RefreshNotice {
        failure.map { .failed($0) } ?? .updated
    }

    /// Refresh Venue Locations in Settings. Nil while a run is still going —
    /// its end is what gets a notice.
    static func venues(_ refresh: VenuePlaces.Refresh?) -> RefreshNotice? {
        switch refresh {
        case .refreshed: .updated
        case .failed(let reason): .failed(reason)
        case .asking, .none: nil
        }
    }
}

// MARK: - Drawing it

extension EnvironmentValues {
    /// How many sheets drawing notices of their own stand between this view
    /// and the tabs — see ``View/refreshNoticesInSheet()``.
    @Entry var refreshNoticeDepth = 0
}

extension View {
    /// Draws whatever notice is up along the bottom of this screen.
    ///
    /// On each tab's own content rather than once over the tab view: a tab's
    /// safe area already stops short of the floating tab bar, so the notice
    /// rests just above it on an iPhone and at the foot of the screen on an
    /// iPad, where the bar sits at the top — with no height of the bar's
    /// written down here to go stale. And once more inside each sheet that can
    /// start a refresh, since a sheet covers the tab that would otherwise draw
    /// it; and on each page with a bar or a capsule along its foot — an
    /// event's sheet, a performer's or a hall's page, the Following tab, My
    /// Events and the full Favorite Events list under their capsules — inside
    /// that page, since only its own safe area knows the bar is there.
    ///
    /// `aboveBar` marks those pages: one stands in front of whatever holds it,
    /// so a tab or a sheet keeps quiet while it is up — see
    /// ``RefreshNotices/standing``.
    ///
    /// `showing` is for a sheet that draws its notices in two places — an
    /// event's, above its action bar at the root and over the whole stack
    /// once a page is pushed — so that only one of them draws at a time.
    func refreshNotices(aboveBar: Bool = false, showing: Bool = true) -> some View {
        modifier(RefreshNoticeOverlay(aboveBar: aboveBar, showing: showing))
    }

    /// Marks this view as a sheet that draws notices of its own, so they stand
    /// in front of those of the screen it covers. On the sheet's whole content,
    /// outside its own ``refreshNotices(aboveBar:showing:)``.
    func refreshNoticesInSheet() -> some View {
        modifier(RefreshNoticeSheet())
    }
}

private struct RefreshNoticeSheet: ViewModifier {
    @Environment(\.refreshNoticeDepth) private var depth

    func body(content: Content) -> some View {
        content.environment(\.refreshNoticeDepth, depth + 1)
    }
}

private struct RefreshNoticeOverlay: ViewModifier {
    /// Optional, so a preview with no notices in its environment still draws.
    @Environment(RefreshNotices.self) private var notices: RefreshNotices?
    @Environment(\.refreshNoticeDepth) private var depth
    let aboveBar: Bool
    let showing: Bool

    @State private var id = UUID()
    @State private var isOnScreen = false

    /// How far in front this stands: a sheet in front of what it covers, and
    /// a page with a bar of its own in front of the stack or tab it is pushed
    /// onto. Two at the same rank are never on screen together — a page
    /// pushed over another sends the one beneath off screen.
    private var rank: Int { depth * 2 + (aboveBar ? 1 : 0) }

    private var shown: RefreshNotice? {
        guard showing, isOnScreen, let notices, notices.front == rank else { return nil }
        return notices.current
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let notice = shown {
                    RefreshNoticeBanner(notice: notice) { notices?.dismiss(notice) }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.bouncy, value: shown)
            .onAppear {
                isOnScreen = true
                stand()
            }
            .onDisappear {
                isOnScreen = false
                stand()
            }
            .onChange(of: showing) { stand() }
    }

    private func stand() {
        notices?.standing[id] = isOnScreen && showing ? rank : nil
    }
}

/// Liquid Glass, the material of the tab bar it rests above: a pill saying
/// "Updated", or a card saying "Update failed" with the reason beneath it.
private struct RefreshNoticeBanner: View {
    let notice: RefreshNotice
    let dismiss: () -> Void

    private var tint: Color { notice.succeeded ? .brandTint : .favorite }

    var body: some View {
        HStack(alignment: notice.succeeded ? .center : .top, spacing: 8) {
            Image(systemName: notice.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.succeeded ? "Updated" : "Update failed")
                    .font(.system(size: 14, weight: .semibold))
                if let failure = notice.failure {
                    Text(verbatim: failure)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, notice.succeeded ? 10 : 12)
        // A pill for the one word; a rounded card once a reason has to wrap,
        // since a sentence set in a capsule loses its ends to the curve. A
        // failure tints the glass itself, so it reads as one before a word of
        // it is read.
        .glassBackground(in: notice.succeeded
                             ? AnyShape(.capsule)
                             : AnyShape(.rect(cornerRadius: 22, style: .continuous)),
                         interactive: true,
                         tint: notice.succeeded ? nil : Color.favorite.opacity(0.2))
        .contentShape(.rect)
        // Out of the way the moment the reader wants it gone.
        .onTapGesture(perform: dismiss)
        // Felt on a device as it arrives, for a reader who has looked away.
        .sensoryFeedback(notice.succeeded ? .success : .error, trigger: notice.id)
        .accessibilityElement(children: .combine)
    }
}
