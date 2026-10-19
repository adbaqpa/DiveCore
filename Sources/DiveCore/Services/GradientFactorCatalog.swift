import Foundation

/// GF ayar kataloğu — kullanıcıya sunulabilir ön ayarlar.
///
/// Kullanıcı dalış öncesi ekrandan bunlardan birini seçer veya **custom**
/// (Low/High kaydırıcıları) değer girer. Öneriler dalış derinliği/süresi ve
/// deneyim düzeyine göre üretilir.
public enum GradientFactorCatalog {

    /// Kullanıcıya gösterilen tek bir ön ayar.
    public struct Preset: Identifiable, Equatable, Sendable {
        public let id: String
        public let factors: GradientFactors
        /// Kısa ad ("Konservatif")
        public let name: String
        /// Bir cümle açıklama
        public let summary: String
        /// Kimler için: `.beginner`, `.recreational`, `.deep`, `.technical`
        public let audience: Audience
        /// Tavsiye edilen azami dalış derinliği (m)
        public let suggestedMaxDepth: Double

        public enum Audience: String, Equatable, Sendable {
            case beginner
            case recreational
            case deep
            case technical
        }

        public var factorsText: String { "\(factors.low)/\(factors.high)" }
    }

    /// Tüm ön ayarlar (ekranda listelenen sıra).
    public static let presets: [Preset] = [
        Preset(id: "ufuk", factors: .conservative, name: "Konservatif",
               summary: "En güvenli seçenek; daha fazla durağa kısa deko yapar.",
               audience: .beginner, suggestedMaxDepth: 24),
        Preset(id: "balanced", factors: .balanced, name: "Dengeli",
               summary: "30–40 m arası rekreasyonel dalışlar için en yaygın seçim.",
               audience: .recreational, suggestedMaxDepth: 40),
        Preset(id: "relaxed", factors: .relaxed, name: "Gevşek",
               summary: "Daha az deko, daha uzun dalış; deneyimli dalgıçlar için.",
               audience: .recreational, suggestedMaxDepth: 40),
        Preset(id: "deep", factors: .moderate, name: "Derin",
               summary: "40–60 m derin dalışlar; daha kısa NDL, daha güvenli tavan.",
               audience: .deep, suggestedMaxDepth: 60),
        Preset(id: "technical", factors: .technical, name: "Teknik",
               summary: "Trimix/derin deko dalışları; en muhafazakâr profil.",
               audience: .technical, suggestedMaxDepth: 100),
        Preset(id: "reference", factors: .default, name: "Referans",
               summary: "Saf matematiksel — yalnızca doğrulama ve eğitim için.",
               audience: .technical, suggestedMaxDepth: 100)
    ]

    /// Kimliğe göre ön ayar.
    public static func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    /// Değerlere en yakın ön ayar (özel değerler için etiket bulmak için).
    public static func closestPreset(to factors: GradientFactors) -> Preset {
        presets.min { lhs, rhs in
            let left = distance(from: factors, to: lhs.factors)
            let right = distance(from: factors, to: rhs.factors)
            return left < right
        } ?? presets[0]
    }

    private static func distance(from lhs: GradientFactors, to rhs: GradientFactors) -> Int {
        abs(lhs.low - rhs.low) + abs(lhs.high - rhs.high)
    }

    /// Derinlik ve süreye göre önerilen ön ayar.
    ///
    /// - Parameters:
    ///   - maxDepth: Planlanan azami derinlik (m)
    ///   - duration: Planlanan süre (saniye)
    ///   - experience: `.beginner` / `.experienced` / `.technical`
    public static func recommended(maxDepth: Double,
                                  duration: TimeInterval,
                                  experience: Experience = .experienced) -> Preset {
        if experience == .technical || maxDepth > 60 {
            return preset(id: "technical")!
        }
        if experience == .beginner || maxDepth <= 18 {
            return preset(id: "ufuk")!
        }
        if maxDepth <= 30 {
            // 30 m sınırında kısa dalış: gevşek, uzun dalış: dengeli
            return duration <= 25 * 60 ? preset(id: "relaxed")! : preset(id: "balanced")!
        }
        return preset(id: "deep")!
    }

    public enum Experience: String, Equatable, Codable, Sendable, CaseIterable {
        case beginner
        case experienced
        case technical
    }

    /// GF aralığının "genişliği" (0 = tek değer, 100 = çok esnek).
    public static func spread(of factors: GradientFactors) -> Int {
        factors.high - factors.low
    }

    /// GF değerleri geçerli mi (low ≤ high, 10...100)?
    public static func isValid(low: Int, high: Int) -> Bool {
        GradientFactors.validated(low: low, high: high) != nil
    }

    /// Kaydırıcı aralığı (UI için).
    public static let allowedRange: ClosedRange<Int> = 10...100
}

extension GradientFactors {
    /// **75/85** — kullanıcı talebindeki "konservatif" yeni muhafazakâr profil.
    public static let balanced = GradientFactors(low: 75, high: 85)

    /// **90/90** — kullanıcı talebindeki "agresif" gevşek profil.
    public static let relaxed = GradientFactors(low: 90, high: 90)

    /// Aynı değer mi (GF Low == GF High)?
    public var isUniform: Bool { low == high }

    /// Kullanıcıya gösterilecek "75/85" metni.
    public var displayText: String { "\(low)/\(high)" }
}