import Foundation

/// Dalışta işaretlenen bir olay (yer imi, gaz değişimi, emniyet durağı...).
public struct DiveMarker: Codable, Equatable, Sendable, Identifiable {

    public enum Kind: String, Codable, Equatable, Sendable {
        /// Kullanıcı yer imi (Action Button)
        case marker = "marker"
        /// Gaz değişikliği
        case gasChange = "gasChange"
        /// Emniyet durağına giriş
        case safetyStopStart = "safetyStopStart"
        /// Emniyet durağının tamamlanması
        case safetyStopComplete = "safetyStopComplete"
        /// Deko durağına giriş
        case decoStop = "decoStop"
        /// Dalış sonu
        case end = "end"
        /// Uyarı anı
        case alarm = "alarm"
    }

    public let id: UUID
    public let kind: Kind
    public let elapsed: TimeInterval
    public let depth: Double
    public let timestamp: Date
    public let label: String

    public init(id: UUID = UUID(),
                kind: Kind,
                elapsed: TimeInterval,
                depth: Double,
                timestamp: Date,
                label: String) {
        self.id = id
        self.kind = kind
        self.elapsed = elapsed
        self.depth = depth
        self.timestamp = timestamp
        self.label = label
    }
}

/// Dalış oturumu yapılandırması.
public struct DiveConfiguration: Equatable, Sendable {

    public var water: DivePhysics.WaterType
    public var gradientFactors: GradientFactors

    /// Silindirdeki gazlar (geçişler dahil)
    public var gases: [GasMix]
    /// Başlangıç gazının indeksi
    public var startGasIndex: Int

    /// Azami oksijen basıncı (bar)
    public var maxPO2: Double
    /// Uyarı eşiği olarak kullanılacak CNS/OTU yüzdesi
    public var oxygenWarningPercent: Double
    /// Günlük OTU limiti
    public var dailyOTULimit: Double

    /// İzin verilen azami çıkış hızı (m/dk)
    public var maxAscentRate: Double
    /// Dikkat çıkış hızı (m/dk)
    public var cautionAscentRate: Double
    /// Hız ihlalinin alarm vermesi için sürmesi gereken süre (saniye)
    public var rateViolationHoldTime: TimeInterval

    /// Profil kaydı aralığı (saniye)
    public var profileSampleInterval: TimeInterval
    /// Yüzey referans basıncı (bar) — rakım düzeltmesi
    public var surfacePressure: Double

    /// Emniyet durağı bölgesinin üst sınırı (m)
    public var safetyStopZoneDepth: Double
    /// Emniyet durağı için gereken süre (saniye)
    public var safetyStopRequiredDuration: TimeInterval

    /// Alarm tekrar beklemesi (saniye)
    public var alarmCooldown: TimeInterval
    /// Tam ekran kritik alarmı açık mı?
    public var fullScreenAlertsEnabled: Bool

    public init(water: DivePhysics.WaterType = .salt,
                gradientFactors: GradientFactors = .conservative,
                gases: [GasMix] = [.air],
                startGasIndex: Int = 0,
                maxPO2: Double = DiveSafetyLimits.maximumPO2,
                oxygenWarningPercent: Double = DiveSafetyLimits.oxygenWarningPercent,
                dailyOTULimit: Double = 80,
                maxAscentRate: Double = DiveSafetyLimits.maximumAscentRate,
                cautionAscentRate: Double = DiveSafetyLimits.cautionAscentRate,
                rateViolationHoldTime: TimeInterval = 4,
                profileSampleInterval: TimeInterval = 10,
                surfacePressure: Double = DivePhysics.surfacePressure,
                safetyStopZoneDepth: Double = 5,
                safetyStopRequiredDuration: TimeInterval = 180,
                alarmCooldown: TimeInterval = 10,
                fullScreenAlertsEnabled: Bool = true) {
        self.water = water
        self.gradientFactors = gradientFactors
        self.gases = gases.isEmpty ? [.air] : gases
        self.startGasIndex = startGasIndex
        self.maxPO2 = maxPO2
        self.oxygenWarningPercent = oxygenWarningPercent
        self.dailyOTULimit = dailyOTULimit
        self.maxAscentRate = maxAscentRate
        self.cautionAscentRate = cautionAscentRate
        self.rateViolationHoldTime = rateViolationHoldTime
        self.profileSampleInterval = profileSampleInterval
        self.surfacePressure = surfacePressure
        self.safetyStopZoneDepth = safetyStopZoneDepth
        self.safetyStopRequiredDuration = safetyStopRequiredDuration
        self.alarmCooldown = alarmCooldown
        self.fullScreenAlertsEnabled = fullScreenAlertsEnabled
    }

    /// Başlangıçta kullanılacak gaz
    public var startGas: GasMix {
        gases.indices.contains(startGasIndex) ? gases[startGasIndex] : .air
    }

    /// Sıfır toleranslı tek silindir konfigürasyonu.
    public static let recreational = DiveConfiguration(
        gradientFactors: .conservative,
        gases: [.air],
        surfacePressure: DivePhysics.surfacePressure)

    /// Nitrox konfigürasyonu.
    public static func nitrox(_ mix: GasMix, second: GasMix? = nil) -> DiveConfiguration {
        DiveConfiguration(
            gradientFactors: .conservative,
            gases: second.map { [mix, $0] } ?? [mix])
    }

    /// Deko gazı içeren (EAN32 + O2) konfigürasyonu.
    public static let nitroxWithDecoGas = DiveConfiguration(
        gradientFactors: .conservative,
        gases: [.air, .ean32, .oxygen],
        startGasIndex: 1)
}