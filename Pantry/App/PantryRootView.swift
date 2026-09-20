import SwiftData
import SwiftUI

/// Opens the persistent store and lets the user retry a failure.
struct PantryRootView: View {
    @State private var storage: Result<ModelContainer, Error>

    init(storage: Result<ModelContainer, Error> = PantryModelContainer.makeShared()) {
        _storage = State(initialValue: storage)
    }

    var body: some View {
        switch storage {
        case .success(let container):
            ContentView()
                .modelContainer(container)

        case .failure:
            StorageUnavailableView(retry: openStore)
        }
    }

    private func openStore() {
        storage = PantryModelContainer.makeShared()
    }
}

/// Explains that a store-opening failure did not remove existing data.
private struct StorageUnavailableView: View {
    let retry: () -> Void

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

            Text("Your recipes and meal plans are still on this device. Try again, or restart the device if the problem continues.")
                .font(Typeface.sans(14))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again", action: retry)
                .font(Typeface.mono(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.brick))
                .buttonStyle(.plain)
                .padding(.top, 4)
        }
        .frame(maxWidth: 460)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
