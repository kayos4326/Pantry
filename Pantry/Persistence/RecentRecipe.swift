import Foundation
import SwiftData

/// A recipe the user has opened, kept so Browse has something of theirs to
/// show the moment the app launches — before, or without, any network call.
///
/// It keeps the whole recipe, not just the card, so a recipe that's been
/// opened once opens again with no connection whether or not it was saved.
@Model
final class RecentRecipe: StoredPhoto {
    /// One row per recipe, however many times it's opened.
    #Unique<RecentRecipe>([\.mealID])

    var mealID: String = ""
    var name: String = ""
    var thumbnailURLString: String?
    var category: String?
    var area: String?
    var instructions: String?
    var ingredients: [Ingredient] = []
    var viewedAt: Date = Date()
    @Attribute(.externalStorage) var imageData: Data?

    /// Enough to fill the strip a few times over without the list becoming a
    /// history nobody scrolls through.
    static let limit = 12

    init(
        mealID: String,
        name: String,
        thumbnailURLString: String?,
        category: String?,
        area: String? = nil,
        instructions: String? = nil,
        ingredients: [Ingredient] = [],
        viewedAt: Date = Date()
    ) {
        self.mealID = mealID
        self.name = name
        self.thumbnailURLString = thumbnailURLString
        self.category = category
        self.area = area
        self.instructions = instructions
        self.ingredients = ingredients
        self.viewedAt = viewedAt
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

    /// Smaller image variant, matching the grid cards.
    var gridThumbnailURL: URL? {
        thumbnailURL?.appendingPathComponent("preview")
    }

    /// Only the ~9 KB preview is kept: a recent recipe is never shown larger
    /// than a thumbnail, and up to a dozen of them are held at once.
    var photoURL: URL? { gridThumbnailURL }

    /// Complete once the recipe has been opened with a connection, which is
    /// what lets the detail screen render it again offline.
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

    /// Records a visit: one row per recipe, moved to the front on a repeat
    /// visit, with the list trimmed to `limit`.
    @MainActor
    @discardableResult
    static func record(_ meal: Meal, in context: ModelContext, limit: Int = limit) -> RecentRecipe {
        let id = meal.id
        let existing = try? context.fetch(
            FetchDescriptor<RecentRecipe>(predicate: #Predicate { $0.mealID == id })
        ).first

        let recent: RecentRecipe
        if let existing {
            existing.viewedAt = .now
            // A visit recorded while offline, or from a category card, can be
            // missing pieces the next visit has, so later visits fill them in
            // rather than overwriting good data with blanks.
            existing.name = meal.name
            if let category = meal.category { existing.category = category }
            if let area = meal.area { existing.area = area }
            if let thumbnail = meal.thumbnailURL?.absoluteString { existing.thumbnailURLString = thumbnail }
            if meal.isFullyLoaded {
                existing.instructions = meal.instructions
                existing.ingredients = meal.ingredients
            }
            recent = existing
        } else {
            recent = RecentRecipe(meal: meal)
            context.insert(recent)
        }

        trim(to: limit, in: context)
        return recent
    }

    static func clear(in context: ModelContext) {
        try? context.delete(model: RecentRecipe.self)
    }

    private static func trim(to limit: Int, in context: ModelContext) {
        let descriptor = FetchDescriptor<RecentRecipe>(
            sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > limit else { return }
        for stale in all.dropFirst(limit) {
            context.delete(stale)
        }
    }
}
