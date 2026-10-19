#if os(watchOS)
import SwiftUI
import DiveCore

// MARK: - Renk paleti

/// `DiveColorRole` → gerçek `Color` eşlemesi.
///
/// Kararlar çekirdekte verilir (`DiveCore`), burada yalnızca görsel karşılık
/// uygulanır. Böylece renk değişikliği tek dosyadan yönetilir ve palet
/// değişiklikleri testleri bozmaz.
public enum DivePalette {

    /// Dalış ekranı arka planı
    public static var background: Color { Color(red: 0.02, green: 0.06, blue: 0.10) }
    /// Yüzey / sığ modu arka planı (biraz daha açık)
    public static var surfaceBackground: Color { Color(red: 0.04, green: 0.10, blue: 0.15) }
    /// Kritik alarm arka planı
    public static var criticalBackground: Color { Color(red: 0.45, green: 0.02, blue: 0.04) }
    /// Panel arka planı
    public static var panel: Color { Color.white.opacity(0.08) }

    public static func color(for role: DiveColorRole) -> Color {
        switch role {
        case .hero:            return .white
        case .secondary:       return Color(red: 0.62, green: 0.70, blue: 0.78)
        case .accent:          return Color(red: 0.20, green: 0.80, blue: 0.95)
        case .safe:            return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .caution:         return Color(red: 1.00, green: 0.75, blue: 0.15)
        case .danger:          return Color(red: 1.00, green: 0.27, blue: 0.23)
        case .criticalBackground: return criticalBackground
        case .deco:            return Color(red: 0.65, green: 0.45, blue: 1.00)
        }
    }

    // MARK: - Tema (ADIM 11)

    /// `DiveRGB` → `Color`.
    public static func color(_ rgb: DiveRGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Bir rolün **tema içindeki** rengi.
    ///
    /// - Note: Gece modunda tüm renkler kırmızı tona çekilir; bu hem OLED
    ///   gücünü düşürür (mavi/yeşil pikseller kapalı) hem de gece görmesini
    ///   bozmaz.
    public static func color(for role: DiveColorRole, theme: DiveDisplayTheme) -> Color {
        switch theme {
        case .standard:
            return color(for: role)
        case .nightShift, .alwaysOnRed:
            return color(DiveThemeCatalog.spec(for: theme).color(for: role))
        }
    }

    /// Arka plan rengi (tema bazlı).
    public static func background(theme: DiveDisplayTheme) -> Color {
        color(DiveThemeCatalog.spec(for: theme).background)
    }

    /// Alarm arka planı (tema bazlı) — gece modunda koyu kırmızı.
    public static func criticalBackground(theme: DiveDisplayTheme) -> Color {
        color(for: .criticalBackground, theme: theme)
    }

    /// Tema, gece modunda mı? (pusula/gösterge süsleme kapatılır)
    public static func isNightMode(_ theme: DiveDisplayTheme) -> Bool {
        theme != .standard
    }
}

// MARK: - Tipografi

/// `DiveTextRole` → `Font` eşlemesi.
///
/// AOD'da Apple, satır sayısını ve kontrastı sınırlar; bu yüzden AOD rolü
/// daha küçük ve kalın (bold) seçilir, aksi halde metin kırpılır.
public enum DiveTypography {

    public static func font(for role: DiveTextRole) -> Font {
        switch role {
        case .hero:      return .system(size: 52, weight: .bold, design: .rounded)
        case .large:     return .system(size: 20, weight: .semibold, design: .rounded)
        case .medium:    return .system(size: 15, weight: .medium, design: .rounded)
        case .small:     return .system(size: 12, weight: .medium, design: .rounded)
        case .micro:     return .system(size: 10, weight: .semibold, design: .rounded)
        case .alwaysOn:  return .system(size: 26, weight: .bold, design: .rounded)
        }
    }
}
#endif