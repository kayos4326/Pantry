import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var savedMatches: [SavedRecipe]
    /// A previous visit's copy, which stands in for the network the same way a
    /// saved one does.
    @Query private var recentMatches: [RecentRecipe]
    @State private var viewModel: RecipeDetailViewModel
    /// What the card handed over, kept so a visit can be recorded even if the
    /// full recipe never arrives.
    private let meal: Meal

    /// Purely local, as specified — ticking ingredients isn't persisted.
    @State private var checkedIngredients: Set<Int> = []
    @State private var heartScale: CGFloat = 1
    @State private var isConfirmingUnsave = false

    /// Keeps long lines readable on iPad instead of spanning the whole screen.
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

    /// The best copy already on the device: whichever of the saved and
    /// recently viewed rows is complete, falling back to a partial one.
    private var localCopy: Meal? {
        let copies = [savedRecipe?.asMeal, recentMatches.first?.asMeal].compactMap { $0 }
        return copies.first(where: \.isFullyLoaded) ?? copies.first
    }

    var body: some View {
        ScrollView {
            Group {
                switch viewModel.state {
                case .loading:
                    DetailSkeleton()
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
            // Recorded after loading, so the entry gets the hydrated recipe's
            // category rather than the blank one a filtered card carries.
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
                        IngredientRow(
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
                    storedData: savedRecipe?.imageData,
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
                // 44 pt touch target around the 38 pt circle.
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save recipe")
        .accessibilityAddTraits(isSaved ? .isSelected : [])
        .accessibilityIdentifier("detail.saveButton")
    }

    /// TheMealDB has no cook-time field, so these numbers are read out of the
    /// instruction text. Labelled as estimates for that reason.
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
        // Category and area are real fields; a tag fills the third slot when
        // TheMealDB provides one. There is no cook time or serving count.
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
        /// nil for a sub-heading.
        let number: Int?
        let text: String
    }

    /// Numbers run continuously across sub-headings, so "step 4" is
    /// unambiguous when reading aloud or following along.
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
            // Unsaving cascades to the planner, so ask first rather than
            // silently wiping planned days on a single tap.
            if plannedDayCount > 0 {
                isConfirmingUnsave = true
                return
            }
            removeSavedRecipe()
        } else {
            // `meal` is always the hydrated copy here, so a recipe opened from
            // a category filter still saves with its full ingredient list.
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

// MARK: - Ingredient row

private struct IngredientRow: View {
    let ingredient: Ingredient
    let isChecked: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var boxSize: CGFloat = 18

    var body: some View {
        Button(action: action) {
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
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

                // Side by side normally; at accessibility sizes the measure
                // sits under the name so neither is squeezed into a sliver.
                let textLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(spacing: 8))

                textLayout {
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
        .accessibilityLabel(ingredient.measure.isEmpty ? ingredient.name : "\(ingredient.name), \(ingredient.measure)")
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

// MARK: - Loading placeholder

private struct DetailSkeleton: View {
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
