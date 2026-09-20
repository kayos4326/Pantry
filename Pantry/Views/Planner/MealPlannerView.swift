import SwiftUI
import SwiftData

struct MealPlannerView: View {
    @Environment(\.modelContext) private var context
    @Query private var plannedMeals: [PlannedMeal]

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    /// Identifies whether the picker adds or replaces a meal.
    @State private var pickerTarget: PickerTarget?
    @Environment(\.dynamicTypeSize) private var typeSize

    enum PickerTarget: Identifiable {
        case add
        case change(PlannedMeal)

        var id: String {
            switch self {
            case .add: "add"
            case .change(let meal): "change-\(meal.persistentModelID)"
            }
        }

        var meal: PlannedMeal? {
            if case .change(let meal) = self { return meal }
            return nil
        }
    }

    private let calendar = Calendar.current
    private let readableWidth: CGFloat = 720

    /// Five previous days, today, and 24 upcoming days.
    private var dates: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (-5...24).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        let markers = PrepSchedule.markers(
            plans: plannedMeals
                .filter { $0.recipe != nil }
                .map { (date: $0.date, leadDays: $0.requiredLeadDays) }
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(eyebrow: "Next 30 days", title: "Meal Planner")
                        .frame(maxWidth: readableWidth, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    DateStrip(dates: dates, selection: $selectedDate) { date in
                        markers[calendar.startOfDay(for: date)] ?? .none
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 0) {
                        DashedDivider()
                            .padding(.vertical, 16)

                        Text(headline(for: selectedDate))
                            .font(Typeface.serif(19))
                            .foregroundStyle(Theme.textDark)
                            .accessibilityAddTraits(.isHeader)

                        plannedSection
                            .padding(.top, 12)

                        prepSection
                    }
                    .frame(maxWidth: readableWidth, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 24)
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meal.self) { meal in
                RecipeDetailView(meal: meal)
            }
            .sheet(item: $pickerTarget) { target in
                MealPickerSheet(
                    date: selectedDate,
                    assignedRecipe: target.meal?.recipe,
                    onSelect: { recipe in
                        if let meal = target.meal {
                            replace(meal, with: recipe)
                        } else {
                            add(recipe, to: selectedDate)
                        }
                    },
                    onRemove: target.meal.map { meal in { remove(meal) } }
                )
            }
        }
    }

    // MARK: - Selected day

    /// Shows the day's meals followed by the add action.
    private var plannedSection: some View {
        let meals = plannedMeals(on: selectedDate)

        return VStack(spacing: 10) {
            ForEach(meals) { meal in
                if let recipe = meal.recipe {
                    plannedCard(meal, recipe: recipe)
                }
            }

            addMealButton(isFirst: meals.isEmpty)
        }
    }

    private func plannedCard(_ meal: PlannedMeal, recipe: SavedRecipe) -> some View {
        let rowLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))

        return VStack(spacing: 0) {
                rowLayout {
                    NavigationLink(value: recipe.asMeal) {
                        HStack(spacing: 12) {
                            RecipeImage(
                                url: recipe.gridThumbnailURL,
                                storedData: recipe.imageData,
                                cacheKey: recipe.mealID,
                                maxPixelSize: 240
                            )
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.name)
                                    .font(Typeface.serif(16))
                                    .foregroundStyle(Theme.textDark)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                timingLine(for: recipe)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the recipe")
                    .accessibilityIdentifier("planner.plannedRecipe")

                    Button {
                        pickerTarget = .change(meal)
                    } label: {
                        Text("Change")
                            .font(Typeface.mono(10.5, weight: .semibold))
                            .foregroundStyle(Theme.brick)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .overlay { Capsule().strokeBorder(Theme.brick, lineWidth: 1) }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change \(recipe.name) on \(headline(for: selectedDate))")
                }
                .padding(14)

                makeAheadNote(for: recipe)
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Uses a larger treatment when the selected day is empty.
    private func addMealButton(isFirst: Bool) -> some View {
        Button {
            pickerTarget = .add
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: isFirst ? 15 : 13, weight: .medium))
                    .foregroundStyle(Theme.textMuted.opacity(0.7))
                    .frame(width: isFirst ? 58 : 36, height: isFirst ? 58 : 36)
                    .background(Theme.paperDim.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: isFirst ? 12 : 9))

                Text(isFirst ? "Tap to plan a meal" : "Add another meal")
                    .font(Typeface.mono(11.5))
                    .foregroundStyle(Theme.textMuted)

                Spacer(minLength: 0)
            }
            .padding(isFirst ? 14 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFirst
            ? "Plan a meal for \(headline(for: selectedDate))"
            : "Add another meal to \(headline(for: selectedDate))")
        .accessibilityIdentifier("planner.planMeal")
    }

    @ViewBuilder
    private func timingLine(for recipe: SavedRecipe) -> some View {
        let timing = recipe.asMeal.timing
        let parts = [
            recipe.category,
            timing.activeMinutes.map { "\(DurationText.approximate(minutes: $0)) cooking" },
            timing.sameDayWaitMinutes.map { "\(DurationText.exact(minutes: $0)) resting" }
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(Typeface.mono(9.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.leading)
        }
    }

    /// Shows required or optional make-ahead guidance.
    @ViewBuilder
    private func makeAheadNote(for recipe: SavedRecipe) -> some View {
        if let ahead = recipe.asMeal.timing.makeAhead {
            let note = prepNote(for: ahead)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: note.symbol)
                    .font(Typeface.mono(11))
                    .foregroundStyle(note.tint)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(note.headline)
                        .font(Typeface.mono(10, weight: .semibold))
                        .foregroundStyle(note.isUrgent ? Theme.brick : Theme.textDark)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\"\(ahead.phrase.trimmingCharacters(in: .whitespaces))\"")
                        .font(Typeface.mono(9))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(note.isUrgent ? Theme.brick.opacity(0.08) : Theme.paperDim.opacity(0.55))
            .accessibilityElement(children: .combine)
        }
    }

    private struct PrepNote {
        let headline: String
        let symbol: String
        let tint: Color
        let isUrgent: Bool
    }

    private func prepNote(for ahead: MakeAheadRequirement) -> PrepNote {
        let days = "\(ahead.leadDays) day\(ahead.leadDays == 1 ? "" : "s")"

        if ahead.isOptional {
            return PrepNote(
                headline: "Can be started \(days) ahead",
                symbol: "clock.arrow.circlepath", tint: Theme.sage, isUrgent: false
            )
        }

        switch PrepSchedule.status(mealDate: selectedDate, leadDays: ahead.leadDays) {
        case .upcoming(let start):
            return PrepNote(
                headline: "Start \(days) ahead — \(shortDate(start))",
                symbol: "exclamationmark.triangle.fill", tint: Theme.mustard, isUrgent: false
            )
        case .startsToday:
            return PrepNote(
                headline: "Start prep today — needs \(days)",
                symbol: "exclamationmark.triangle.fill", tint: Theme.mustard, isUrgent: true
            )
        case .overdue(let shouldHaveStarted):
            return PrepNote(
                headline: "Prep should have started \(shortDate(shouldHaveStarted)) — start as soon as you can",
                symbol: "exclamationmark.octagon.fill", tint: Theme.brick, isUrgent: true
            )
        case .mealInPast, .notNeeded:
            return PrepNote(
                headline: "Needed \(days) of prep ahead",
                symbol: "clock", tint: Theme.textMuted, isUrgent: false
            )
        }
    }

    /// Prep tasks due on the selected date for later meals.
    @ViewBuilder
    private var prepSection: some View {
        let tasks = prepTasks(on: selectedDate)

        if !tasks.isEmpty {
            SectionLabel(text: calendar.isDateInToday(selectedDate) ? "Prep due today" : "Prep due this day")
                .padding(.top, 22)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    if let recipe = task.recipe {
                        NavigationLink(value: recipe.asMeal) {
                            HStack(spacing: 10) {
                                Image(systemName: "timer")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.mustard)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name)
                                        .font(Typeface.serif(14))
                                        .foregroundStyle(Theme.textDark)
                                        .multilineTextAlignment(.leading)
                                    Text("for \(PrepSchedule.mealDateLabel(mealDate: task.date, viewing: selectedDate, calendar: calendar))")
                                        .font(Typeface.mono(9.5))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textMuted.opacity(0.6))
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Data

    /// Returns valid meals for a date in insertion order.
    private func plannedMeals(on date: Date) -> [PlannedMeal] {
        plannedMeals
            .filter { $0.recipe != nil && calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.plannedAt < $1.plannedAt }
    }

    private func prepTasks(on date: Date) -> [PlannedMeal] {
        let due = plannedMeals.filter { meal in
            guard meal.recipe != nil, meal.requiredLeadDays != nil else { return false }
            guard !calendar.isDate(meal.date, inSameDayAs: date) else { return false }
            return calendar.isDate(meal.prepStartDate, inSameDayAs: date)
        }
        .sorted { $0.date < $1.date }

        // One recipe batch on one date produces one reminder.
        var seen: Set<String> = []
        return due.filter { meal in
            guard let recipe = meal.recipe else { return false }
            return seen.insert("\(recipe.persistentModelID)-\(meal.date.timeIntervalSince1970)").inserted
        }
    }

    private func add(_ recipe: SavedRecipe, to date: Date) {
        withAnimation(.easeInOut(duration: 0.2)) {
            context.insert(PlannedMeal(date: date, recipe: recipe))
        }
    }

    /// Replaces a recipe without changing its order in the day.
    private func replace(_ meal: PlannedMeal, with recipe: SavedRecipe) {
        withAnimation(.easeInOut(duration: 0.2)) {
            meal.recipe = recipe
        }
    }

    private func remove(_ meal: PlannedMeal) {
        withAnimation(.easeInOut(duration: 0.2)) {
            context.delete(meal)
        }
    }

    // MARK: - Formatting

    private func headline(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func shortDate(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

#Preview {
    MealPlannerView()
        .modelContainer(PantryModelContainer.preview)
}
