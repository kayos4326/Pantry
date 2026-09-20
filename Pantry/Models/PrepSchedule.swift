import Foundation

/// Markers under a date in the planner strip. A day can carry both: a meal of
/// its own and prep for a later one.
struct DayMarker: Equatable {
    /// A meal is planned for this date.
    var hasMeal = false
    /// Prep for a later meal has to begin on this date.
    var hasPrep = false

    static let none = DayMarker()
}

/// Where a planned meal stands relative to today, given its make-ahead lead.
enum PrepStatus: Equatable {
    /// The recipe needs no head start.
    case notNeeded
    /// Prep begins on a future date.
    case upcoming(start: Date)
    case startsToday
    /// The prep window opened before today but the meal hasn't happened yet.
    case overdue(shouldHaveStarted: Date)
    /// The meal itself is in the past, so there's nothing left to warn about.
    case mealInPast
}

/// Pure date arithmetic for make-ahead planning, kept out of the views so it
/// can be tested with a fixed calendar and a fixed "today".
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

    /// How to word the date of the meal a prep task belongs to, under the day
    /// being viewed.
    ///
    /// "Tomorrow" only means anything while that day is today. Looking back at
    /// Tuesday on a Thursday, a Wednesday meal is the day *after* the one on
    /// screen, but "yesterday" from now — and reading "prep due, for yesterday"
    /// suggests prep for a meal that has already happened. Any other day than
    /// today therefore gets the date itself.
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
        // Counted rather than asked of the calendar, so "today" stays injectable.
        switch calendar.dateComponents([.day], from: todayStart, to: mealDay).day {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default: return absolute
        }
    }

    /// Markers for every date in one pass, rather than re-scanning all plans
    /// once per date.
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
