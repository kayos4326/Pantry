import Foundation

/// Shows whether a date has a meal, prep work, or both.
struct DayMarker: Equatable {
    var hasMeal = false
    var hasPrep = false

    static let none = DayMarker()
}

enum PrepStatus: Equatable {
    case notNeeded
    case upcoming(start: Date)
    case startsToday
    case overdue(shouldHaveStarted: Date)
    case mealInPast
}

/// Date calculations for make-ahead reminders.
enum PrepSchedule {
    static func prepStartDate(mealDate: Date, leadDays: Int, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: mealDate)
        return calendar.date(byAdding: .day, value: -leadDays, to: day) ?? day
    }

    static func status(
        mealDate: Date,
        leadDays: Int?,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> PrepStatus {
        guard let leadDays, leadDays > 0 else { return .notNeeded }

        let todayStart = calendar.startOfDay(for: today)
        let mealDay = calendar.startOfDay(for: mealDate)
        if mealDay < todayStart { return .mealInPast }

        let start = prepStartDate(mealDate: mealDay, leadDays: leadDays, calendar: calendar)
        if calendar.isDate(start, inSameDayAs: todayStart) { return .startsToday }
        if start < todayStart { return .overdue(shouldHaveStarted: start) }
        return .upcoming(start: start)
    }

    /// Uses relative labels only while the user is viewing today.
    static func mealDateLabel(
        mealDate: Date,
        viewing selectedDate: Date,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let absolute = mealDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let todayStart = calendar.startOfDay(for: today)
        guard calendar.isDate(selectedDate, inSameDayAs: todayStart) else { return absolute }

        let mealDay = calendar.startOfDay(for: mealDate)
        switch calendar.dateComponents([.day], from: todayStart, to: mealDay).day {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default: return absolute
        }
    }

    /// Builds all calendar markers in one pass.
    static func markers(
        plans: [(date: Date, leadDays: Int?)],
        calendar: Calendar = .current
    ) -> [Date: DayMarker] {
        var result: [Date: DayMarker] = [:]
        for plan in plans {
            let mealDay = calendar.startOfDay(for: plan.date)
            result[mealDay, default: .none].hasMeal = true

            if let lead = plan.leadDays, lead > 0 {
                let start = prepStartDate(mealDate: mealDay, leadDays: lead, calendar: calendar)
                result[start, default: .none].hasPrep = true
            }
        }
        return result
    }
}
