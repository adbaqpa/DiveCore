import Foundation

/// Ekranda kullanılan bir rengin bileşenleri (0...1).
///
/// SwiftUI `Color` platforma bağlıdır ve test edilemez; bu yüzden palet
/// kararları RGB üçlüleri olarak çekirdekte tutulur, `DiveWatchUI` yalnızca
/// `Color(red:green:blue:)` üretir.
public struct DiveRGB: Equatable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
    }

    /// Tam siyah — OLED'de pikseller **kapatılır** (güç tüketimi sıfıra yaklaşır).
    public static let off = DiveRGB(red: 0, green: 0, blue: 0)
    /// Tam beyaz — en pahalı durum.
    public static let fullWhite = DiveRGB(red: 1, green: 1, blue: 1)

    /// 0 = tam siyah, 1 = tam beyaz (algılanan parlaklık).
    ///
    /// - Note: İnsı gözü yeşil ve maviye daha duyarlıdır; bu ağırlıklı ortalama
    ///   Apple'ın belgelediği OLED güç tüketimi sıralamasıyla (mavi > yeşil > kırmızı)
    ///   uyumludur.
    public var perceivedBrightness: Double {
        (0.30 * red + 0.59 * green + 0.11 * blue).clamped(to: 0...1)
    }

    /// Göreli OLED güç tüketimi (1.0 = tam beyaz ekran).
    ///
    /// - Note: OLED'de mavi alt piksel en pahalıdır. Kanal başına ağırlıklar
    ///   yaygın ölçümlerden türetilmiştir; **göreli** bir metriktir, mutlak
    ///   mAh değildir.
    public var oledCost: Double {
        (1.00 * red + 1.35 * green + 2.60 * blue).clamped(to: 0...5)
    }

    /// Kanal bazlı bileşim.
    public func blended(with other: DiveRGB, amount: Double) -> DiveRGB {
        let t = amount.clamped(to: 0...1)
        return DiveRGB(red: red + (other.red - red) * t,
                       green: green + (other.green - green) * t,
                       blue: blue + (other.blue - blue) * t)
    }

    /// Karartma (night shift için).
    public var dimmed: DiveRGB {
        DiveRGB(red: red * 0.55, green: green * 0.18, blue: blue * 0.12)
    }

    /// Bu renk "kırmızı ağırlıklı" mı (night mode doğrulaması için)?
    public var isRedDominant: Bool {
        red > 0.05 && green <= red * 0.4 && blue <= red * 0.3
    }
}

/// Ekran teması — **pil optimizasyonunun** görsel tarafı.
///
/// ## Neden ayrı temalar?
/// Apple Watch Ultra'da OLED ekranın en pahalı bölümü mavi ve yeşil
/// piksellerdir. Gece dalışında ayrıca kullanıcının gözü karanlığa
/// alışmış durumdadır. **Kırmızı gece modu**:
///
/// 1. Mavi/yeşil pikselleri kapatır → OLED gücü ve batarya tüketimi düşer,
/// 2. Görüşü bozmaz (kırmızı ışıkta görme eşiği en yüksektir),
/// 3. AOD'da yalnızca derinlik rakamı ve kritik uyarılar kalır.
///
/// Tema seçimi çekirdektedir (test edilebilir); `DiveWatchUI` yalnızca
/// `DiveRGB` → `Color` çevirir.
public enum DiveDisplayTheme: String, Equatable, Codable, Sendable, CaseIterable, Identifiable {
    /// Tam renkli, gündüz/etkin kullanım
    case standard
    /// Kırmızı gece modu — gece dalışı
    case nightShift
    /// AOD kırmızı mod — en düşük güç, minimum piksel
    case alwaysOnRed

    public var id: String { rawValue }

    /// Kullanıcıya gösterilen ad.
    public var title: String {
        switch self {
        case .standard: return "Standart"
        case .nightShift: return "Kırmızı Gece"
        case .alwaysOnRed: return "AOD Kırmızı"
        }
    }

    /// Kısa açıklama.
    public var detail: String {
        switch self {
        case .standard: return "Tam renk, tüm bilgiler"
        case .nightShift: return "Kırmızı tonlama, gece dalışı, pil dostu"
        case .alwaysOnRed: return "Yalnızca derinlik ve uyarı, en düşük güç"
        }
    }

    /// Kullanıcı bunu seçebilir mi? (AOD uygulama tarafından zorlanır)
    public var isUserSelectable: Bool {
        switch self {
        case .standard, .nightShift: return true
        case .alwaysOnRed: return false
        }
    }
}

/// Bir temanın sayısal özellikleri.
public struct DiveThemeSpec: Equatable, Codable, Sendable {

    public let theme: DiveDisplayTheme
    public let background: DiveRGB
    /// `DiveColorRole` → renk
    public let palette: [DiveColorRole: DiveRGB]
    /// Azami parlaklık (0...1) — AOD'da 0.6, gece modunda 0.8
    public let maximumBrightness: Double
    /// Saniye hanesi gösterilsin mi (AOD'da gizlenir)
    public let showsSeconds: Bool
    /// Pusola/maksimum derinlik gibi ikincil bilgiler gösterilsin mi
    public let showsSecondaryDetails: Bool
    /// Bilgi düzeyi banner gösterilsin mi
    public let showsInfoBanner: Bool
    /// Tema için önerilen minimum örnekleme aralığı (saniye)
    public let suggestedUpdateInterval: TimeInterval

    public init(theme: DiveDisplayTheme,
                background: DiveRGB,
                palette: [DiveColorRole: DiveRGB],
                maximumBrightness: Double,
                showsSeconds: Bool,
                showsSecondaryDetails: Bool,
                showsInfoBanner: Bool,
                suggestedUpdateInterval: TimeInterval) {
        self.theme = theme
        self.background = background
        self.palette = palette
        self.maximumBrightness = maximumBrightness
        self.showsSeconds = showsSeconds
        self.showsSecondaryDetails = showsSecondaryDetails
        self.showsInfoBanner = showsInfoBanner
        self.suggestedUpdateInterval = suggestedUpdateInterval
    }

    /// Rolün bu temadaki rengi (tanımsızsa `secondary`).
    public func color(for role: DiveColorRole) -> DiveRGB {
        palette[role] ?? palette[.secondary] ?? .off
    }

    /// Ekranın tahmini göreli güç tüketimi (0...1, 1 = tam beyaz).
    ///
    /// - Parameters:
    ///   - heroFraction: Ana rakamın kapladığı ekran oranı (0...1)
    ///   - secondaryFraction: İkincil metinlerin kapladığı oran
    public func estimatedPower(heroFraction: Double = 0.28,
                               secondaryFraction: Double = 0.10) -> Double {
        let hero = color(for: .hero).oledCost * heroFraction.clamped(to: 0...1)
        let secondary = color(for: .secondary).oledCost * secondaryFraction.clamped(to: 0...1)
        let backgroundCost = background.oledCost
        return (hero + secondary + backgroundCost).clamped(to: 0...3)
    }
}

/// Tema kataloğu.
public enum DiveThemeCatalog {

    /// Standart palet (mevcut uygulama renkleri).
    public static let standardPalette: [DiveColorRole: DiveRGB] = [
        .hero: DiveRGB(red: 1.00, green: 1.00, blue: 1.00),
        .secondary: DiveRGB(red: 0.62, green: 0.70, blue: 0.78),
        .accent: DiveRGB(red: 0.20, green: 0.80, blue: 0.95),
        .safe: DiveRGB(red: 0.20, green: 0.85, blue: 0.45),
        .caution: DiveRGB(red: 1.00, green: 0.75, blue: 0.15),
        .danger: DiveRGB(red: 1.00, green: 0.27, blue: 0.23),
        .deco: DiveRGB(red: 0.65, green: 0.45, blue: 1.00),
        .criticalBackground: DiveRGB(red: 0.45, green: 0.02, blue: 0.04)
    ]

    /// Kırmızı gece paleti — mavi/yeşil pikseller kapalı.
    ///
    /// Güvenlik renkleri de kırmızı tona çekilir: sarı (caution) ve yeşil
    /// (safe) yerine turuncu/koyu kırmızı kullanılır, böylece ekranda
    /// **yalnızca kırmızı kanal** yanar.
    public static let nightPalette: [DiveColorRole: DiveRGB] = [
        .hero: DiveRGB(red: 1.00, green: 0.12, blue: 0.06),
        .secondary: DiveRGB(red: 0.62, green: 0.10, blue: 0.05),
        .accent: DiveRGB(red: 0.95, green: 0.22, blue: 0.08),
        .safe: DiveRGB(red: 0.70, green: 0.20, blue: 0.06),
        .caution: DiveRGB(red: 1.00, green: 0.38, blue: 0.10),
        .danger: DiveRGB(red: 1.00, green: 0.05, blue: 0.03),
        .deco: DiveRGB(red: 0.85, green: 0.18, blue: 0.06),
        .criticalBackground: DiveRGB(red: 0.35, green: 0.01, blue: 0.01)
    ]

    /// AOD kırmızı paleti — daha koyu, yalnızca kritik tonlar.
    public static let alwaysOnPalette: [DiveColorRole: DiveRGB] = [
        .hero: DiveRGB(red: 0.85, green: 0.10, blue: 0.05),
        .secondary: DiveRGB(red: 0.45, green: 0.08, blue: 0.04),
        .accent: DiveRGB(red: 0.70, green: 0.14, blue: 0.06),
        .safe: DiveRGB(red: 0.55, green: 0.14, blue: 0.05),
        .caution: DiveRGB(red: 0.90, green: 0.28, blue: 0.08),
        .danger: DiveRGB(red: 1.00, green: 0.04, blue: 0.02),
        .deco: DiveRGB(red: 0.70, green: 0.12, blue: 0.05),
        .criticalBackground: DiveRGB(red: 0.30, green: 0.01, blue: 0.01)
    ]

    /// Tüm temaların özellikleri.
    public static func spec(for theme: DiveDisplayTheme) -> DiveThemeSpec {
        switch theme {
        case .standard:
            return DiveThemeSpec(theme: .standard,
                                 background: DiveRGB(red: 0.02, green: 0.06, blue: 0.10),
                                 palette: standardPalette,
                                 maximumBrightness: 1.0,
                                 showsSeconds: true,
                                 showsSecondaryDetails: true,
                                 showsInfoBanner: true,
                                 suggestedUpdateInterval: 1)
        case .nightShift:
            return DiveThemeSpec(theme: .nightShift,
                                 background: DiveRGB.off,
                                 palette: nightPalette,
                                 maximumBrightness: 0.8,
                                 showsSeconds: true,
                                 showsSecondaryDetails: true,
                                 showsInfoBanner: true,
                                 suggestedUpdateInterval: 2)
        case .alwaysOnRed:
            return DiveThemeSpec(theme: .alwaysOnRed,
                                 background: DiveRGB.off,
                                 palette: alwaysOnPalette,
                                 maximumBrightness: 0.6,
                                 showsSeconds: false,
                                 showsSecondaryDetails: false,
                                 showsInfoBanner: false,
                                 suggestedUpdateInterval: 5)
        }
    }

    /// Temel stok (GF, gaz, derin durak vb.) ayarları.
    public static let baseSettings = DiveSettings()

    /// Mevcut ayarlara göre kullanıcının seçebileceği temalar.
    ///
    /// - Note: Pil %20'nin altına düştüğünde gece modu, AOD'da AOD kırmızı
    ///   modu **zorlanır**; bu kural `EnergyManager` içinde uygulanır.
    public static func userSelectableThemes(for settings: DiveSettings) -> [DiveDisplayTheme] {
        switch settings.nightModePreference {
        case .auto:
            return [.standard, .nightShift]
        case .forced:
            return [.nightShift]
        case .off:
            return [.standard]
        }
    }
}
