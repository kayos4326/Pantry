import SwiftUI
import SwiftData

/// Horizontal row of recipes the user has opened before, shown at the top of
/// Browse. It reads straight from SwiftData, so it's on screen immediately at
/// launch — including with no connection, since each row keeps its own photo.
struct RecentlyViewedStrip: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecentRecipe.viewedAt, order: .reverse) private var recents: [RecentRecipe]
    @ScaledMetric(relativeTo: .body) private var itemWidth: CGFloat = 92

    var body: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "Recently viewed")
                        .accessibilityAddTraits(.isHeader)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            RecentRecipe.clear(in: context)
                        }
                    } label: {
                        Text("Clear")
                            .font(Typeface.mono(10, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            // Grow the touch target past 44 pt, claim it as the
                            // hit area, then give the space back to the layout
                            // so the label stays on the heading's baseline.
                            .padding(16)
                            .contentShape(Rectangle())
                            .padding(-16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear recently viewed")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(recents) { recent in
                            NavigationLink(value: recent.asMeal) {
                                item(recent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("browse.recentCard")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                // Bleed to the screen edges so the row scrolls out past the
                // page padding, then restore the inset, as the chip row does.
                .padding(.horizontal, -20)
            }
        }
    }

    private func item(_ recent: RecentRecipe) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipeImage(
                url: recent.gridThumbnailURL,
                storedData: recent.imageData,
                cacheKey: recent.mealID,
                maxPixelSize: 300
            )
            .frame(width: itemWidth, height: itemWidth * 0.72)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(recent.name)
                .font(Typeface.serif(12.5))
                .foregroundStyle(Theme.textDark)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: itemWidth, alignment: .leading)
    }
}
