import Foundation
import Testing
@testable import Pantry

@Suite("Meal decoding")
struct MealDecodingTests {
    private func decode(_ json: String) throws -> [Meal] {
        try JSONDecoder().decode(MealResponse.self, from: Data(json.utf8)).meals ?? []
    }

    @Test("Ingredients skip empty, whitespace-only and null slots")
    func ingredientSlots() throws {
        let meal = try #require(try decode(Fixtures.mealsResponse([Fixtures.fullMealJSON()])).first)

        #expect(meal.ingredients.map(\.name) == ["Chicken", "Onion", "Garlic"])
        #expect(meal.ingredients.map(\.id) == [1, 2, 6])
    }

    @Test("Names and measures are trimmed; lowercase names are capitalised")
    func trimmingAndCapitalisation() throws {
        let meal = try #require(try decode(Fixtures.mealsResponse([Fixtures.fullMealJSON()])).first)
        let onion = try #require(meal.ingredients.first { $0.id == 2 })

        #expect(onion.name == "Onion")
        #expect(onion.measure == "5 sliced")
    }

    @Test("A missing measure becomes an empty string, not nil text")
    func missingMeasure() throws {
        let meal = try #require(try decode(Fixtures.mealsResponse([Fixtures.fullMealJSON()])).first)
        #expect(meal.ingredients.last?.measure == "")
    }

    @Test("One malformed thumbnail doesn't fail the whole result list")
    func malformedThumbnail() throws {
        let good = Fixtures.fullMealJSON(id: "1", name: "Good")
        let bad = Fixtures.fullMealJSON(id: "2", name: "Bad", thumb: "")
        let meals = try decode(Fixtures.mealsResponse([good, bad]))

        #expect(meals.map(\.name) == ["Good", "Bad"])
        #expect(meals[1].thumbnailURL == nil)
    }

    @Test("Grid thumbnail uses TheMealDB's small /preview variant")
    func previewURL() throws {
        let meal = try #require(try decode(Fixtures.mealsResponse([Fixtures.fullMealJSON()])).first)
        #expect(meal.gridThumbnailURL?.absoluteString.hasSuffix(".jpg/preview") == true)
    }

    @Test("isFullyLoaded needs both instructions and ingredients")
    func fullyLoaded() {
        #expect(Fixtures.meal().isFullyLoaded)
        #expect(!Fixtures.meal(instructions: nil).isFullyLoaded)
        #expect(!Fixtures.meal(instructions: "").isFullyLoaded)
        #expect(!Fixtures.meal(ingredients: []).isFullyLoaded)
    }

    @Test("Tags split on commas and drop blanks")
    func tags() {
        let meal = Meal(id: "1", name: "x", thumbnailURL: nil, category: nil, area: nil,
                        instructions: nil, tags: " Spicy, ,Curry ,", ingredients: [])
        #expect(meal.tagList == ["Spicy", "Curry"])
    }
}
