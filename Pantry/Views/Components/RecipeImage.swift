import SwiftUI
import UIKit

/// Shows a stored photo first, then falls back to the network.
struct RecipeImage: View {
    let url: URL?
    var storedData: Data?
    var cacheKey: String?
    /// Limits decoded image size for smaller views.
    var maxPixelSize: CGFloat = 600

    var body: some View {
        Group {
            if let image = decodedStoredImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        Theme.photoPlaceholder
                            .overlay {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.textMuted.opacity(0.7))
                            }
                    case .empty:
                        Theme.photoPlaceholder.shimmering()
                    @unknown default:
                        Theme.photoPlaceholder
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var decodedStoredImage: UIImage? {
        guard let storedData else { return nil }
        let key = "\(cacheKey ?? String(storedData.count))-\(Int(maxPixelSize))" as NSString
        if let cached = DecodedImageCache.shared.object(forKey: key) {
            return cached
        }
        guard let full = UIImage(data: storedData) else { return nil }
        let longest = max(full.size.width, full.size.height)
        let scale = min(1, maxPixelSize / max(longest, 1))
        let target = CGSize(width: full.size.width * scale, height: full.size.height * scale)
        let decoded = full.preparingThumbnail(of: target) ?? full
        DecodedImageCache.shared.setObject(decoded, forKey: key)
        return decoded
    }
}

/// Keeps decoded images in memory to avoid stuttering while scrolling.
private enum DecodedImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()
}
