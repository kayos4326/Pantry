import SwiftUI
import SwiftData

/// Picker for adding a saved recipe to a day, or swapping one already on it.
/// Only saved recipes can be planned, since the planner has to keep working
/// offline.
struct MealPickerSheet: View {
    let date: Date
    /// The meal being replaced, when the sheet was opened from Change. Nil
    /// while adding a meal to the day.
    let assignedRecipe: SavedRecipe?
    let onSelect: (SavedRecipe) -> Void
    /// Only set when replacing an existing meal, which is the only case where
    /// there's something to remove.
    let onRemove: (() -> Void)?

    @Query(sort: \SavedRecipe.savedAt, order: .reverse) private var savedRecipes: [SavedRecipe]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Clears the sheet's grabber, which was clipping the eyebrow.
                PageHeader(eyebrow: "Plan for", title: headline)
                    .padding(.top, 28)

                DashedDivider()
                    .padding(.vertical, 16)

                if savedRecipes.isEmpty {
                    EmptyStateView(
                        symbol: "heart",
                        message: "No saved recipes yet.",
                        detail: "Save a recipe from Browse, then plan it here."
                    )
                } else {
                    // Above the list, so removing doesn't need a scroll past
                    // every saved recipe.
                    if let onRemove {
                        removeButton(onRemove)
                            .padding(.bottom, 14)
                    }

                    VStack(spacing: 10) {
                        ForEach(savedRecipes) { recipe in
                            recipeRow(recipe)
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.paper)
    }

    private var headline: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func recipeRow(_ recipe: SavedRecipe) -> some View {
        let isAssigned = recipe.persistentModelID == assignedRecipe?.persistentModelID
        let makeAhead = recipe.asMeal.timing.makeAhead

        return Button {
            onSelect(recipe)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RecipeImage(
                    url: recipe.gridThumbnailURL,
                    storedData: recipe.imageData,
                    cacheKey: recipe.mealID,
                    maxPixelSize: 200
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.name)
                        .font(Typeface.serif(14.5))
                        .foregroundStyle(Theme.textDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let category = recipe.category {
                        Text(category)
                            .font(Typeface.mono(9.5))
                            .foregroundStyle(Theme.textMuted)
                    }

                    if let makeAhead {
                        leadBadge(makeAhead)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isAssigned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.sage)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isAssigned ? .isSelected : [])
        .accessibilityIdentifier("picker.recipeRow")
    }

    /// Shown before choosing, so a recipe that should already be marinating
    /// isn't picked for a date that's now too soon without warning.
    private func leadBadge(_ makeAhead: MakeAheadRequirement) -> some View {
        let days = "\(makeAhead.leadDays) day\(makeAhead.leadDays == 1 ? "" : "s")"
        let tooLate: Bool = {
            guard !makeAhead.isOptional else { return false }
            if case .overdue = PrepSchedule.status(mealDate: date, leadDays: makeAhead.leadDays) { return true }
            return false
        }()

        let text: String
        if makeAhead.isOptional {
            text = "Can be made \(days) ahead"
        } else if tooLate {
            text = "Needs \(days) ahead — too late for this date"
        } else {
            text = "Needs \(days) ahead"
        }

        // An HStack rather than a Label: Label keeps its title on one line,
        // which truncated the warning on narrower widths.
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: tooLate ? "exclamationmark.octagon.fill" : "calendar.badge.clock")
                .accessibilityHidden(true)
            Text(text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typeface.mono(9, weight: .semibold))
        .foregroundStyle(tooLate ? Theme.brick : (makeAhead.isOptional ? Theme.sageText : Theme.mustardText))
        .padding(.top, 1)
    }

    private func removeButton(_ remove: @escaping () -> Void) -> some View {
        Button {
            remove()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Remove this meal")
            }
            .font(Typeface.mono(12, weight: .semibold))
            .foregroundStyle(Theme.brick)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay {
                Capsule().strokeBorder(Theme.brick, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
