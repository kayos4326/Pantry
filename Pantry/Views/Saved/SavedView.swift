import SwiftUI
import SwiftData

struct SavedView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRecipe.savedAt, order: .reverse) private var savedRecipes: [SavedRecipe]
    @Namespace private var cardNamespace
    @State private var recipePendingRemoval: SavedRecipe?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(eyebrow: "Local storage", title: "Saved")
                        .padding(.top, 6)

                    DashedDivider()
                        .padding(.vertical, 16)

                    if savedRecipes.isEmpty {
                        EmptyStateView(
                            symbol: "heart",
                            message: "Nothing saved yet.",
                            detail: "Tap the heart on any recipe to keep it here."
                        )
                    } else {
                        grid
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meal.self) { meal in
                RecipeDetailView(meal: meal)
                    .navigationTransition(.zoom(sourceID: meal.id, in: cardNamespace))
            }
            .confirmationDialog(
                removalTitle,
                isPresented: Binding(
                    get: { recipePendingRemoval != nil },
                    set: { if !$0 { recipePendingRemoval = nil } }
                ),
                titleVisibility: .visible,
                presenting: recipePendingRemoval
            ) { recipe in
                Button("Remove and clear from planner", role: .destructive) {
                    delete(recipe)
                }
                Button("Keep saved", role: .cancel) {}
            } message: { _ in
                Text("Removing it from Saved also removes it from those days in the Meal Planner.")
            }
        }
        // Retry missing images when the saved collection changes.
        .task(id: savedRecipes.count) {
            for recipe in savedRecipes where recipe.imageData == nil {
                await recipe.storeImageIfNeeded()
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: RecipeGrid.columns(for: typeSize), spacing: RecipeGrid.spacing) {
            ForEach(savedRecipes) { recipe in
                let meal = recipe.asMeal

                ZStack(alignment: .topTrailing) {
                    NavigationLink(value: meal) {
                        RecipeCardView(meal: meal, storedImageData: recipe.imageData)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("saved.recipeCard")
                    .matchedTransitionSource(id: meal.id, in: cardNamespace)

                    removeButton(recipe)
                        .padding(1)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        remove(recipe)
                    } label: {
                        Label("Remove from Saved", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func removeButton(_ recipe: SavedRecipe) -> some View {
        Button {
            remove(recipe)
        } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.brick)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.surface))
                .padding(7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(recipe.name) from saved")
    }

    private var removalTitle: String {
        guard let recipe = recipePendingRemoval else { return "" }
        let days = recipe.plannedDayCount
        return "\(recipe.name) is planned on \(days) day\(days == 1 ? "" : "s")"
    }

    /// Confirms before cascading an unsave into the planner.
    private func remove(_ recipe: SavedRecipe) {
        if recipe.plannedMeals.isEmpty {
            delete(recipe)
        } else {
            recipePendingRemoval = recipe
        }
    }

    private func delete(_ recipe: SavedRecipe) {
        recipePendingRemoval = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            context.delete(recipe)
        }
    }
}

#Preview {
    SavedView()
        .modelContainer(PantryModelContainer.preview)
}
