import Foundation
import SwiftData
import Testing
@testable import Pantry

extension NetworkBacked {
    @Suite("BrowseViewModel")
    @MainActor
    struct BrowseViewModelTests {
        private static let feed = Fixtures.mealsResponse([
            Fixtures.fullMealJSON(id: "1", name: "Flan"),
            Fixtures.fullMealJSON(id: "2", name: "Ezme")
        ])

        private func loadedNames(_ vm: BrowseViewModel) -> [String]? {
            if case .loaded(let meals, _) = vm.state { return meals.map(\.name) }
            return nil
        }

        private func offlineCopy(_ vm: BrowseViewModel) -> BrowseViewModel.OfflineCopy? {
            if case .loaded(_, let offline) = vm.state { return offline }
            return nil
        }

        @Test("First load shows the default feed from an empty search")
        func defaultFeed() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .json(Self.feed) }
            let vm = BrowseViewModel(network: network, debounce: .zero)

            #expect(vm.currentRequest == .defaultFeed)
            await vm.loadForCurrentInputs()

            #expect(loadedNames(vm) == ["Flan", "Ezme"])
            #expect(StubURLProtocol.requests.first?.queryValue("s") == "")
        }

        @Test("Typing a search drops the selected category in the same update")
        func searchClearsCategory() {
            let vm = BrowseViewModel(network: StubURLProtocol.makeNetworkManager { _ in .json(Self.feed) })
            vm.select(category: "Dessert")
            #expect(vm.selectedCategory == "Dessert")

            vm.searchText = "pasta"

            #expect(vm.selectedCategory == nil)
            #expect(vm.currentRequest == .search("pasta"))
            #expect(vm.requestKey == "pasta|")
        }

        @Test("Picking a category clears the search")
        func categoryClearsSearch() {
            let vm = BrowseViewModel(network: StubURLProtocol.makeNetworkManager { _ in .json(Self.feed) })
            vm.searchText = "pasta"

            vm.select(category: "Beef")

            #expect(vm.searchText == "")
            #expect(vm.currentRequest == .category("Beef"))
            #expect(vm.requestKey == "|Beef")
        }

        @Test("Tapping the selected chip again, or All, returns to the default feed")
        func deselect() {
            let vm = BrowseViewModel(network: StubURLProtocol.makeNetworkManager { _ in .json(Self.feed) })
            vm.select(category: "Beef")
            vm.select(category: "Beef")
            #expect(vm.selectedCategory == nil)

            vm.select(category: "Beef")
            vm.select(category: nil)
            #expect(vm.currentRequest == .defaultFeed)
        }

        @Test("Whitespace-only search is treated as no search")
        func whitespaceSearch() {
            let vm = BrowseViewModel(network: StubURLProtocol.makeNetworkManager { _ in .json(Self.feed) })
            vm.select(category: "Beef")
            vm.searchText = "   "
            #expect(vm.selectedCategory == "Beef")
            #expect(vm.currentRequest == .category("Beef"))
        }

        @Test("Category browsing uses filter.php")
        func categoryLoad() async {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([Fixtures.filterMealJSON(id: "9", name: "Beef Pie")]))
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            vm.select(category: "Beef")

            await vm.loadForCurrentInputs()

            #expect(loadedNames(vm) == ["Beef Pie"])
            #expect(StubURLProtocol.requests.last?.url?.path.hasSuffix("/filter.php") == true)
        }

        @Test("No results shows an empty state naming what was searched")
        func emptyState() async {
            let vm = BrowseViewModel(
                network: StubURLProtocol.makeNetworkManager { _ in .json(Fixtures.emptyMeals) },
                debounce: .zero
            )
            vm.searchText = "zzzz"

            await vm.loadForCurrentInputs()

            guard case .empty(let message) = vm.state else {
                Issue.record("Expected empty state, got \(vm.state)")
                return
            }
            #expect(message.contains("zzzz"))
        }

        @Test("Offline with nothing cached shows an error, and retry recovers — chips included")
        func failureAndRetry() async {
            var online = false
            let network = StubURLProtocol.makeNetworkManager { request in
                guard online else { return .failure(.notConnectedToInternet) }
                return request.url!.path.hasSuffix("categories.php") ? .json(Fixtures.categories) : .json(Self.feed)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)

            await vm.loadCategories()
            await vm.loadForCurrentInputs()
            guard case .failed(let message) = vm.state else {
                Issue.record("Expected failure, got \(vm.state)")
                return
            }
            #expect(message == NetworkError.noConnection.errorDescription)
            #expect(vm.categories.isEmpty)

            online = true
            await vm.retry()

            #expect(loadedNames(vm) == ["Flan", "Ezme"])
            #expect(vm.categories.map(\.name) == ["Beef", "Chicken"])
        }

        @Test("A slow retry can't overwrite a category picked after it")
        func staleResponseIgnored() async throws {
            let network = StubURLProtocol.makeNetworkManager { request in
                let path = request.url!.path
                if path.hasSuffix("filter.php") {
                    return .json(Fixtures.mealsResponse([Fixtures.filterMealJSON(id: "9", name: "Beef Pie")]))
                }
                if path.hasSuffix("categories.php") { return .json(Fixtures.categories) }
                return .json(Self.feed, delay: .milliseconds(500))
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)

            async let slowRetry: Void = vm.retry()
            try await Task.sleep(for: .milliseconds(80))
            vm.select(category: "Beef")
            await vm.loadForCurrentInputs()
            await slowRetry

            #expect(loadedNames(vm) == ["Beef Pie"])
        }

        // MARK: - Offline

        @Test("Offline falls back to the last results for the same request, marked as offline")
        func offlineFallback() async {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                online ? .json(Self.feed) : .failure(.notConnectedToInternet)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            await vm.loadForCurrentInputs()
            #expect(offlineCopy(vm) == nil, "a live load is not an offline one")

            online = false
            await vm.refresh()

            #expect(loadedNames(vm) == ["Flan", "Ezme"])
            let offline = offlineCopy(vm)
            #expect(offline?.isDisconnected == true)
            #expect(abs(offline?.storedAt.timeIntervalSinceNow ?? .infinity) < 10)
        }

        @Test("A category browsed before is still browsable offline")
        func offlineCategory() async {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { request in
                guard online else { return .failure(.notConnectedToInternet) }
                return request.url!.path.hasSuffix("filter.php")
                    ? .json(Fixtures.mealsResponse([Fixtures.filterMealJSON(id: "9", name: "Beef Pie")]))
                    : .json(Self.feed)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            vm.select(category: "Beef")
            await vm.loadForCurrentInputs()

            online = false
            await vm.retry()

            #expect(loadedNames(vm) == ["Beef Pie"])
            #expect(offlineCopy(vm) != nil)
        }

        @Test("A server error falls back too, but doesn't claim the user is offline")
        func serverErrorFallback() async {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                online ? .json(Self.feed) : .json("{}", status: 500)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            await vm.loadForCurrentInputs()

            online = false
            await vm.refresh()

            #expect(loadedNames(vm) == ["Flan", "Ezme"])
            #expect(offlineCopy(vm)?.isDisconnected == false)
        }

        @Test("A genuine no-match answer shows the empty state, never stale results")
        func emptyResultBeatsCache() async {
            var hasResults = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                hasResults ? .json(Self.feed) : .json(Fixtures.emptyMeals)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            await vm.loadForCurrentInputs()
            #expect(loadedNames(vm) != nil)

            hasResults = false
            await vm.refresh()

            guard case .empty = vm.state else {
                Issue.record("Expected the empty state, got \(vm.state)")
                return
            }
        }

        @Test("Nothing cached for this request still shows the error, not another request's results")
        func noCopyForThisRequest() async {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                online ? .json(Self.feed) : .failure(.notConnectedToInternet)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            await vm.loadForCurrentInputs()

            online = false
            vm.searchText = "pierogi"
            await vm.loadForCurrentInputs()

            guard case .failed = vm.state else {
                Issue.record("Expected a failure for an uncached search, got \(vm.state)")
                return
            }
        }

        @Test("Filter chips come back from the last successful load when offline")
        func offlineCategories() async {
            var online = true
            let cache = StubURLProtocol.makeCache()
            let network = StubURLProtocol.makeNetworkManager(cache: cache) { request in
                guard online else { return .failure(.notConnectedToInternet) }
                return request.url!.path.hasSuffix("categories.php") ? .json(Fixtures.categories) : .json(Self.feed)
            }
            await BrowseViewModel(network: network).loadCategories()

            online = false
            let relaunched = BrowseViewModel(network: network, debounce: .zero)
            await relaunched.loadCategories()

            #expect(relaunched.categories.map(\.name) == ["Beef", "Chicken"])
        }

        @Test("Pull-to-refresh keeps current results on screen while loading")
        func refreshKeepsResults() async throws {
            var slow = false
            let network = StubURLProtocol.makeNetworkManager { request in
                if request.url!.path.hasSuffix("categories.php") { return .json(Fixtures.categories) }
                return .json(Self.feed, delay: slow ? .milliseconds(400) : .zero)
            }
            let vm = BrowseViewModel(network: network, debounce: .zero)
            await vm.loadForCurrentInputs()
            #expect(loadedNames(vm) != nil)

            slow = true
            async let refreshing: Void = vm.refresh()
            try await Task.sleep(for: .milliseconds(120))
            #expect(loadedNames(vm) == ["Flan", "Ezme"], "refresh should not flash back to skeletons")
            await refreshing
            #expect(loadedNames(vm) == ["Flan", "Ezme"])
        }
    }

    @Suite("RecipeDetailViewModel")
    @MainActor
    struct RecipeDetailViewModelTests {
        private let partial = Meal(
            id: "53120", name: "Æbleskiver", thumbnailURL: nil, category: nil,
            area: "Norway", instructions: nil, ingredients: []
        )

        @Test("A complete meal is ready immediately and never fetches")
        func completeMeal() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.notConnectedToInternet) }
            let vm = RecipeDetailViewModel(meal: Fixtures.meal(), network: network)

            #expect(vm.meal != nil)
            await vm.loadIfNeeded(localCopy: nil)

            #expect(vm.meal?.name == "Test Meal")
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @Test("A partial meal from category browsing is hydrated by id")
        func hydratesPartial() async {
            let network = StubURLProtocol.makeNetworkManager { _ in
                .json(Fixtures.mealsResponse([Fixtures.fullMealJSON(id: "53120", name: "Æbleskiver")]))
            }
            let vm = RecipeDetailViewModel(meal: partial, network: network)
            #expect(vm.meal == nil)

            await vm.loadIfNeeded(localCopy: nil)

            #expect(vm.meal?.category == "Chicken")
            #expect(vm.meal?.isFullyLoaded == true)
            #expect(StubURLProtocol.requests.first?.queryValue("i") == "53120")
        }

        @Test("A saved copy opens with no network request at all")
        func savedCopyOffline() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.notConnectedToInternet) }
            let vm = RecipeDetailViewModel(meal: partial, network: network)

            await vm.loadIfNeeded(localCopy: Fixtures.meal(id: "53120", name: "Æbleskiver"))

            #expect(vm.meal?.name == "Æbleskiver")
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @Test("Unsaved and offline shows a readable error")
        func offlineUnsaved() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.notConnectedToInternet) }
            let vm = RecipeDetailViewModel(meal: partial, network: network)

            await vm.loadIfNeeded(localCopy: nil)

            guard case .failed(let message) = vm.state else {
                Issue.record("Expected failure, got \(vm.state)")
                return
            }
            #expect(message == NetworkError.noConnection.errorDescription)
        }

        @Test("Offline with only a partial saved copy still shows that copy")
        func partialSavedCopyFallback() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.notConnectedToInternet) }
            let vm = RecipeDetailViewModel(meal: partial, network: network)

            await vm.loadIfNeeded(localCopy: partial)

            #expect(vm.meal?.name == "Æbleskiver")
        }

        @Test("A recipe opened before opens again with no connection, even unsaved")
        func cachedLookupOffline() async {
            var online = true
            let network = StubURLProtocol.makeNetworkManager { _ in
                online
                    ? .json(Fixtures.mealsResponse([Fixtures.fullMealJSON(id: "53120", name: "Æbleskiver")]))
                    : .failure(.notConnectedToInternet)
            }
            await RecipeDetailViewModel(meal: partial, network: network).loadIfNeeded(localCopy: nil)

            online = false
            let reopened = RecipeDetailViewModel(meal: partial, network: network)
            await reopened.loadIfNeeded(localCopy: nil)

            #expect(reopened.meal?.name == "Æbleskiver")
            #expect(reopened.meal?.isFullyLoaded == true)
            #expect(reopened.meal?.ingredients.isEmpty == false)
        }

        @Test("A recipe never opened before still shows the error offline")
        func uncachedLookupOffline() async {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.notConnectedToInternet) }
            let vm = RecipeDetailViewModel(meal: partial, network: network)

            await vm.loadIfNeeded(localCopy: nil)

            guard case .failed = vm.state else {
                Issue.record("Expected a failure, got \(vm.state)")
                return
            }
        }

        @Test("Retry after a failure recovers")
        func retry() async {
            var online = false
            let network = StubURLProtocol.makeNetworkManager { _ in
                online
                    ? .json(Fixtures.mealsResponse([Fixtures.fullMealJSON(id: "53120")]))
                    : .failure(.timedOut)
            }
            let vm = RecipeDetailViewModel(meal: partial, network: network)
            await vm.loadIfNeeded(localCopy: nil)
            #expect(vm.meal == nil)

            online = true
            await vm.retry(localCopy: nil)

            #expect(vm.meal?.isFullyLoaded == true)
        }
    }

    @Suite("Saved recipe photos")
    @MainActor
    struct SavedRecipeImageTests {
        private func makeContext() throws -> ModelContext {
            let schema = PantryModelContainer.schema
            return ModelContext(try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            ))
        }

        @Test("The photo is downloaded and stored for offline use")
        func storesImage() async throws {
            let bytes = Data([0xFF, 0xD8, 0xFF])
            let network = StubURLProtocol.makeNetworkManager { _ in .data(bytes) }
            let context = try makeContext()
            let recipe = SavedRecipe(meal: Fixtures.meal(id: "7"))
            context.insert(recipe)

            await recipe.storeImageIfNeeded(using: network)

            #expect(recipe.imageData == bytes)
            #expect(StubURLProtocol.requests.first?.url?.absoluteString == "https://example.com/7.jpg")
        }

        @Test("A recently viewed recipe keeps only the small preview")
        func recentKeepsPreview() async throws {
            let bytes = Data([0xFF, 0xD8, 0xFF])
            let network = StubURLProtocol.makeNetworkManager { _ in .data(bytes) }
            let context = try makeContext()
            let recent = RecentRecipe(meal: Fixtures.meal(id: "7"))
            context.insert(recent)

            await recent.storeImageIfNeeded(using: network)

            #expect(recent.imageData == bytes)
            // Recent recipes store the smaller preview image.
            #expect(StubURLProtocol.requests.first?.url?.absoluteString == "https://example.com/7.jpg/preview")
        }

        @Test("An already-stored photo isn't downloaded again")
        func skipsWhenStored() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in .data(Data([1])) }
            let context = try makeContext()
            let recipe = SavedRecipe(meal: Fixtures.meal(id: "7"))
            recipe.imageData = Data([9, 9])
            context.insert(recipe)

            await recipe.storeImageIfNeeded(using: network)

            #expect(recipe.imageData == Data([9, 9]))
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @Test("A failed download leaves the recipe usable and retries later")
        func failedDownload() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in .failure(.notConnectedToInternet) }
            let context = try makeContext()
            let recipe = SavedRecipe(meal: Fixtures.meal(id: "7"))
            context.insert(recipe)

            await recipe.storeImageIfNeeded(using: network)

            #expect(recipe.imageData == nil)
        }

        @Test("Unsaving while the photo downloads doesn't crash or resurrect it")
        func deletedDuringDownload() async throws {
            let network = StubURLProtocol.makeNetworkManager { _ in .json("jpegbytes", delay: .milliseconds(300)) }
            let context = try makeContext()
            let recipe = SavedRecipe(meal: Fixtures.meal(id: "7"))
            context.insert(recipe)
            try context.save()

            async let download: Void = recipe.storeImageIfNeeded(using: network)
            try await Task.sleep(for: .milliseconds(50))
            context.delete(recipe)
            try context.save()
            await download

            #expect(try context.fetchCount(FetchDescriptor<SavedRecipe>()) == 0)
        }
    }
}
