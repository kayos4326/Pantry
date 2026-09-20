import Foundation

@MainActor
@Observable
final class BrowseViewModel {
    enum ViewState {
        case loading
        /// `offline` is non-nil when the request failed and these results came
        /// from the copy on disk instead, so the view can say so.
        case loaded([Meal], offline: OfflineCopy?)
        case empty(message: String)
        case failed(message: String)
    }

    struct OfflineCopy: Equatable {
        let storedAt: Date
        /// False when the request failed for some reason other than
        /// connectivity, e.g. a server error. Only the wording changes.
        let isDisconnected: Bool
    }

    /// What the current inputs resolve to. TheMealDB has no combined
    /// search+category endpoint, so exactly one of these is in play at a time.
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
            // Search and category are mutually exclusive, so typing drops the
            // chip filter. Doing it here rather than during the load keeps both
            // mutations in one pass, so `requestKey` only changes once.
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

    /// Incremented for every load. A response is only applied if no newer
    /// load has started since — otherwise a slow retry could land after, and
    /// overwrite, the results of a category the user picked later.
    private var generation = 0

    init(network: NetworkManager = .shared, debounce: Duration = .milliseconds(350)) {
        self.network = network
        self.debounce = debounce
    }

    /// Single key derived from both inputs. The view drives loading off this,
    /// so search text and category selection can never disagree about what
    /// should be on screen.
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
        // A failure here only costs the filter chips; the grid still works,
        // so this doesn't put the whole screen into an error state. Offline,
        // the chips from the last successful load are worth keeping.
        if let live = try? await network.fetchCategories() {
            categories = live
        } else {
            categories = await network.cachedCategories()?.value ?? []
        }
    }

    /// Called by the view whenever `requestKey` changes. Typing is debounced;
    /// tapping a chip is not.
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
        // Category and search are mutually exclusive, so picking a chip
        // clears any query. Both mutations land before the view re-reads
        // requestKey, so this triggers exactly one load.
        searchText = ""
        selectedCategory = (selectedCategory == name) ? nil : name
    }

    /// Retry after a failure. Chips that failed to load alongside the grid
    /// get another attempt too.
    func retry() async {
        async let chips: Void = loadCategories()
        await load(currentRequest, showSkeleton: true)
        await chips
    }

    /// Pull-to-refresh keeps the current results on screen until new ones
    /// arrive, rather than flashing back to skeletons.
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
                // An empty query returns a starter set of meals, which saves
                // hardcoding a default category.
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
            // A genuine "no matches" answer from the server, not a failure to
            // reach it, so the offline copy would only be misleading here.
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

    /// The stored copy of whatever the current inputs ask for. The default
    /// feed and an empty search are the same request, so they share a copy.
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
