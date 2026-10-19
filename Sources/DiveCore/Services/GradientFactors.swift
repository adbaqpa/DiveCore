import Foundation

/// Bühlmann **Gradient Factors** — GF Low / GF High ayarı.
///
/// Derinliğe göre lineer interpolasyon kullanılır:
/// yüzeyde `high`, dalışın maksimum derinliğinde `low` geçerlidir.
///
/// - `low`  düşük değerler daha muhafazakârdır (daha fazla dekompresyon durağı, daha kısa uçuş yasağı).
/// - `high` yüksek değerler daha "yumuşak" (daha az durak, daha uzun dekompresyon) sonuç verir.
///
/// Tipik aralıkler:
/// - `30/75`  – çok muhafazakâkar (aşırı derin, uzun dalışlar)
/// - `50/80`  – 30-45 m derinliklerde tercih edilir
/// - `80/85`  – geleneksel 30 m sınırı kullanıcıları için popüler
/// - `100/100` – saf matematiksel (doğrulama/test amaçlı)
public struct GradientFactors: Equatable, Hashable, Codable, Sendable, Comparable {

    /// GF Low (10...100). Daha küçük = daha muhafazakâr.
    public let low: Int

    /// GF High (10...100). `low`'dan büyük olmalıdır.
    public let high: Int

    public init(low: Int, high: Int) {
        let l = low.clamped(to: 10...100)
        let h = high.clamped(to: 10...100)
        // low > high olmasın
        self.low = min(l, h)
        self.high = max(l, h)
    }

    /// Yalnızca tek bir GF değeri (low == high).
    public init(uniform value: Int) {
        let v = value.clamped(to: 10...100)
        self.low = v
        self.high = v
    }

    // MARK: - Hazır ayarlar

    public static let `default` = GradientFactors(low: 100, high: 100)      // matematiksel referans
    public static let conservative = GradientFactors(low: 80, high: 85)      // 30 m sınırı için popüler
    public static let moderate = GradientFactors(low: 50, high: 80)         // 30-45 m sınırı
    public static let aggressive = GradientFactors(low: 30, high: 75)       // çok derin / uzun dalış
    public static let technical = GradientFactors(low: 30, high: 70)        // trimix/teknik dalış

    // MARK: - Hesap

    /// Derinlik oranına göre GF değerini (0...1) döndürür.
    ///
    /// - Parameters:
    ///   - depth: Mevcut derinlik (m)
    ///   - maxDepth: Dalışın maksimum derinliği (m)
    public func value(atDepth depth: Double, maxDepth: Double) -> Double {
        let lowValue = Double(low) / 100.0
        let highValue = Double(high) / 100.0

        guard maxDepth > 0.5 else { return highValue }
        let fraction = (depth / maxDepth).clamped(to: 0...1)
        return highValue + (lowValue - highValue) * fraction
    }

    /// Yüzeydeki GF değeri.
    public var surfaceValue: Double { Double(high) / 100.0 }

    /// Maksimum derinlikteki GF değeri.
    public var deepValue: Double { Double(low) / 100.0 }

    /// Ayarlanabilir aralık dışına çıkarsa `nil` döner (UI doğrulaması için).
    public static func validated(low: Int, high: Int) -> GradientFactors? {
        guard (10...100).contains(low), (10...100).contains(high), low <= high else { return nil }
        return GradientFactors(low: low, high: high)
    }

    public static func < (lhs: GradientFactors, rhs: GradientFactors) -> Bool {
        lhs.low != rhs.low ? lhs.low < rhs.low : lhs.high < rhs.high
    }
}

// MARK: - Codable (Int olarak saklanır)

extension GradientFactors: CustomStringConvertible {
    public var description: String { "\(low)/\(high)" }
}