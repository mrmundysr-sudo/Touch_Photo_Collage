import SwiftUI
import UIKit

extension UIColor {
    convenience init(argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(argb: dark) : UIColor(argb: light) }
    }
}

/// The Touch Photo Collage palette, ported 1:1 from the Android Material colour schemes (warm cream light theme and
/// deep-plum dark theme). Colours resolve dynamically, so they follow light/dark mode and the in-app appearance setting.
enum Palette {
    static let uiPrimary = UIColor.dynamic(light: 0xFFD94F28, dark: 0xFFFF8A63)
    static let primary = Color(uiPrimary)
    static let onPrimary = Color(UIColor.dynamic(light: 0xFFFFFFFF, dark: 0xFF560F00))
    static let primaryContainer = Color(UIColor.dynamic(light: 0xFFFFDDD2, dark: 0xFF7A2A10))
    static let onPrimaryContainer = Color(UIColor.dynamic(light: 0xFF3B0D00, dark: 0xFFFFDDD2))
    static let secondaryContainer = Color(UIColor.dynamic(light: 0xFFC0EDE6, dark: 0xFF214E49))
    static let onSecondaryContainer = Color(UIColor.dynamic(light: 0xFF00201D, dark: 0xFFC0EDE6))
    static let background = Color(UIColor.dynamic(light: 0xFFFFFBF7, dark: 0xFF15121A))
    static let onBackground = Color(UIColor.dynamic(light: 0xFF211A17, dark: 0xFFEDE0DB))
    static let surfaceVariant = Color(UIColor.dynamic(light: 0xFFF4E6DF, dark: 0xFF3B3340))
    static let onSurfaceVariant = Color(UIColor.dynamic(light: 0xFF52443E, dark: 0xFFD6C8CE))
    static let surfaceContainer = Color(UIColor.dynamic(light: 0xFFF8EEE8, dark: 0xFF211C27))
    static let surfaceContainerHigh = Color(UIColor.dynamic(light: 0xFFF2E7E0, dark: 0xFF2B2531))
    static let outline = Color(UIColor.dynamic(light: 0xFF85746D, dark: 0xFF9E8F96))
    static let outlineVariant = Color(UIColor.dynamic(light: 0xFFD8C2B9, dark: 0xFF4B4151))
    static let error = Color(UIColor.dynamic(light: 0xFFBA1A1A, dark: 0xFFFFB4AB))

    static let coral = Color(red: 0xE8 / 255, green: 0x61 / 255, blue: 0x3C / 255)
    static let sunny = Color(red: 0xFF / 255, green: 0xC8 / 255, blue: 0x57 / 255)
    static let teal = Color(red: 0x3F / 255, green: 0xA7 / 255, blue: 0x96 / 255)
    static let violet = Color(red: 0x7B / 255, green: 0x6C / 255, blue: 0xF0 / 255)
}

extension Font {
    static let headlineLarge = Font.system(size: 32, weight: .bold, design: .serif)
    static let headlineMedium = Font.system(size: 26, weight: .bold, design: .serif)
    static let titleLarge = Font.system(size: 20, weight: .semibold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let bodyMedium = Font.system(size: 14)
    static let labelLarge = Font.system(size: 14, weight: .semibold)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
