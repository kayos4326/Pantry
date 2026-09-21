import SwiftUI

enum RecipeGrid {
    /// Uses full-width cards at accessibility text sizes.
    static func columns(for typeSize: DynamicTypeSize) -> [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: spacing)]
            : [GridItem(.adaptive(minimum: 150), spacing: spacing)]
    }

    static let spacing: CGFloat = 12
}

struct RecipeCardView: View {
    let meal: Meal
    /// Category supplied by the browse screen when the API omits it.
    var categoryFallback: String?
    var storedImageData: Data?

    private var subtitle: String? {
        meal.category ?? categoryFallback
    }

    var body: some View {
        VStack(spacing: 0) {
            // Let the photo area grow if a large category label needs more room.
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
                        // A fixed background keeps the label readable on every photo.
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

/// Loading placeholder sized like a recipe card.
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
