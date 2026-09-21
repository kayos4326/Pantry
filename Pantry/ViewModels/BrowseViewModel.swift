import Foundation

@MainActor
@Observable
final class BrowseViewModel {
    enum ViewState {
        case loading
        case loaded([Meal], offline: OfflineCopy?)
        case empty(message: String)
        case failed(message: String)
    }

    struct OfflineCopy: Equatable {
        let storedAt: Date
        let isDisconnected: Bool
    }

    enum Request: Equatable {
        case defaultFeed
        case search(String)
        case category(String)
    }

    private var storedSearchText = ""

    var searchText: String {
        get { storedSearchText }
        set {
            storedSearchText = newValue
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedCategory = nil
            }
        }
    }

    private(set) var selectedCategory: String?
    private(set) var categories: [Category] = []
    private(set) var state: ViewState = .loading

    private let network: NetworkManager
    private let debounce: Duration

    /// Prevents an older request from replacing newer results.
    private var generation = 0

    init(network: NetworkManager = .shared, debounce: Duration = .milliseconds(350)) {
        self.network = network
        self.debounce = debounce
    }

    var requestKey: String {
        "\(trimmedQuery)|\(selectedCategory ?? "")"
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentRequest: Request {
        if !trimmedQuery.isEmpty { return .search(trimmedQuery) }
        if let selectedCategory { return .category(selectedCategory) }
        return .defaultFeed
    }

    func loadCategories() async {
        guard categories.isEmpty else { return }
        if let live = try? await network.fetchCategories() {
            categories = live
        } else {
            categories = await network.cachedCategories()?.value ?? []
        }
    }

    func loadForCurrentInputs() async {
        if !trimmedQuery.isEmpty {
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return // superseded by a newer keystroke
            }
        }
        await load(currentRequest, showSkeleton: true)
    }

    func select(category name: String?) {
        searchText = ""
        selectedCategory = (selectedCategory == name) ? nil : name
    }

    func retry() async {
        async let chips: Void = loadCategories()
        await load(currentRequest, showSkeleton: true)
        await chips
    }

    func refresh() async {
        async let chips: Void = loadCategories()
        await load(currentRequest, showSkeleton: false)
        await chips
    }

    private func load(_ request: Request, showSkeleton: Bool) async {
        generation += 1
        let thisLoad = generation
        if showSkeleton { state = .loading }

        let outcome: ViewState
        do {
            let meals: [Meal]
            switch request {
            case .defaultFeed:
                meals = try await network.searchMeals(named: "")
            case .search(let query):
                meals = try await network.searchMeals(named: query)
            case .category(let name):
                meals = try await network.filterMeals(byCategory: name)
            }
            outcome = .loaded(meals, offline: nil)
        } catch is CancellationError {
            return
        } catch NetworkError.emptyResults {
            outcome = .empty(message: Self.emptyMessage(for: request))
        } catch {
            if Task.isCancelled { return }
            if let cached = await cachedResults(for: request) {
                outcome = .loaded(
                    cached.value,
                    offline: OfflineCopy(
                        storedAt: cached.storedAt,
                        isDisconnected: (error as? NetworkError) == .noConnection
                    )
                )
            } else {
                outcome = .failed(message: error.localizedDescription)
            }
        }

        guard thisLoad == generation else { return }
        state = outcome
    }

    private func cachedResults(for request: Request) async -> NetworkManager.Cached<[Meal]>? {
        switch request {
        case .defaultFeed: await network.cachedMeals(search: "")
        case .search(let query): await network.cachedMeals(search: query)
        case .category(let name): await network.cachedMeals(category: name)
        }
    }

    private static func emptyMessage(for request: Request) -> String {
        switch request {
        case .search(let query):
            return "No recipes matched \"\(query)\"."
        case .category(let name):
            return "No recipes found in \(name)."
        case .defaultFeed:
            return "No recipes available right now."
        }
    }
}
