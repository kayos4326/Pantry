import SwiftUI

struct RecipeIngredientRow: View {
    let ingredient: Ingredient
    let isChecked: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var boxSize: CGFloat = 18

    var body: some View {
        Button(action: action) {
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
                checkbox
                ingredientText
            }
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.paperDim)
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Theme.sage, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isChecked ? Theme.sage : .clear)
            )
            .frame(width: boxSize, height: boxSize)
            .overlay {
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: boxSize * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    private var ingredientText: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))

        return layout {
            Text(ingredient.name)
                .font(Typeface.sans(13.5))
                .foregroundStyle(isChecked ? Theme.textMuted : Theme.textDark)
                .strikethrough(isChecked)
                .multilineTextAlignment(.leading)

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }

            if !ingredient.measure.isEmpty {
                Text(ingredient.measure)
                    .font(Typeface.mono(10.5, weight: .regular))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        ingredient.measure.isEmpty ? ingredient.name : "\(ingredient.name), \(ingredient.measure)"
    }
}

struct RecipeDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1.75, contentMode: .fit)
                .overlay { SkeletonBlock(cornerRadius: 20) }
                .padding(.top, 6)

            SkeletonBlock(cornerRadius: 6)
                .frame(height: 26)
                .padding(.trailing, 90)
                .padding(.top, 16)

            HStack(spacing: 10) {
                SkeletonBlock(cornerRadius: 999).frame(width: 70, height: 24)
                SkeletonBlock(cornerRadius: 999).frame(width: 58, height: 24)
            }
            .padding(.top, 10)

            SkeletonBlock(cornerRadius: 4)
                .frame(width: 92, height: 11)
                .padding(.top, 24)

            VStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: 4).frame(height: 13)
                }
            }
            .padding(.top, 16)
        }
        .accessibilityLabel("Loading recipe")
    }
}
