import SwiftUI

/// Horizontally scrolling calendar covering the planning window.
struct DateStrip: View {
    let dates: [Date]
    @Binding var selection: Date
    let marker: (Date) -> DayMarker

    private let calendar = Calendar.current
    /// Grows with Dynamic Type so the weekday and date never overflow the pill.
    @ScaledMetric(relativeTo: .body) private var pillWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 6

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dates, id: \.self) { date in
                        dayPill(date)
                            .id(date)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }

    private func dayPill(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let markers = marker(date)

        return Button {
            selection = date
        } label: {
            VStack(spacing: 3) {
                Text(weekdayText(date))
                    .font(Typeface.mono(10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.textMuted)

                Text(dayNumber(date))
                    .font(Typeface.serif(20))
                    .foregroundStyle(isSelected ? .white : Theme.textDark)

                HStack(spacing: 3) {
                    if markers.hasMeal {
                        // On the brick selected pill, white keeps it visible.
                        Circle().fill(isSelected ? .white : Theme.brick)
                            .frame(width: dotSize, height: dotSize)
                    }
                    if markers.hasPrep {
                        Circle().fill(Theme.mustard)
                            .frame(width: dotSize, height: dotSize)
                    }
                }
                .frame(height: dotSize)
            }
            .lineLimit(1)
            .frame(width: pillWidth)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 15)
                    .fill(isSelected ? Theme.brick : Theme.paperDim.opacity(0.55))
            }
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Theme.brick.opacity(0.45), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(accessibilityText(date, markers: markers, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func weekdayText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }

    private func accessibilityText(_ date: Date, markers: DayMarker, isToday: Bool) -> String {
        var text = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if isToday { text = "Today, " + text }
        if markers.hasMeal { text += ", meal planned" }
        if markers.hasPrep { text += ", prep due" }
        return text
    }
}
