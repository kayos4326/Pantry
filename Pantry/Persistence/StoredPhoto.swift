import Foundation
import SwiftData

/// Shared photo storage for saved and recently viewed recipes.
protocol StoredPhoto: AnyObject, PersistentModel {
    var imageData: Data? { get set }
    var photoURL: URL? { get }
}

extension StoredPhoto {
    /// Downloads the photo once and retries on a later call if it fails.
    @MainActor
    func storeImageIfNeeded(using network: NetworkManager = .shared) async {
        guard imageData == nil, let url = photoURL else { return }
        guard let data = try? await network.imageData(from: url) else { return }
        // The model may have been deleted while the download was running.
        guard modelContext != nil, !isDeleted else { return }
        imageData = data
    }
}
