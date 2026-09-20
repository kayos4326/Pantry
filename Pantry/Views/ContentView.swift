import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Browse", systemImage: "fork.knife") {
                BrowseView()
            }
            Tab("Saved", systemImage: "heart.fill") {
                SavedView()
            }
            Tab("Planner", systemImage: "calendar") {
                MealPlannerView()
            }
        }
        .tint(Theme.brick)
    }
}

#Preview {
    ContentView()
        .modelContainer(PantryModelContainer.preview)
}
