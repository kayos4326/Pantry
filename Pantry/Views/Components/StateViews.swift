import SwiftUI

/// Centred message used for "nothing saved yet" / "no results" style states.
struct EmptyStateView: View {
    let symbol: String
    let message: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(Theme.textMuted)
            Text(message)
                .font(Typeface.mono(12.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(Typeface.mono(12.5))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }
}

/// Sits above results that came from the copy on disk because the request
/// failed, so recipes that may be out of date are never passed off as fresh.
struct OfflineNotice: View {
    let storedAt: Date
    /// Distinguishes "no connection" from a server that answered badly; the
    /// fallback is the same either way, only the wording changes.
    let isDisconnected: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isDisconnected ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.mustardText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(isDisconnected ? "You're offline" : "Couldn't reach TheMealDB")
                    .font(Typeface.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textDark)
                // Not "saved": that word means favourited everywhere else in
                // the app, and these recipes haven't been.
                Text("Showing recipes from \(storedAt.formatted(.relative(presentation: .named))).")
                    .font(Typeface.mono(10))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button(action: retry) {
                Text("Retry")
                    .font(Typeface.mono(10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.brick))
                    // 44 pt touch target; the capsule itself stays small.
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.mustard.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.mustard.opacity(0.55), lineWidth: 1)
        }
    }
}

/// Error state with a retry affordance, used whenever a request fails.
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.brick)
            Text(message)
                .font(Typeface.mono(12.5))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Text("Try again")
                    .font(Typeface.mono(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.brick))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
        .padding(.horizontal, 24)
    }
}
