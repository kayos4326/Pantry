import Foundation
import Testing
@testable import Pantry

@Suite("Prep schedule")
struct PrepScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func status(meal: Date, lead: Int?, today: Date) -> PrepStatus {
        PrepSchedule.status(mealDate: meal, leadDays: lead, today: today, calendar: calendar)
    }

    @Test("Prep start is the meal date minus the lead, at midnight")
    func prepStart() {
        let start = PrepSchedule.prepStartDate(mealDate: day(9, 14, hour: 19), leadDays: 2, calendar: calendar)
        #expect(start == calendar.startOfDay(for: day(9, 12)))
    }

    @Test("Prep start crosses a month boundary")
    func monthBoundary() {
        let start = PrepSchedule.prepStartDate(mealDate: day(10, 1), leadDays: 2, calendar: calendar)
        #expect(start == calendar.startOfDay(for: day(9, 29)))
    }

    @Test("No lead means no prep")
    func notNeeded() {
        #expect(status(meal: day(9, 20), lead: nil, today: day(9, 13)) == .notNeeded)
        #expect(status(meal: day(9, 20), lead: 0, today: day(9, 13)) == .notNeeded)
    }

    @Test("A future start is upcoming")
    func upcoming() {
        #expect(status(meal: day(9, 20), lead: 1, today: day(9, 13)) ==
                .upcoming(start: calendar.startOfDay(for: day(9, 19))))
    }

    @Test("Starting today is flagged as today, whatever the time of day")
    func startsToday() {
        #expect(status(meal: day(9, 14), lead: 1, today: day(9, 13, hour: 0)) == .startsToday)
        #expect(status(meal: day(9, 14), lead: 1, today: day(9, 13, hour: 23)) == .startsToday)
    }

    @Test("Planning a marinated dish for today or tomorrow without enough lead is overdue")
    func overdue() {
        #expect(status(meal: day(9, 13), lead: 1, today: day(9, 13)) ==
                .overdue(shouldHaveStarted: calendar.startOfDay(for: day(9, 12))))
        #expect(status(meal: day(9, 14), lead: 2, today: day(9, 13)) ==
                .overdue(shouldHaveStarted: calendar.startOfDay(for: day(9, 12))))
    }

    @Test("Meals already in the past don't raise warnings")
    func mealInPast() {
        #expect(status(meal: day(9, 10), lead: 2, today: day(9, 13)) == .mealInPast)
    }

    // MARK: - Wording of the meal a prep task belongs to

    private func label(meal: Date, viewing: Date, today: Date) -> String {
        PrepSchedule.mealDateLabel(mealDate: meal, viewing: viewing, today: today, calendar: calendar)
    }

    @Test("While viewing today, the meal's date is worded relative to now")
    func labelRelativeWhileViewingToday() {
        let today = day(9, 17)
        #expect(label(meal: day(9, 18), viewing: today, today: today) == "tomorrow")
        #expect(label(meal: day(9, 17), viewing: today, today: today) == "today")
        // Use the date when a relative label would be unclear.
        #expect(label(meal: day(9, 20), viewing: today, today: today).contains("20"))
    }

    @Test("Viewing another day never words the meal relative to now")
    func labelAbsoluteWhileViewingAnotherDay() {
        // Relative labels are based on today, not the selected planner date.
        let wording = label(meal: day(9, 16), viewing: day(9, 15), today: day(9, 17))
        #expect(wording.contains("16"))
        #expect(!["today", "tomorrow", "yesterday"].contains(wording))

        let future = label(meal: day(9, 25), viewing: day(9, 24), today: day(9, 17))
        #expect(future.contains("25"))
        #expect(!["today", "tomorrow", "yesterday"].contains(future))
    }

    @Test("The time of day never changes the wording")
    func labelIgnoresTimeOfDay() {
        let today = day(9, 17, hour: 23)
        #expect(label(meal: day(9, 18, hour: 1), viewing: day(9, 17, hour: 0), today: today) == "tomorrow")
    }

    @Test("Markers flag meal days and prep days, including both on one day")
    func markers() {
        let map = PrepSchedule.markers(
            plans: [
                (date: day(9, 14), leadDays: 1),   // prep on the 13th
                (date: day(9, 13), leadDays: nil), // the 13th also has its own meal
                (date: day(9, 20), leadDays: 2)    // prep on the 18th
            ],
            calendar: calendar
        )

        #expect(map[calendar.startOfDay(for: day(9, 13))] == DayMarker(hasMeal: true, hasPrep: true))
        #expect(map[calendar.startOfDay(for: day(9, 14))] == DayMarker(hasMeal: true, hasPrep: false))
        #expect(map[calendar.startOfDay(for: day(9, 18))] == DayMarker(hasMeal: false, hasPrep: true))
        #expect(map[calendar.startOfDay(for: day(9, 19))] == nil)
    }
}
