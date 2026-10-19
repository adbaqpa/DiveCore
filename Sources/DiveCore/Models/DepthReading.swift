import Foundation

/// Sensörden gelen tek bir derinlik/basınç örneği.
///
/// Hem gerçek cihaz (CoreMotion) hem de simülatör tarafından üretilir; bu sayede
/// uygulama katmanı kaynağın ne olduğunu bilmez.
public struct DepthReading: Equatable, Codable, Sendable {

    /// Anlık derinlik (metre, yüzeyin üstü negatif olabilir).
    public let depth: Double

    /// Mutlak ambient basınç (bar).
    public let ambientPressure: Double

    /// Yüzeydeki referans basınç (bar) — rakım/atlama düzeltmesi için.
    public let surfacePressure: Double

    /// Okumanın alındığı zaman.
    public let timestamp: Date

    /// Dalış başlangıcından itibaren geçen süre (saniye).
    public let elapsed: TimeInterval

    /// Su sıcaklığı (°C) — yalnızca termoklin ölçümü olan kaynaklar doldurur.
    public let temperature: Double?

    /// Okuma simülasyondan mı geliyor?
    public let isSimulated: Bool

    // MARK: - Oluşturucular

    public init(
        depth: Double,
        ambientPressure: Double? = nil,
        surfacePressure: Double = DivePhysics.surfacePressure,
        timestamp: Date,
        elapsed: TimeInterval,
        temperature: Double? = nil,
        isSimulated: Bool = false,
        water: DivePhysics.WaterType = .salt
    ) {
        self.depth = depth
        self.surfacePressure = surfacePressure
        self.ambientPressure = ambientPressure
            ?? DivePhysics.ambientPressure(depthMeters: depth, water: water)
        self.timestamp = timestamp
        self.elapsed = elapsed
        self.temperature = temperature
        self.isSimulated = isSimulated
    }

    // MARK: - Türetilmiş

    /// Yüzeyde mi (emniyet toleransı dahil)?
    public var isAtSurface: Bool { depth <= 0.3 }

    /// Suda mı?
    public var isUnderwater: Bool { depth > 0.3 }

    /// Yüzey referansına göre derinlik farkı (bar) — CoreMotion'un göreli
    /// basınç çıktısını mutlak derinliğe çevirmek için kullanılır.
    public var pressureDelta: Double { ambientPressure - surfacePressure }

    /// Derinlik iki okuma arasında değiştiyse hız hesabı için kullanılır.
    public func depthChange(since previous: DepthReading) -> Double {
        depth - previous.depth
    }

    /// İki okuma arasındaki ortalama dikey hız.
    ///
    /// - Returns: m/dk, **pozitif = yukarı (çıkış)**, negatif = aşağı (iniş).
    public func verticalSpeed(since previous: DepthReading) -> Double {
        let dt = elapsed - previous.elapsed
        guard dt > 0 else { return 0 }
        return (previous.depth - depth) / dt * 60.0
    }
}

/// Örnek başına saniyede okuma sayısı.
public enum DepthSampleRate {
    /// Canlı dalış için önerilen: 1 Hz.
    public static let live: Double = 1.0
    /// Yüksek çözünürlüklü (kısa süreli tavan olayları için): 4 Hz.
    public static let high: Double = 4.0
    /// Profil kaydı için yeterli: 0.1 Hz.
    public static let logging: Double = 0.1

    /// Saniyelik örnekleme aralığına çevirir.
    public static func interval(for rate: Double) -> TimeInterval {
        guard rate > 0 else { return 1 }
        return 1.0 / rate
    }
}