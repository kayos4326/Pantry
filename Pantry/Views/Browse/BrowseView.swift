import SwiftUI

struct BrowseView: View {
    @State private var viewModel = BrowseViewModel()
    @Namespace private var cardNamespace
    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(eyebrow: "Pantry", title: "Browse")
                        .padding(.top, 6)

                    searchField
                        .padding(.top, 16)

                    chipRow
                        .padding(.top, 12)

                    if viewModel.currentRequest == .defaultFeed {
                        RecentlyViewedStrip()
                            .padding(.top, 18)
                    }

                    DashedDivider()
                        .padding(.vertical, 16)

                    if let offline = offlineCopy {
                        OfflineNotice(storedAt: offline.storedAt, isDisconnected: offline.isDisconnected) {
                            Task { await viewModel.retry() }
                        }
                        .padding(.bottom, 14)
                    }

                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Theme.paper)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await viewModel.refresh()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meal.self) { meal in
                RecipeDetailView(meal: meal)
                    .navigationTransition(.zoom(sourceID: meal.id, in: cardNamespace))
            }
        }
        .task {
            await viewModel.loadCategories()
        }
        .task(id: viewModel.requestKey) {
            await viewModel.loadForCurrentInputs()
        }
    }

    /// Metadata for results restored from disk.
    private var offlineCopy: BrowseViewModel.OfflineCopy? {
        if case .loaded(_, let offline) = viewModel.state { return offline }
        return nil
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Typeface.sans(14))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)

            TextField("Search recipes…", text: $viewModel.searchText)
                .font(Typeface.sans(14))
                .foregroundStyle(Theme.textDark)
                .tint(Theme.brick)
                .submitLabel(.search)
                .accessibilityIdentifier("browse.search")
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                // Prevents Inter's ascenders from clipping.
                .frame(minHeight: 28)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textMuted.opacity(0.7))
                        .padding(14)
                        .contentShape(Rectangle())
                        .padding(-14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.paperDim, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.searchText.isEmpty)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(title: "All", isSelected: viewModel.selectedCategory == nil) {
                    searchFocused = false
                    viewModel.select(category: nil)
                }

                ForEach(viewModel.categories) { category in
                    CategoryChip(
                        title: category.name,
                        isSelected: viewModel.selectedCategory == category.name
                    ) {
                        searchFocused = false
                        viewModel.select(category: category.name)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        // Allows chips to scroll through the page margins.
        .padding(.horizontal, -20)
        .padding(.vertical, -8)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LazyVGrid(columns: RecipeGrid.columns(for: typeSize), spacing: RecipeGrid.spacing) {
                ForEach(0..<6, id: \.self) { _ in
                    RecipeCardSkeleton()
                }
            }

        case .loaded(let meals, _):
            LazyVGrid(columns: RecipeGrid.columns(for: typeSize), spacing: RecipeGrid.spacing) {
                ForEach(meals) { meal in
                    NavigationLink(value: meal) {
                        RecipeCardView(meal: meal, categoryFallback: viewModel.selectedCategory)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browse.recipeCard")
                    .matchedTransitionSource(id: meal.id, in: cardNamespace)
                }
            }

        case .empty(let message):
            EmptyStateView(
                symbol: "magnifyingglass",
                message: message,
                detail: "Try another search or category."
            )

        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.retry() }
            }
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.mono(11.5, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.textDark)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(isSelected ? Theme.brick : .clear)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? Theme.brick : Theme.textDark, lineWidth: 1)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

#Preview {
    BrowseView()
        .modelContainer(PantryModelContainer.preview)
}
