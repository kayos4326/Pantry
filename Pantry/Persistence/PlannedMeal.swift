import Foundation
import SwiftData

/// Links a saved recipe to a date in the meal planner.
@Model
final class PlannedMeal {
    /// Stored at midnight so plans can be compared by day.
    var date: Date = Date()
    var recipe: SavedRecipe?
    var plannedAt: Date = Date()

    init(date: Date, recipe: SavedRecipe?, plannedAt: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
        self.recipe = recipe
        self.plannedAt = plannedAt
    }

    var prepStartDate: Date {
        guard let requiredLeadDays else { return date }
        return PrepSchedule.prepStartDate(mealDate: date, leadDays: requiredLeadDays)
    }

    /// Optional make-ahead suggestions do not create prep reminders.
    var requiredLeadDays: Int? {
        guard let makeAhead = recipe?.asMeal.timing.makeAhead, !makeAhead.isOptional else { return nil }
        return makeAhead.leadDays
    }
}
