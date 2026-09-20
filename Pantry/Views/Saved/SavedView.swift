import SwiftUI
import SwiftData

struct SavedView: View {
    @Environment(\.modelContext) private var context
    // Reading SwiftData straight from the view is what keeps the grid in sync
    // automatically; wrapping @Query in a view model would break that.
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
        // Recipes saved while offline, or before photos were stored, pick up
        // their image the next time the tab is shown with a connection.
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

                    // Sibling of the link rather than nested inside it, so the
                    // tap targets don't fight each other.
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
                // 44 pt touch target; the visible circle stays 30 pt.
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

    /// Unsaving cascades to the planner, so a recipe that's planned asks first.
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
