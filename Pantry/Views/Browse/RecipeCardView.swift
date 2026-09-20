import SwiftUI

enum RecipeGrid {
    /// Two columns on iPhone; iPad widens to more without any extra code.
    /// At accessibility text sizes a card needs the full width to stay legible.
    static func columns(for typeSize: DynamicTypeSize) -> [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: spacing)]
            : [GridItem(.adaptive(minimum: 150), spacing: spacing)]
    }

    static let spacing: CGFloat = 12
}

struct RecipeCardView: View {
    let meal: Meal
    /// filter.php omits strCategory, so the browsing category is passed in to
    /// stop the card falling back to the area and printing it twice.
    var categoryFallback: String?
    /// Photo bytes kept on device for saved recipes.
    var storedImageData: Data?

    private var subtitle: String? {
        meal.category ?? categoryFallback
    }

    var body: some View {
        VStack(spacing: 0) {
            // A ZStack rather than an overlay: overlays can't affect layout,
            // so an enlarged badge could only clip. Here the photo area grows
            // if the badge ever needs more room than the photo gives it.
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .aspectRatio(1.55, contentMode: .fit)
                    .overlay {
                        RecipeImage(url: meal.gridThumbnailURL, storedData: storedImageData, cacheKey: meal.id)
                    }
                    .clipped()

                if let badge = meal.area {
                    Text(badge)
                        .font(Typeface.mono(9.5))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        // Opaque rather than a scrim: at 55% black the badge's
                        // contrast depended on the photo behind it, and pale
                        // pictures failed the contrast audit on some runs.
                        // Charcoal is a fixed 15:1 against the white text.
                        .background(Capsule().fill(Theme.charcoal))
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(meal.name)
                    .font(Typeface.serif(14.5))
                    .foregroundStyle(Theme.textDark)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.mono(9.5))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Loading placeholder that mirrors the card's layout so the grid doesn't
/// jump when real content arrives.
struct RecipeCardSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1.55, contentMode: .fit)
                .overlay { SkeletonBlock(cornerRadius: 0) }

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(cornerRadius: 4).frame(height: 11)
                SkeletonBlock(cornerRadius: 4).frame(height: 11).padding(.trailing, 34)
                SkeletonBlock(cornerRadius: 4).frame(width: 52, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
