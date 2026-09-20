import Foundation
import SwiftData

/// Adopted by the stored models that keep their own copy of a recipe photo, so
/// the download-once rule is written once rather than per model.
///
/// Only the download is main-actor bound; marking the protocol itself would
/// make every conforming model main-actor isolated, which the rest of the app
/// doesn't need.
protocol StoredPhoto: AnyObject, PersistentModel {
    /// The photo itself, kept so the app shows pictures with no connection.
    /// TheMealDB sends no cache headers, so URLCache can't be relied on.
    var imageData: Data? { get set }
    /// Which size to keep: the full photo for a recipe that fills the detail
    /// screen, the ~9 KB preview for one that only ever appears as a thumbnail.
    var photoURL: URL? { get }
}

extension StoredPhoto {
    /// Downloads and keeps the photo if it isn't stored yet. Safe to call
    /// repeatedly: a failed download leaves the remote URL in use and is
    /// retried next time.
    @MainActor
    func storeImageIfNeeded(using network: NetworkManager = .shared) async {
        guard imageData == nil, let url = photoURL else { return }
        guard let data = try? await network.imageData(from: url) else { return }
        // The row may have been deleted while the download was in flight.
        guard modelContext != nil, !isDeleted else { return }
        imageData = data
    }
}
