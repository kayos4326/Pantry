import SwiftUI

/// Lays children out left to right, wrapping onto a new row when the next one
/// won't fit. Keeps pill rows readable on narrow phones and at large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            // Measured against the available width rather than unconstrained,
            // so an item wider than the row wraps to a taller size instead of
            // being squeezed into its one-line height and clipped.
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let widthIfAdded = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if widthIfAdded > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

enum DurationText {
    /// "~45 min", "~1 h 35 min", "~8 h". Estimates are rounded to five
    /// minutes once they pass an hour, so they don't imply false precision.
    static func approximate(minutes: Int) -> String {
        guard minutes >= 60 else { return "~\(minutes) min" }
        let rounded = Int((Double(minutes) / 5).rounded()) * 5
        let hours = rounded / 60
        let remainder = rounded % 60
        return remainder == 0 ? "~\(hours) h" : "~\(hours) h \(remainder) min"
    }

    static func exact(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }
}
