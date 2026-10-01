import Foundation
import Testing
@testable import Eventrail

struct FollowingFilterTests {
    private func event(inDays days: Int) -> Event {
        Fixtures.event(date: Fixtures.day(fromToday: days))
    }

    /// The next seven days are today and the six after it, counted in written
    /// dates rather than hours.
    @Test func aWeekIsTodayAndTheSixDaysAfter() {
        let week = FollowingFilter.Window.week
        #expect(week.contains(event(inDays: 0)))
        #expect(week.contains(event(inDays: 6)))
        #expect(!week.contains(event(inDays: 7)))
    }

    @Test func thirtyDaysStopsAtTheThirtieth() {
        let month = FollowingFilter.Window.month
        #expect(month.contains(event(inDays: 29)))
        #expect(!month.contains(event(inDays: 30)))
    }

    /// Months as the calendar has them, so the window ends on the same date
    /// three months on, whatever the months' lengths.
    @Test func monthsEndOnTheSameDateMonthsOn() {
        let reader = Calendar.current
        let today = reader.startOfDay(for: .now)
        let end = reader.date(byAdding: .month, value: 3, to: today)!
        let lastDay = reader.dateComponents([.day], from: today, to: end).day! - 1
        #expect(FollowingFilter.Window.threeMonths.contains(event(inDays: lastDay)))
        #expect(!FollowingFilter.Window.threeMonths.contains(event(inDays: lastDay + 1)))
    }

    @Test func allReachesAsFarAsAnythingIsPublished() {
        #expect(FollowingFilter.Window.any.contains(event(inDays: 900)))
        #expect(!FollowingFilter().isNarrowing)
    }

    /// A window alone narrows the list without holding it to any area — so it
    /// sends nobody off to place halls.
    @Test func aWindowAloneHoldsNoArea() {
        let filter = FollowingFilter(window: .week)
        #expect(filter.isNarrowing)
        #expect(!filter.holdsAreas)
        #expect(filter.matches(event(inDays: 2), in: nil))
        #expect(!filter.matches(event(inDays: 40), in: .kanto))
    }

    @Test func theWindowAndTheAreasMustBothAgree() {
        let filter = FollowingFilter(window: .month, areas: [.kansai])
        #expect(filter.matches(event(inDays: 3), in: .kansai))
        #expect(!filter.matches(event(inDays: 3), in: .kanto))
        #expect(!filter.matches(event(inDays: 3), in: nil))
        #expect(!filter.matches(event(inDays: 45), in: .kansai))
    }
}
