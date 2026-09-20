import SwiftUI
import SwiftData

@main
struct PantryApp: App {
    private let storage = PantryModelContainer.makeShared()

    var body: some Scene {
        WindowGroup {
            Group {
                switch storage {
                case .success(let container):
                    ContentView()
                        .modelContainer(container)

                case .failure:
                    StorageUnavailableView()
                }
            }
            // The palette is a fixed warm-paper design with explicit colours,
            // so the system chrome is pinned to light to match.
            .preferredColorScheme(.light)
        }
    }
}

/// A store-opening problem must not look like an empty collection: that could
/// encourage the user to recreate data in a temporary store. This screen makes
/// it explicit that the existing recipes and plans have been left untouched.
private struct StorageUnavailableView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.brick)
                .accessibilityHidden(true)

            Text("Pantry couldn't open your saved data")
                .font(Typeface.serif(25))
                .foregroundStyle(Theme.textDark)
                .multilineTextAlignment(.center)

            Text("Your recipes and meal plans are still on this device. Close and reopen Pantry. If the problem continues, restart the device and try again.")
                .font(Typeface.sans(14))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
