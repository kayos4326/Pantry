import Foundation
import OSLog
import SwiftData

/// A recently opened recipe that can be shown again without a network request.
@Model
final class RecentRecipe: StoredPhoto {
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

    static let limit = 12
    private static let logger = Logger(subsystem: "com.pantry.app.Pantry", category: "RecentRecipes")

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

    var gridThumbnailURL: URL? {
        thumbnailURL?.appendingPathComponent("preview")
    }

    /// Recent items only need the smaller image used in the browse strip.
    var photoURL: URL? { gridThumbnailURL }

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

    /// Adds or updates a visit, then trims the oldest items.
    @MainActor
    @discardableResult
    static func record(_ meal: Meal, in context: ModelContext, limit: Int = limit) -> RecentRecipe {
        let id = meal.id
        let existing: RecentRecipe?
        do {
            existing = try context.fetch(
                FetchDescriptor<RecentRecipe>(predicate: #Predicate { $0.mealID == id })
            ).first
        } catch {
            logger.error("Could not look up recent recipe \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            existing = nil
        }

        let recent: RecentRecipe
        if let existing {
            existing.viewedAt = .now
            // Fill missing details without replacing useful data with nil values.
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
        do {
            try context.delete(model: RecentRecipe.self)
        } catch {
            logger.error("Could not clear recent recipes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func trim(to limit: Int, in context: ModelContext) {
        let descriptor = FetchDescriptor<RecentRecipe>(
            sortBy: [SortDescriptor(\.viewedAt, order: .reverse)]
        )
        let all: [RecentRecipe]
        do {
            all = try context.fetch(descriptor)
        } catch {
            logger.error("Could not trim recent recipes: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard all.count > limit else { return }
        for stale in all.dropFirst(limit) {
            context.delete(stale)
        }
    }
}
