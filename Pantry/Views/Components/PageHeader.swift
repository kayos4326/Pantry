import SwiftUI

/// Mono uppercase eyebrow above a serif title, per the prototype's page head.
struct PageHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(Typeface.mono(11))
                .kerning(1.3)
                .foregroundStyle(Theme.sageText)
            Text(title)
                .font(Typeface.serif(32))
                .foregroundStyle(Theme.textDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashedDivider: View {
    var body: some View {
        HorizontalLine()
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .foregroundStyle(Theme.dividerDash)
            .frame(height: 2)
    }
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Mono uppercase section label used on the detail screen.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typeface.mono(11))
            .kerning(0.9)
            .foregroundStyle(Theme.sageText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
