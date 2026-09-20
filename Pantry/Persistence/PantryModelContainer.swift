import Foundation
import OSLog
import SwiftData

enum PantryModelContainer {
    static let schema = Schema([SavedRecipe.self, PlannedMeal.self, RecentRecipe.self])
    private static let logger = Logger(subsystem: "com.pantry.app.Pantry", category: "Persistence")

    /// Opens the app's store without ever deleting or replacing it on failure.
    /// The caller decides how to present an unavailable store to the user.
    static func makeShared() -> Result<ModelContainer, Error> {
        // UI tests launch with this flag so they start empty and never read or
        // overwrite the recipes and plans saved on the device.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        let result = make(configuration: configuration)
        if case .failure(let error) = result {
            logger.error("Failed to open the persistent store: \(error.localizedDescription)")
        }
        return result
    }

    /// Kept separate so the failure path can be tested with an unavailable
    /// location. Returning the error preserves the original store and avoids
    /// silently switching to an in-memory database that would lose new saves.
    static func make(configuration: ModelConfiguration) -> Result<ModelContainer, Error> {
        Result {
            try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    /// In-memory container seeded with sample data, for SwiftUI previews.
    @MainActor
    static let preview: ModelContainer = {
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )

        let sample = SavedRecipe(
            mealID: "52795",
            name: "Chicken Handi",
            thumbnailURLString: "https://www.themealdb.com/images/media/meals/wyxwsp1486979827.jpg",
            category: "Chicken",
            area: "Indian",
            instructions: "Marinate the chicken overnight in yoghurt.\nHeat oil in a pan.\nAdd the onions and fry until golden.",
            ingredients: [
                Ingredient(id: 1, name: "Chicken", measure: "1.2 kg"),
                Ingredient(id: 2, name: "Onion", measure: "5 thinly sliced"),
                Ingredient(id: 3, name: "Tomatoes", measure: "2 finely chopped")
            ]
        )
        container.mainContext.insert(sample)

        let inThreeDays = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
        container.mainContext.insert(PlannedMeal(date: inThreeDays, recipe: sample))

        container.mainContext.insert(RecentRecipe(
            mealID: "52874",
            name: "Beef and Mustard Pie",
            thumbnailURLString: "https://www.themealdb.com/images/media/meals/sytuqu1511553755.jpg",
            category: "Beef"
        ))

        return container
    }()
}
