import Foundation

/// Basınç / derinlik dönüşümleri ve ortam fiziği sabitleri.
///
/// Tüm basınç değerleri **bar (mutlak atmosfer basıncı)** cinsindendir.
/// Derinlikler **metre (m, deniz seviyesi)** cinsindendir.
public enum DivePhysics {

    // MARK: - Basınç sabitleri

    /// Yüzeydeki mutlak atmosfer basıncı (bar).
    public static let surfacePressure: Double = 1.0

    /// Havadaki azot oranı (EAN referansı).
    public static let nitrogenFractionOfAir: Double = 0.79

    /// Solunum yolundaki su buharı basıncı (Schreiner yaklaşımı, bar).
    /// Vücut sıcaklığında (37 °C) yaklaşık 0.0627 bar.
    public static let waterVaporPressure: Double = 0.0627

    // MARK: - Su tipi

    public enum WaterType: String, Codable, Sendable, CaseIterable {
        case salt
        case fresh

        /// 1 bar basınç artışına karşılık gelen derinlik (m).
        /// Deniz suyu için 10.0 m/bar, tatlı su için yaklaşık 10.33 m/bar.
        public var metersPerBar: Double {
            switch self {
            case .salt: return 10.0
            case .fresh: return 10.33
            }
        }

        /// Bir bar basınçın metre cinsinden karşılığı (derinlik = bar * m/bar).
        public var barPerMeter: Double { 1.0 / metersPerBar }
    }

    // MARK: - Dönüşümler

    /// Derinlik (m) -> mutlak ambient basınç (bar).
    public static func ambientPressure(depthMeters depth: Double, water: WaterType = .salt) -> Double {
        guard depth > 0 else { return surfacePressure }
        return surfacePressure + depth * water.barPerMeter
    }

    /// Mutlak ambient basınç (bar) -> derinlik (m). Yüzeyin üstünde negatif döner.
    public static func depthMeters(ambientPressure pressure: Double, water: WaterType = .salt) -> Double {
        (pressure - surfacePressure) * water.metersPerBar
    }

    /// Alveoler solunumdaki nitrojen basıncı (bar) = (Pamb - PH2O) * fN2
    ///
    /// - Not: Bu "inspired/alveolar" basınç Bühlmann doku yüklenmesinde kullanılır.
    public static func alveolarNitrogenPressure(
        ambientPressure: Double,
        nitrogenFraction: Double,
        waterVapor: Double = DivePhysics.waterVaporPressure
    ) -> Double {
        partialPressure(ambientPressure: ambientPressure,
                        fraction: nitrogenFraction,
                        waterVapor: waterVapor)
    }

    /// Gaz bileşeninin solunan (alveoler) kısmi basıncı.
    ///
    /// Px = (Pamb - PH2O) * fx
    public static func partialPressure(
        ambientPressure: Double,
        fraction: Double,
        waterVapor: Double = DivePhysics.waterVaporPressure
    ) -> Double {
        max(0, ambientPressure - waterVapor) * max(0, fraction)
    }

    /// Solunan karbondioksit basıncı (bar) — Schreiner denkleminde kullanılır.
    public static let carbonDioxidePressure: Double = 0.0627

    // MARK: - Yüzdeler

    /// Yüzde (0...100) -> oran (0...1).
    public static func fraction(fromPercent percent: Double) -> Double { percent / 100.0 }

    /// Oran (0...1) -> yüzde (0...100).
    public static func percent(fromFraction fraction: Double) -> Double { fraction * 100.0 }
}