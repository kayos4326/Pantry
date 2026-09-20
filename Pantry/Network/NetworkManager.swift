import Foundation

/// Thin wrapper around TheMealDB's JSON API using async/await URLSession.
///
/// Every successful response is also written to `ResponseCache`, and each
/// endpoint has a matching `cached…` reader. Callers decide when to fall back
/// to that copy, which is what keeps Browse and Detail usable offline.
final class NetworkManager {
    static let shared = NetworkManager()

    /// A value read back from the offline copy, with the time it was stored so
    /// the UI can say how old it is.
    struct Cached<Value> {
        let value: Value
        let storedAt: Date
    }

    /// The four endpoints the app uses, each carrying the key its offline copy
    /// is filed under. Keeping the URL and the key together means a cached
    /// response can never be filed against the wrong request.
    enum Endpoint: Equatable {
        case search(String)
        case filter(category: String)
        case categories
        case lookup(id: String)

        var path: String {
            switch self {
            case .search: "search.php"
            case .filter: "filter.php"
            case .categories: "categories.php"
            case .lookup: "lookup.php"
            }
        }

        var queryItems: [URLQueryItem] {
            switch self {
            case .search(let query): [URLQueryItem(name: "s", value: query)]
            case .filter(let category): [URLQueryItem(name: "c", value: category)]
            case .categories: []
            case .lookup(let id): [URLQueryItem(name: "i", value: id)]
            }
        }

        var cacheKey: String {
            switch self {
            case .search(let query): "search:\(query.lowercased())"
            case .filter(let category): "filter:\(category.lowercased())"
            case .categories: "categories"
            case .lookup(let id): "lookup:\(id)"
            }
        }
    }

    private let baseURL = URL(string: "https://www.themealdb.com/api/json/v1/1/")!
    private let session: URLSession
    private let cache: ResponseCache
    /// URLSession's default is 60 s, which leaves a dead connection showing
    /// a skeleton for a full minute before any error appears.
    private let requestTimeout: TimeInterval = 15

    init(session: URLSession = .shared, cache: ResponseCache = .shared) {
        self.session = session
        self.cache = cache
    }

    // MARK: - Endpoints

    func searchMeals(named query: String) async throws -> [Meal] {
        let response: MealResponse = try await get(.search(query))
        guard let meals = response.meals, !meals.isEmpty else {
            throw NetworkError.emptyResults
        }
        return meals
    }

    func filterMeals(byCategory category: String) async throws -> [Meal] {
        let response: MealResponse = try await get(.filter(category: category))
        guard let meals = response.meals, !meals.isEmpty else {
            throw NetworkError.emptyResults
        }
        return meals
    }

    func fetchCategories() async throws -> [Category] {
        let response: CategoryResponse = try await get(.categories)
        guard !response.categories.isEmpty else {
            throw NetworkError.emptyResults
        }
        return response.categories
    }

    func lookupMeal(id: String) async throws -> Meal {
        let response: MealResponse = try await get(.lookup(id: id))
        guard let meal = response.meals?.first else {
            throw NetworkError.emptyResults
        }
        return meal
    }

    /// Raw bytes for a recipe photo, so saved recipes keep their images offline.
    func imageData(from url: URL) async throws -> Data {
        let data = try await fetch(url)
        guard !data.isEmpty else { throw NetworkError.emptyResults }
        return data
    }

    // MARK: - Offline copies

    /// Results from the last successful request for the same search, if there
    /// was one. `nil` means there's nothing to show but the error.
    func cachedMeals(search query: String) async -> Cached<[Meal]>? {
        await cachedMeals(.search(query))
    }

    func cachedMeals(category: String) async -> Cached<[Meal]>? {
        await cachedMeals(.filter(category: category))
    }

    func cachedCategories() async -> Cached<[Category]>? {
        guard
            let cached: Cached<CategoryResponse> = await cachedValue(.categories),
            !cached.value.categories.isEmpty
        else { return nil }
        return Cached(value: cached.value.categories, storedAt: cached.storedAt)
    }

    /// The last copy of a full recipe, which lets a recently viewed recipe
    /// open with no connection even when it was never saved.
    func cachedMeal(id: String) async -> Cached<Meal>? {
        guard
            let cached: Cached<MealResponse> = await cachedValue(.lookup(id: id)),
            let meal = cached.value.meals?.first
        else { return nil }
        return Cached(value: meal, storedAt: cached.storedAt)
    }

    private func cachedMeals(_ endpoint: Endpoint) async -> Cached<[Meal]>? {
        guard
            let cached: Cached<MealResponse> = await cachedValue(endpoint),
            let meals = cached.value.meals, !meals.isEmpty
        else { return nil }
        return Cached(value: meals, storedAt: cached.storedAt)
    }

    private func cachedValue<T: Decodable>(_ endpoint: Endpoint) async -> Cached<T>? {
        guard
            let entry = await cache.entry(for: endpoint.cacheKey),
            let value = try? JSONDecoder().decode(T.self, from: entry.data)
        else { return nil }
        return Cached(value: value, storedAt: entry.storedAt)
    }

    // MARK: - Core request

    private func get<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await fetch(try url(for: endpoint))

        let value: T
        do {
            value = try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }

        // Only what decoded cleanly is kept, so the offline copy can never be
        // worse than what the app just displayed.
        await cache.store(data, for: endpoint.cacheKey)
        return value
    }

    private func url(for endpoint: Endpoint) throws -> URL {
        let path = baseURL.appendingPathComponent(endpoint.path)
        guard var components = URLComponents(url: path, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }
        return url
    }

    private func fetch(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, timeoutInterval: requestTimeout)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cancelled:
                // A debounced search superseded this request — not a real failure.
                throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw NetworkError.noConnection
            default:
                throw NetworkError.unknown(urlError.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown("Missing HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.badResponse(statusCode: httpResponse.statusCode)
        }
        return data
    }
}
