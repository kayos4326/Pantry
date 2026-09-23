import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var savedMatches: [SavedRecipe]
    /// A previous visit can provide an offline copy.
    @Query private var recentMatches: [RecentRecipe]
    @State private var viewModel: RecipeDetailViewModel
    /// The partial or complete meal passed by the previous screen.
    private let meal: Meal

    @State private var checkedIngredients: Set<Int> = []
    @State private var heartScale: CGFloat = 1
    @State private var isConfirmingUnsave = false

    private let readableWidth: CGFloat = 720

    init(meal: Meal) {
        let mealID = meal.id
        self.meal = meal
        _savedMatches = Query(filter: #Predicate<SavedRecipe> { $0.mealID == mealID })
        _recentMatches = Query(filter: #Predicate<RecentRecipe> { $0.mealID == mealID })
        _viewModel = State(initialValue: RecipeDetailViewModel(meal: meal))
    }

    private var savedRecipe: SavedRecipe? { savedMatches.first }
    private var isSaved: Bool { savedRecipe != nil }

    /// Prefers a complete saved or recently viewed copy.
    private var localCopy: Meal? {
        let copies = [savedRecipe?.asMeal, recentMatches.first?.asMeal].compactMap { $0 }
        return copies.first(where: \.isFullyLoaded) ?? copies.first
    }

    var body: some View {
        ScrollView {
            Group {
                switch viewModel.state {
                case .loading:
                    RecipeDetailSkeleton()
                        .padding(.bottom, 24)

                case .ready(let meal):
                    loadedContent(meal)
                        .padding(.bottom, 32)

                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.retry(localCopy: localCopy) }
                    }
                }
            }
            .frame(maxWidth: readableWidth)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded(localCopy: localCopy)
            // Record the hydrated meal when available.
            let recent = RecentRecipe.record(viewModel.meal ?? meal, in: context)
            await recent.storeImageIfNeeded()
        }
        .confirmationDialog(
            unsaveTitle,
            isPresented: $isConfirmingUnsave,
            titleVisibility: .visible
        ) {
            Button("Remove and clear from planner", role: .destructive) {
                removeSavedRecipe()
            }
            Button("Keep saved", role: .cancel) {}
        } message: {
            Text("Removing it from Saved also removes it from those days in the Meal Planner.")
        }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func loadedContent(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(meal)

            Text(meal.name)
                .font(Typeface.serif(25))
                .foregroundStyle(Theme.textDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)

            metaRow(meal)
                .padding(.top, 8)

            timingCard(meal)

            if !meal.ingredients.isEmpty {
                SectionLabel(text: "Ingredients")
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    ForEach(meal.ingredients) { ingredient in
                        RecipeIngredientRow(
                            ingredient: ingredient,
                            isChecked: checkedIngredients.contains(ingredient.id)
                        ) {
                            toggle(ingredient.id)
                        }
                    }
                }
                .padding(.top, 2)
            }

            let lines = numberedLines(meal.instructionLines)
            if lines.contains(where: { $0.number != nil }) {
                SectionLabel(text: "Steps")
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(lines) { line in
                        if let number = line.number {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(number)")
                                    .font(Typeface.serif(15))
                                    .foregroundStyle(Theme.brick)
                                    .frame(minWidth: 20, alignment: .leading)
                                Text(line.text)
                                    .font(Typeface.sans(13))
                                    .foregroundStyle(Theme.textDark)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Step \(number). \(line.text)")
                        } else {
                            Text(line.text)
                                .font(Typeface.serif(16))
                                .foregroundStyle(Theme.textDark)
                                .padding(.top, 6)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func hero(_ meal: Meal) -> some View {
        Color.clear
            .aspectRatio(1.75, contentMode: .fit)
            .overlay {
                RecipeImage(
                    url: meal.thumbnailURL,
                    storedData: savedRecipe?.imageData ?? recentMatches.first?.imageData,
                    cacheKey: "\(meal.id)-hero",
                    maxPixelSize: 1400
                )
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                saveButton(meal)
                    .padding(9)
            }
            .padding(.top, 6)
    }

    private func saveButton(_ meal: Meal) -> some View {
        Button {
            toggleSave(meal)
        } label: {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.brick)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.surface))
                .scaleEffect(heartScale)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save recipe")
        .accessibilityAddTraits(isSaved ? .isSelected : [])
        .accessibilityIdentifier("detail.saveButton")
    }

    /// Displays timing estimates parsed from the instructions.
    @ViewBuilder
    private func timingCard(_ meal: Meal) -> some View {
        let timing = meal.timing

        if timing.activeMinutes != nil || timing.makeAhead != nil || timing.sameDayWaitMinutes != nil {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 14, rowSpacing: 8) {
                    if let active = timing.activeMinutes {
                        timingStat(symbol: "flame", value: DurationText.approximate(minutes: active), caption: "cooking")
                    }
                    if let wait = timing.sameDayWaitMinutes {
                        timingStat(symbol: "hourglass", value: DurationText.exact(minutes: wait), caption: "resting")
                    }
                    if let ahead = timing.makeAhead {
                        timingStat(
                            symbol: "calendar.badge.clock",
                            value: "\(ahead.leadDays) day\(ahead.leadDays == 1 ? "" : "s") ahead",
                            caption: ahead.isOptional ? "optional" : "required"
                        )
                    }
                }

                if let ahead = timing.makeAhead {
                    Text("\(ahead.isOptional ? "Can be started early" : "Needs starting early") — \"\(ahead.phrase.trimmingCharacters(in: .whitespaces))\"")
                        .font(Typeface.mono(9))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Estimated from the recipe steps")
                    .font(Typeface.mono(8.5))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private func timingStat(symbol: String, value: String, caption: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(Typeface.mono(12))
                .foregroundStyle(Theme.brick)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(Typeface.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.textDark)
                Text(caption)
                    .font(Typeface.mono(8.5))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func metaRow(_ meal: Meal) -> some View {
        let pills = ([meal.category, meal.area].compactMap { $0 } + meal.tagList.prefix(1))

        return FlowLayout(spacing: 10, rowSpacing: 8) {
            ForEach(pills, id: \.self) { pill in
                Text(pill)
                    .font(Typeface.mono(10.5))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.surface))
            }
        }
    }

    // MARK: - Steps numbering

    private struct NumberedLine: Identifiable {
        let id: Int
        let number: Int?
        let text: String
    }

    /// Numbers steps continuously across subheadings.
    private func numberedLines(_ lines: [InstructionLine]) -> [NumberedLine] {
        var stepNumber = 0
        return lines.enumerated().map { index, line in
            switch line {
            case .header(let text):
                return NumberedLine(id: index, number: nil, text: text)
            case .step(let text):
                stepNumber += 1
                return NumberedLine(id: index, number: stepNumber, text: text)
            }
        }
    }

    // MARK: - Actions

    private var plannedDayCount: Int {
        savedRecipe?.plannedDayCount ?? 0
    }

    private var unsaveTitle: String {
        let days = plannedDayCount
        return "\(savedRecipe?.name ?? "This recipe") is planned on \(days) day\(days == 1 ? "" : "s")"
    }

    private func toggle(_ id: Int) {
        withAnimation(.easeOut(duration: 0.15)) {
            if checkedIngredients.contains(id) {
                checkedIngredients.remove(id)
            } else {
                checkedIngredients.insert(id)
            }
        }
    }

    private func toggleSave(_ meal: Meal) {
        if savedRecipe != nil {
            if plannedDayCount > 0 {
                isConfirmingUnsave = true
                return
            }
            removeSavedRecipe()
        } else {
            let recipe = SavedRecipe(meal: meal)
            context.insert(recipe)
            Task { await recipe.storeImageIfNeeded() }
            bounceHeart()
        }
    }

    private func removeSavedRecipe() {
        guard let savedRecipe else { return }
        context.delete(savedRecipe)
        bounceHeart()
    }

    private func bounceHeart() {
        heartScale = 1
        withAnimation(.spring(response: 0.15, dampingFraction: 0.45)) {
            heartScale = 1.35
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.12)) {
            heartScale = 1
        }
    }
}
