import Foundation
import SwiftData

/// A recipe the user has favorited. Stores a full copy of the recipe data so
/// the Saved tab and Meal Planner work with no network connection.
@Model
final class SavedRecipe: StoredPhoto {
    /// Prevents the same meal being favorited twice.
    #Unique<SavedRecipe>([\.mealID])

    var mealID: String = ""
    var name: String = ""
    var thumbnailURLString: String?
    var category: String?
    var area: String?
    var instructions: String?
    var ingredients: [Ingredient] = []
    var savedAt: Date = Date()
    /// The photo itself, so the Saved tab and planner keep their images with
    /// no connection. TheMealDB sends no cache headers, so URLCache alone
    /// can't be relied on for that. Kept outside the SQLite file.
    @Attribute(.externalStorage) var imageData: Data?

    /// Deleting a saved recipe removes any day it was planned for, so the
    /// planner falls back to its empty state instead of holding a dead reference.
    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.recipe)
    var plannedMeals: [PlannedMeal] = []

    /// How many *days* the recipe appears on, which is what the unsave warning
    /// talks about. A day can hold it more than once.
    var plannedDayCount: Int {
        Set(plannedMeals.map(\.date)).count
    }

    init(
        mealID: String,
        name: String,
        thumbnailURLString: String?,
        category: String?,
        area: String?,
        instructions: String?,
        ingredients: [Ingredient],
        savedAt: Date = Date()
    ) {
        self.mealID = mealID
        self.name = name
        self.thumbnailURLString = thumbnailURLString
        self.category = category
        self.area = area
        self.instructions = instructions
        self.ingredients = ingredients
        self.savedAt = savedAt
    }

    convenience init(meal: Meal) {
        self.init(
            mealID: meal.id,
            name: meal.name,
            thumbnailURLString: meal.thumbnailURL?.absoluteString,
            category: meal.category,
            area: meal.area,
            instructions: meal.instructions,
            ingredients: meal.ingredients
        )
    }

    var thumbnailURL: URL? {
        guard let thumbnailURLString else { return nil }
        return URL(string: thumbnailURLString)
    }

    /// Smaller image variant, for grid cards and planner rows.
    var gridThumbnailURL: URL? {
        thumbnailURL?.appendingPathComponent("preview")
    }

    /// The full photo: a saved recipe also fills the detail screen's hero.
    var photoURL: URL? { thumbnailURL }

    /// Lets the Detail screen render a saved recipe offline using the same
    /// view it uses for API results.
    var asMeal: Meal {
        Meal(
            id: mealID,
            name: name,
            thumbnailURL: thumbnailURL,
            category: category,
            area: area,
            instructions: instructions,
            ingredients: ingredients
        )
    }
}
