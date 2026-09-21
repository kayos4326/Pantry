import Foundation
import SwiftData

/// A favourite recipe stored for offline use and meal planning.
@Model
final class SavedRecipe: StoredPhoto {
    #Unique<SavedRecipe>([\.mealID])

    var mealID: String = ""
    var name: String = ""
    var thumbnailURLString: String?
    var category: String?
    var area: String?
    var instructions: String?
    var ingredients: [Ingredient] = []
    var savedAt: Date = Date()
    @Attribute(.externalStorage) var imageData: Data?

    /// Removing a favourite also removes its meal-plan entries.
    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.recipe)
    var plannedMeals: [PlannedMeal] = []

    /// Counts unique dates because a recipe may appear more than once in one day.
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

    var gridThumbnailURL: URL? {
        thumbnailURL?.appendingPathComponent("preview")
    }

    var photoURL: URL? { thumbnailURL }

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
