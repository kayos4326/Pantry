import Foundation
import Testing
@testable import Pantry

/// Every suite that drives the shared URL stub is nested here so they never
/// run concurrently with one another.
@Suite("Network-backed", .serialized)
struct NetworkBacked {}

extension NetworkBacked {
    @Suite("NetworkManager")
    struct NetworkManagerTests {
        @Test("Search decodes meals and builds ingredients")
        func searchDecodes() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([Fixtures.fullMealJSON()]))
            }

            let meals = try await network.searchMeals(named: "chicken")

            let meal = try #require(meals.first)
            #expect(meal.id == "52795")
            #expect(meal.name == "Chicken Handi")
            #expect(meal.category == "Chicken")
            #expect(meal.area == "Indian")
            #expect(meal.tagList == ["Spicy", "Curry"])
            #expect(meal.youtubeURL == nil)
            #expect(meal.thumbnailURL?.absoluteString == "https://www.themealdb.com/images/media/meals/wyxwsp1486979827.jpg")
        }

        @Test("Search sends the query as the s parameter, percent-encoded")
        func searchQueryEncoding() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([Fixtures.fullMealJSON()]))
            }

            _ = try await network.searchMeals(named: "Apple & Blackberry Æbleskiver")

            let request = try #require(StubURLProtocol.requests.first)
            #expect(request.url?.path.hasSuffix("/search.php") == true)
            #expect(request.queryValue("s") == "Apple & Blackberry Æbleskiver")
            // "&" must be escaped or the server would split it into two parameters.
            #expect(request.url?.absoluteString.contains("%26") == true)
        }

        @Test("null meals becomes emptyResults, not a crash or an empty list")
        func nullMealsIsEmptyResults() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json(Fixtures.emptyMeals) }

            await #expect(throws: NetworkError.emptyResults) {
                try await network.searchMeals(named: "zzzz")
            }
        }

        @Test("Filter hits filter.php with the category and tolerates partial meals")
        func filterPartialMeals() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([
                    Fixtures.filterMealJSON(id: "1", name: "Pie"),
                    Fixtures.filterMealJSON(id: "2", name: "Stew")
                ]))
            }

            let meals = try await network.filterMeals(byCategory: "Beef")

            #expect(meals.map(\.name) == ["Pie", "Stew"])
            #expect(StubURLProtocol.requests.first?.queryValue("c") == "Beef")
            #expect(meals.allSatisfy { !$0.isFullyLoaded })
            #expect(meals.first?.category == nil)
        }

        @Test("Categories decode in order")
        func categoriesDecode() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in .json(Fixtures.categories) }

            let categories = try await network.fetchCategories()

            #expect(categories.map(\.name) == ["Beef", "Chicken"])
            #expect(categories.first?.id == "1")
        }

        @Test("Lookup returns the single meal and sends the id")
        func lookupReturnsMeal() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([Fixtures.fullMealJSON(id: "53120", name: "Æbleskiver")]))
            }

            let meal = try await network.lookupMeal(id: "53120")

            #expect(meal.name == "Æbleskiver")
            #expect(StubURLProtocol.requests.first?.queryValue("i") == "53120")
        }

        @Test("Lookup of an unknown id is emptyResults")
        func lookupUnknownId() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json(Fixtures.emptyMeals) }

            await #expect(throws: NetworkError.emptyResults) {
                try await network.lookupMeal(id: "0")
            }
        }

        @Test("Non-2xx status becomes badResponse with the code", arguments: [404, 500, 503])
        func badStatus(code: Int) async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json("{}", status: code) }

            await #expect(throws: NetworkError.badResponse(statusCode: code)) {
                try await network.fetchCategories()
            }
        }

        @Test("Malformed JSON becomes decodingFailed")
        func malformedJSON() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json("<html>Service Unavailable</html>") }

            await #expect(throws: NetworkError.decodingFailed) {
                try await network.searchMeals(named: "x")
            }
        }

        @Test(
            "Connectivity failures become noConnection",
            arguments: [
                URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed
            ]
        )
        func connectivityFailures(code: URLError.Code) async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(code) }

            await #expect(throws: NetworkError.noConnection) {
                try await network.searchMeals(named: "x")
            }
        }

        @Test("A cancelled request surfaces as CancellationError so the UI ignores it")
        func cancellation() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.cancelled) }

            await #expect(throws: CancellationError.self) {
                try await network.searchMeals(named: "x")
            }
        }

        @Test("Other URL errors keep their description")
        func otherURLError() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.badServerResponse) }

            do {
                _ = try await network.searchMeals(named: "x")
                Issue.record("Expected an error")
            } catch let error as NetworkError {
                guard case .unknown(let message) = error else {
                    Issue.record("Expected .unknown, got \(error)")
                    return
                }
                #expect(!message.isEmpty)
            }
        }

        @Test("Requests use a 15 second timeout instead of URLSession's 60")
        func requestTimeout() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in .json(Fixtures.categories) }

            _ = try await network.fetchCategories()

            #expect(StubURLProtocol.requests.first?.timeoutInterval == 15)
        }

        @Test("Image download returns bytes, and an empty body is an error")
        func imageData() async throws {
            let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
            let network = StubURLProtocol.makeNetworkManager { _ in .data(bytes) }
            #expect(try await network.imageData(from: URL(string: "https://example.com/a.jpg")!) == bytes)

            let empty = StubURLProtocol.makeNetworkManager { _ in .data(Data()) }
            await #expect(throws: NetworkError.emptyResults) {
                try await empty.imageData(from: URL(string: "https://example.com/a.jpg")!)
            }
        }

        // MARK: - Offline copies

        @Test("A successful response is kept, so the same request works offline")
        func successIsCached() async throws {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                online ? .json(Fixtures.mealsResponse([Fixtures.fullMealJSON()])) : .failure(.notConnectedToInternet)
            }
            _ = try await network.searchMeals(named: "chicken")

            online = false
            await #expect(throws: NetworkError.noConnection) {
                try await network.searchMeals(named: "chicken")
            }

            let cached = try #require(await network.cachedMeals(search: "chicken"))
            #expect(cached.value.map(\.name) == ["Chicken Handi"])
            // Ingredients survive the round trip, so the copy is as complete
            // as what was on screen.
            #expect(cached.value.first?.ingredients.map(\.name) == ["Chicken", "Onion", "Garlic"])
            #expect(abs(cached.storedAt.timeIntervalSinceNow) < 10)
        }

        @Test("Each request has its own copy, and an unrequested one has none")
        func cachePerRequest() async throws {
            let cache = StubURLProtocol.makeCache()
            let network = StubURLProtocol.makeNetworkManager(cache: cache) { request in
                request.url!.path.hasSuffix("filter.php")
                    ? .json(Fixtures.mealsResponse([Fixtures.filterMealJSON(id: "9", name: "Beef Pie")]))
                    : .json(Fixtures.mealsResponse([Fixtures.fullMealJSON()]))
            }

            _ = try await network.searchMeals(named: "chicken")
            _ = try await network.filterMeals(byCategory: "Beef")

            #expect(await network.cachedMeals(category: "Beef")?.value.map(\.name) == ["Beef Pie"])
            #expect(await network.cachedMeals(search: "chicken")?.value.map(\.name) == ["Chicken Handi"])
            #expect(await network.cachedMeals(search: "beef") == nil, "a search never made has no copy")
            #expect(await network.cachedMeals(category: "Dessert") == nil)
        }

        @Test("The default feed and an empty search share one copy")
        func defaultFeedCached() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([Fixtures.fullMealJSON()]))
            }

            _ = try await network.searchMeals(named: "")

            #expect(await network.cachedMeals(search: "")?.value.count == 1)
        }

        @Test("Categories and single recipes are kept too")
        func categoriesAndLookupCached() async throws {
            let cache = StubURLProtocol.makeCache()
            let network = StubURLProtocol.makeNetworkManager(cache: cache) { request in
                request.url!.path.hasSuffix("categories.php")
                    ? .json(Fixtures.categories)
                    : .json(Fixtures.mealsResponse([Fixtures.fullMealJSON(id: "53120", name: "Æbleskiver")]))
            }

            _ = try await network.fetchCategories()
            _ = try await network.lookupMeal(id: "53120")

            #expect(await network.cachedCategories()?.value.map(\.name) == ["Beef", "Chicken"])
            let meal = try #require(await network.cachedMeal(id: "53120"))
            #expect(meal.value.name == "Æbleskiver")
            #expect(meal.value.isFullyLoaded, "a cached recipe has to be complete enough to open")
            #expect(await network.cachedMeal(id: "99999") == nil)
        }

        @Test("A response that couldn't be decoded is never kept")
        func decodeFailureNotCached() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json("<html>Down for maintenance</html>") }

            await #expect(throws: NetworkError.decodingFailed) {
                try await network.searchMeals(named: "chicken")
            }

            #expect(await network.cachedMeals(search: "chicken") == nil)
        }

        @Test("A failed refresh leaves the previous copy intact")
        func failureKeepsPreviousCopy() async throws {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                online ? .json(Fixtures.mealsResponse([Fixtures.fullMealJSON()])) : .json("{}", status: 500)
            }
            _ = try await network.searchMeals(named: "chicken")

            online = false
            await #expect(throws: NetworkError.badResponse(statusCode: 500)) {
                try await network.searchMeals(named: "chicken")
            }

            #expect(await network.cachedMeals(search: "chicken")?.value.map(\.name) == ["Chicken Handi"])
        }

        @Test("An empty result isn't offered as an offline copy")
        func emptyResultNotOffered() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json(Fixtures.emptyMeals) }

            await #expect(throws: NetworkError.emptyResults) {
                try await network.searchMeals(named: "zzzz")
            }

            #expect(await network.cachedMeals(search: "zzzz") == nil)
        }

        @Test("Every error has a user-facing message")
        func errorMessages() {
            let errors: [NetworkError] = [
                .noConnection, .badResponse(statusCode: 500), .emptyResults,
                .decodingFailed, .invalidURL, .unknown("Something")
            ]
            for error in errors {
                #expect(!(error.errorDescription ?? "").isEmpty)
            }
            #expect(NetworkError.badResponse(statusCode: 503).errorDescription?.contains("503") == true)
        }
    }
}
