import SwiftUI

/// Palette and type scale lifted from the HTML prototype. Every colour and
/// font in the app routes through here, so restyling means editing this file
/// rather than hunting through views.
enum Theme {
    static let charcoal = Color(hex: 0x211C1A)
    static let paper = Color(hex: 0xFAF3E4)
    static let paperDim = Color(hex: 0xEFE4CC)
    static let textDark = Color(hex: 0x231B14)
    /// Darkened from the prototype's #7A6F5C (4.47:1 on paper) to clear
    /// WCAG AA's 4.5:1 for small text; visually almost identical.
    static let textMuted = Color(hex: 0x6B604E)
    static let mustard = Color(hex: 0xD9A441)
    static let sage = Color(hex: 0x6B8F71)
    static let brick = Color(hex: 0xA63D2F)

    /// Sage and mustard are kept for dots, checkboxes and icons, where 3:1 is
    /// enough. As text they measured 3.3:1 and 2.3:1, so text uses these.
    static let sageText = Color(hex: 0x4F6E55)
    static let mustardText = Color(hex: 0x8A6414)

    static let surface = Color.white
    static let dividerDash = Color(hex: 0xD9CCA3)

    /// Warm placeholder behind recipe photos while they load or when missing.
    static let photoPlaceholder = LinearGradient(
        colors: [Color(hex: 0xF4E6C8), Color(hex: 0xE7D6AB)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The prototype's three faces, all bundled under the OFL: DM Serif Display
/// for display text, IBM Plex Mono for labels and Inter for reading text.
/// Every style scales with Dynamic Type. `Font.custom` falls back to the
/// system font if a family ever fails to register, so text never disappears.
enum Typeface {
    private enum Family {
        static let serif = "DMSerifDisplay-Regular"
        static let mono = "IBMPlexMono-Regular"
        static let monoSemibold = "IBMPlexMono-SemiBold"
        static let monoBold = "IBMPlexMono-Bold"
        static let sans = "Inter-Regular"
        static let sansMedium = "Inter-Medium"
        static let sansSemibold = "Inter-SemiBold"
    }

    /// Custom fonts scale with the text style they're tied to. Tying a 32 pt
    /// title to `.body` made it grow ~3× at the largest accessibility size;
    /// display sizes follow the gentler title curves instead, while the text
    /// people actually read keeps the full body-rate growth.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 28...: return .largeTitle
        case 20..<28: return .title2
        case 15..<20: return .title3
        case 12..<15: return .body
        default: return .footnote
        }
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // DM Serif Display ships a single weight; heavier requests keep the
        // same face rather than letting the system synthesise a fake bold.
        .custom(Family.serif, size: size, relativeTo: textStyle(for: size))
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let family: String
        switch weight {
        case .bold, .heavy, .black: family = Family.monoBold
        case .semibold, .medium: family = Family.monoSemibold
        default: family = Family.mono
        }
        return .custom(family, size: size, relativeTo: textStyle(for: size))
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family: String
        switch weight {
        case .semibold, .bold, .heavy, .black: family = Family.sansSemibold
        case .medium: family = Family.sansMedium
        default: family = Family.sans
        }
        return .custom(family, size: size, relativeTo: textStyle(for: size))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
