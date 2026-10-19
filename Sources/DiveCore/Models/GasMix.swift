import Foundation

/// Bir dalıştaki nefes gazı karışımı.
///
/// - `oxygenFraction`: O2 oranı. Suda solunabilen minimum %21 (EAN21),
///   maksimum %100 (saf oksijen / OBOE).
/// - `heliumFraction`: He oranı. Trimix için ayrılmıştır; varsayılan 0.
/// - `nitrogenFraction`: Kalan pay (1 - O2 - He), türetilmiş.
public struct GasMix: Equatable, Hashable, Codable, Sendable {

    /// Oksijen oranı (0.21 ... 1.0)
    public let oxygenFraction: Double

    /// Heliyum oranı (0.0 ... 0.79), varsayılan 0
    public let heliumFraction: Double

    /// Nitrojen oranı — daima `1 - O2 - He`.
    public var nitrogenFraction: Double { 1.0 - oxygenFraction - heliumFraction }

    // MARK: - Oluşturucular

    /// Oksijen **oranı** ile oluşturur.
    ///
    /// - Oksijen oranı minimum %21'e (EAN21), maksimum %100'e sınırlanır.
    /// - Heliyum oranı, kalan payı aşamayacak şekilde sınırlanır.
    public init(oxygenFraction: Double, heliumFraction: Double = 0.0) {
        let o2 = oxygenFraction.clamped(to: 0.21...1.0)
        self.oxygenFraction = o2
        let maxHelium = max(0.0, 1.0 - o2)
        self.heliumFraction = max(0.0, heliumFraction).clamped(to: 0.0...maxHelium)
    }

    /// Oksijen **yüzdesi** ile oluşturur (21 ... 100).
    public init(oxygenPercent: Double, heliumPercent: Double = 0.0) {
        self.init(oxygenFraction: DivePhysics.fraction(fromPercent: oxygenPercent),
                  heliumFraction: DivePhysics.fraction(fromPercent: heliumPercent))
    }

    /// "EAN32" gibi etiketlerden parse eder.
    public init?(label: String) {
        let cleaned = label.uppercased()
            .replacingOccurrences(of: "EAN", with: "")
            .replacingOccurrences(of: "O2", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), (21.0...100.0).contains(value) else { return nil }
        self.init(oxygenPercent: value)
    }

    // MARK: - Yaygın gazlar

    /// Hava (Air) — %21 O2
    public static let air = GasMix(oxygenFraction: 0.21)

    /// EAN32
    public static let ean32 = GasMix(oxygenFraction: 0.32)

    /// EAN36
    public static let ean36 = GasMix(oxygenFraction: 0.36)

    /// Saf oksijen (O2) — dekompresyon durakları için
    public static let oxygen = GasMix(oxygenFraction: 1.0)

    // MARK: - Türetilmiş değerler

    /// Gaz etiketi: Air / EAN32 / O2
    public var label: String {
        let o2Percent = Int((oxygenFraction * 100).rounded())
        if heliumFraction > 0.001 {
            let hePercent = Int((heliumFraction * 100).rounded())
            return "O\(o2Percent)/He\(hePercent)"
        }
        if abs(oxygenFraction - 0.21) < 0.0001 { return "Air" }
        if abs(oxygenFraction - 1.0) < 0.0001 { return "O₂" }
        return "EAN\(o2Percent)"
    }

    /// Bu gazla, verilen derinlikte solunan oksijenin basıncı (PO2, bar).
    ///
    /// PO2 = (Pamb - PH2O) * fO2
    public func oxygenPartialPressure(atDepth depth: Double, water: DivePhysics.WaterType = .salt) -> Double {
        let pAmb = DivePhysics.ambientPressure(depthMeters: depth, water: water)
        return DivePhysics.partialPressure(ambientPressure: pAmb, fraction: oxygenFraction)
    }

    /// Maksimum çalışma derinliği (MOD) — PO2 1.4 bar sınırı için (metre).
    public func maximumOperatingDepth(
        maxPO2: Double = DiveSafetyLimits.maximumPO2,
        water: DivePhysics.WaterType = .salt
    ) -> Double {
        guard oxygenFraction > 0 else { return 0 }
        let pAmbAtLimit = DivePhysics.waterVaporPressure + maxPO2 / oxygenFraction
        return DivePhysics.depthMeters(ambientPressure: pAmbAtLimit, water: water)
    }

    /// Endonezyal derinlik limiti (EDD, "afx" — endo) — PO2 1.4 bar.
    public var endoDepth: Double { maximumOperatingDepth(maxPO2: 1.4) }
}

// MARK: - Yardımcı

extension Double {
    /// Değeri verilen kapalı aralığa sınırlar.
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    /// Değeri verilen kapalı aralığa sınırlar.
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Dalış güvenliği sınırları (varsayılanlar; kullanıcı ayarıyla değiştirilebilir).
public enum DiveSafetyLimits {
    /// Azami oksijen basıncı (bar)
    public static let maximumPO2: Double = 1.4

    /// Uyarı eşiği (%80)
    public static let oxygenWarningPercent: Double = 80.0

    /// İzin verilen azami çıkış hızı (m/dk)
    public static let maximumAscentRate: Double = 10.0

    /// Dikkat çıkış hızı eşiği (m/dk) — sarı uyarı
    public static let cautionAscentRate: Double = 7.0

    /// Önerilen (hedef) çıkış hızı (m/dk) — planların ve uyarıların dayanağı
    public static let recommendedAscentRate: Double = 9.0

    /// Azami iniş hızı (m/dk) — PADI RDP 75 ft/dk ≈ 23 m/dk
    public static let maximumDescentRate: Double = 23.0

    /// Emniyet durağı derinliği (m)
    public static let safetyStopDepth: Double = 3.0

    /// Emniyet durağı süresi (saniye)
    public static let safetyStopDuration: TimeInterval = 180

    /// Dekompresyon durağı ızgarası (m)
    public static let decoStopInterval: Double = 3.0
}