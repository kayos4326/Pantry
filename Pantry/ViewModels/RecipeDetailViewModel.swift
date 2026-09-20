import Foundation

@MainActor
@Observable
final class RecipeDetailViewModel {
    enum ViewState {
        case loading
        case ready(Meal)
        case failed(message: String)
    }

    private(set) var state: ViewState
    private let mealID: String
    private let network: NetworkManager

    init(meal: Meal, network: NetworkManager = .shared) {
        self.mealID = meal.id
        self.network = network
        self.state = meal.isFullyLoaded ? .ready(meal) : .loading
    }

    var meal: Meal? {
        if case .ready(let meal) = state { return meal }
        return nil
    }

    /// Meals arriving from category browsing carry no instructions or
    /// ingredients, so they're re-fetched by id. A copy already on the device
    /// — saved, or from a previous visit — is preferred over the network,
    /// which is what lets those recipes open with no connection.
    func loadIfNeeded(localCopy: Meal?) async {
        guard case .loading = state else { return }

        if let localCopy, localCopy.isFullyLoaded {
            state = .ready(localCopy)
            return
        }

        do {
            state = .ready(try await network.lookupMeal(id: mealID))
        } catch is CancellationError {
            return
        } catch {
            // The stored copy of this recipe, if it's been opened before. It's
            // complete, so it's preferred over a partial saved copy.
            if let cached = await network.cachedMeal(id: mealID), cached.value.isFullyLoaded {
                state = .ready(cached.value)
            } else if let localCopy {
                // Falling back to a partial local copy still beats an error screen.
                state = .ready(localCopy)
            } else {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func retry(localCopy: Meal?) async {
        state = .loading
        await loadIfNeeded(localCopy: localCopy)
    }
}
