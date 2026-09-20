import SwiftUI

@main
struct PantryApp: App {
    var body: some Scene {
        WindowGroup {
            PantryRootView()
            .preferredColorScheme(.light)
        }
    }
}
