import Foundation
import Testing
@testable import Pantry

/// Contract tests against the real TheMealDB. Off by default so normal runs
/// stay offline and deterministic. Enable from the command line with:
///   TEST_RUNNER_PANTRY_LIVE_API=1 xcodebuild test ...
/// or by adding PANTRY_LIVE_API=1 to the scheme's test environment.
@Suite(
    "Live TheMealDB contract",
    .enabled(if: ProcessInfo.processInfo.environment["PANTRY_LIVE_API"] != nil),
    .serialized
)
struct LiveAPITests {
    private let network = NetworkManager.shared

    @Test("Search returns decodable meals with ingredients")
    func search() async throws {
        let meals = try await network.searchMeals(named: "chicken")
        #expect(!meals.isEmpty)
        #expect(meals.contains { !$0.ingredients.isEmpty && $0.isFullyLoaded })
    }

    @Test("Categories include the ones the chips expect")
    func categories() async throws {
        let names = try await network.fetchCategories().map(\.name)
        #expect(names.contains("Beef"))
        #expect(names.contains("Dessert"))
    }

    @Test("Category filter still returns partial meals that need hydrating")
    func filterIsPartial() async throws {
        let meals = try await network.filterMeals(byCategory: "Seafood")
        #expect(!meals.isEmpty)
        #expect(meals.allSatisfy { !$0.isFullyLoaded })
    }

    @Test("Lookup of a known recipe is complete")
    func lookup() async throws {
        let meal = try await network.lookupMeal(id: "52772")
        #expect(meal.isFullyLoaded)
        #expect(!meal.instructionSteps.isEmpty)
    }

    @Test("Nonsense search is emptyResults")
    func nonsense() async {
        await #expect(throws: NetworkError.emptyResults) {
            try await network.searchMeals(named: "zzzznotarealmealzzzz")
        }
    }

    @Test("Æbleskiver's decorative ▢ lines don't become steps")
    func glyphRegression() async throws {
        let meal = try await network.lookupMeal(id: "53120")
        #expect(meal.instructionSteps.count == 6)
        #expect(meal.instructionSteps.allSatisfy { $0.rangeOfCharacter(from: .alphanumerics) != nil })
    }

    @Test("Ayam Percik is still detected as needing a day's marinating")
    func makeAheadRegression() async throws {
        let meals = try await network.searchMeals(named: "Ayam Percik")
        let meal = try #require(meals.first { $0.name == "Ayam Percik" })
        #expect(meal.timing.makeAhead?.leadDays == 1)
        #expect(meal.timing.makeAhead?.isOptional == false)
    }

    @Test("Recipe photos download as real image data")
    func imageDownload() async throws {
        let meal = try await network.lookupMeal(id: "52772")
        let url = try #require(meal.gridThumbnailURL)
        let data = try await network.imageData(from: url)
        #expect(data.count > 1_000)
    }
}
