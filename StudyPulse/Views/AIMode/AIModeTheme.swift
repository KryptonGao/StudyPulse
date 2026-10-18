//
//  AIModeTheme.swift
//  StudyPulse
//
//  Two token sets for AI Mode (pure white-blue and warm serif). Light values
//  come from the design reference; dark values are a simple mapping so the
//  space stays readable under the system dark appearance.
//

import SwiftUI
import UIKit

struct AIModeTheme: Equatable {
    let appearance: AIModeAppearance
    let paper: Color
    let drawer: Color
    let ink: Color
    let muted: Color
    let line: Color
    let soft: Color
    let accent: Color
    let accentSoft: Color
    let userBubble: Color
    /// Design for display titles: serif in the warm set, default in the blue set.
    let titleDesign: Font.Design

    static func make(_ appearance: AIModeAppearance) -> AIModeTheme {
        switch appearance {
        case .pureBlue:
            return AIModeTheme(
                appearance: .pureBlue,
                paper: Color(light: 0xFFFFFF, dark: 0x0E0E11),
                drawer: Color(light: 0xFAFAFA, dark: 0x16161A),
                ink: Color(light: 0x101013, dark: 0xF2F2F5),
                muted: Color(light: 0x747477, dark: 0x9A9AA2),
                line: Color(light: 0xE5E5E7, dark: 0x2A2A30),
                soft: Color(light: 0xF2F2F4, dark: 0x1E1E23),
                accent: Color(light: 0x3564F4, dark: 0x6E8FFF),
                accentSoft: Color(light: 0xEDF1FF, dark: 0x1D2540),
                userBubble: Color(light: 0xF1F1F4, dark: 0x202026),
                titleDesign: .default
            )
        case .warmSerif:
            return AIModeTheme(
                appearance: .warmSerif,
                paper: Color(light: 0xFAF9F6, dark: 0x141311),
                drawer: Color(light: 0xF1F0EB, dark: 0x1B1A17),
                ink: Color(light: 0x292925, dark: 0xEFEDE6),
                muted: Color(light: 0x7C7A71, dark: 0xA19E92),
                line: Color(light: 0xE4E2DA, dark: 0x2E2C27),
                soft: Color(light: 0xEFEDE6, dark: 0x22211D),
                accent: Color(light: 0xBC7258, dark: 0xD28D72),
                accentSoft: Color(light: 0xF4E8E2, dark: 0x33241E),
                userBubble: Color(light: 0xEFEDE6, dark: 0x25241F),
                titleDesign: .serif
            )
        }
    }
}

extension Color {
    /// Light / dark pair from 0xRRGGBB values.
    nonisolated init(light: UInt32, dark: UInt32) {
        // `@Sendable`: UIKit resolves dynamic colors on the render thread, off the main actor.
        self.init(uiColor: UIColor { @Sendable traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

private struct AIModeThemeKey: EnvironmentKey {
    static let defaultValue = AIModeTheme.make(.pureBlue)
}

extension EnvironmentValues {
    var aiTheme: AIModeTheme {
        get { self[AIModeThemeKey.self] }
        set { self[AIModeThemeKey.self] = newValue }
    }
}

// MARK: - Small shared pieces

/// The brand mark: a small sprout drawn as a shape so it takes the theme accent.
struct AISproutMark: View {
    var size: CGFloat = 22
    @Environment(\.aiTheme) private var theme

    var body: some View {
        Image(systemName: "leaf.fill")
            .scaledFont(size: size * 0.8, weight: .semibold)
            .foregroundStyle(theme.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
