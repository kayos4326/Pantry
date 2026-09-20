import Foundation
import SwiftData

/// Assigns one saved recipe to one calendar date. A row exists only for meals
/// actually planned, so "no rows for the 16th" is the empty state.
///
/// A date can carry several of these — a day's meals are a list, in the order
/// they were added, rather than a single slot.
@Model
final class PlannedMeal {
    /// Always normalised to midnight so date equality is reliable.
    var date: Date = Date()
    var recipe: SavedRecipe?
    /// Orders the meals within a day: first added, first shown.
    var plannedAt: Date = Date()

    init(date: Date, recipe: SavedRecipe?, plannedAt: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
        self.recipe = recipe
        self.plannedAt = plannedAt
    }

    /// The date prep has to begin, once any marinating or chilling is taken
    /// into account. Same as `date` when the recipe needs no head start.
    var prepStartDate: Date {
        guard let requiredLeadDays else { return date }
        return PrepSchedule.prepStartDate(mealDate: date, leadDays: requiredLeadDays)
    }

    /// Days of head start the recipe *requires*. An optional head start
    /// ("can be made a day ahead") doesn't schedule prep on the calendar.
    var requiredLeadDays: Int? {
        guard let makeAhead = recipe?.asMeal.timing.makeAhead, !makeAhead.isOptional else { return nil }
        return makeAhead.leadDays
    }
}
