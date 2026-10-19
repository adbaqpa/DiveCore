import Foundation

/// Dalış öncesi **ayarlar ekranı** verisi (ADIM 6).
///
/// GF seçimi, gaz planı ve derin durak seçenekleri tek yapıda toplanır;
/// SwiftUI yalnızca listeler ve değişiklikleri `DiveSettings` ile yapar.
public struct DiveSettingsDisplay: Equatable, Sendable {

    // MARK: - GF

    /// Tek bir GF ön ayar satırı.
    public struct FactorRow: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let factorsText: String
        public let summary: String
        public let isSelected: Bool
        public let isRecommended: Bool
        public let colorRole: DiveColorRole

        public init(preset: GradientFactorCatalog.Preset,
                    selected: GradientFactors,
                    recommended: GradientFactorCatalog.Preset?) {
            self.id = preset.id
            self.name = preset.name
            self.factorsText = preset.factorsText
            self.summary = preset.summary
            self.isSelected = preset.factors == selected
            self.isRecommended = recommended?.id == preset.id
            self.colorRole = isSelected ? .accent : .secondary
        }
    }

    /// Özel GF girişi (kaydırıcılar).
    public struct CustomRow: Equatable, Sendable {
        public let low: Int
        public let high: Int
        public let isValid: Bool
        public let spreadText: String
        /// Geniş aralık uyarısı (AOD/ekran rengi için)
        public let isCaution: Bool
        public let note: String

        public init(factors: GradientFactors) {
            self.low = factors.low
            self.high = factors.high
            self.isValid = GradientFactorCatalog.isValid(low: factors.low, high: factors.high)
            self.spreadText = "Aralık genişliği: \(GradientFactorCatalog.spread(of: factors))"
            // Çok geniş aralık (ör. 10/100) dikey yükleme yapar
            let spread = GradientFactorCatalog.spread(of: factors)
            self.isCaution = spread > 70
            if spread == 0 {
                self.note = "Sabit GF — tüm derinliklerde aynı değer"
            } else if isCaution {
                self.note = "Çok geniş aralık — daha fazla durağa çıkabilir"
            } else {
                self.note = ""
            }
        }
    }

    // MARK: - Gaz

    /// Tek bir silindir satırı.
    public struct GasRow: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let label: String
        public let modText: String
        public let nitrogenPercentText: String
        public let isStartGas: Bool
        public let isDecoGas: Bool
        public let isUsableAtTargetDepth: Bool
        public let colorRole: DiveColorRole

        public init(cylinder: GasPlan.Cylinder, isStart: Bool, targetDepth: Double,
                    maxPO2: Double, water: DivePhysics.WaterType) {
            self.id = cylinder.id
            self.label = cylinder.gas.label
            self.modText = cylinder.gas.maximumOperatingDepthText(
                maxPO2: cylinder.effectiveMaxPO2(planMaxPO2: maxPO2), water: water)
            self.nitrogenPercentText = "%\(cylinder.gas.nitrogenPercent) N₂"
            self.isStartGas = isStart
            self.isDecoGas = cylinder.gas.oxygenFraction >= 0.99
            self.isUsableAtTargetDepth = cylinder.isUsable(
                at: targetDepth,
                maxPO2: cylinder.effectiveMaxPO2(planMaxPO2: maxPO2),
                water: water)
            self.colorRole = isUsableAtTargetDepth ? .safe : .danger
        }
    }

    // MARK: - Derin duraklar

    public struct DeepStopRow: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let depthText: String
        public let isLive: Bool
        public let holdText: String
        public let colorRole: DiveColorRole

        public init(stop: DeepStopCalculator.DeepStop) {
            self.id = stop.id
            self.depthText = stop.label
            self.isLive = stop.isLive
            self.holdText = stop.holdTime > 0 ? DurationFormatter.clock(stop.holdTime) : "—"
            self.colorRole = stop.isLive ? .accent : .secondary
        }
    }

    // MARK: - Genel

    public let selectedFactors: GradientFactors
    public let factorsText: String
    public let factorsRows: [FactorRow]
    public let customRow: CustomRow
    public let recommendationNote: String

    public let gasRows: [GasRow]
    public let switchNote: String
    public let gasIssues: [String]

    public let deepStopsEnabled: Bool
    public let deepStopRows: [DeepStopRow]
    public let deepStopNote: String

    public let targetDepthText: String
    public let targetDurationText: String
    public let estimatedNDLText: String

    public init(settings: DiveSettings,
                targetDepth: Double,
                targetDuration: TimeInterval,
                estimatedNDL: TimeInterval,
                calculatedDeepStops: [DeepStopCalculator.DeepStop] = [],
                water: DivePhysics.WaterType = .salt) {
        let recommended = GradientFactorCatalog.recommended(
            maxDepth: targetDepth, duration: targetDuration,
            experience: settings.experience)

        self.selectedFactors = settings.gradientFactors
        self.factorsText = settings.gradientFactors.displayText
        self.factorsRows = GradientFactorCatalog.presets.map {
            FactorRow(preset: $0, selected: settings.gradientFactors, recommended: recommended)
        }
        self.customRow = CustomRow(factors: settings.gradientFactors)
        self.recommendationNote = "Öneri: \(recommended.name) (\(recommended.factorsText)) — \(recommended.summary)"

        self.gasRows = settings.gasPlan.cylinders.enumerated().map { index, cylinder in
            GasRow(cylinder: cylinder, isStart: index == 0,
                   targetDepth: targetDepth,
                   maxPO2: settings.gasPlan.maxPO2, water: water)
        }
        let table = settings.gasPlan.switchTable()
        self.switchNote = table.isEmpty
            ? "Gaz değişimi yok"
            : table.map { "\(Int($0.depth)) m'de \($0.from.label) → \($0.to.label)" }
                .joined(separator: " · ")
        self.gasIssues = settings.gasPlan.validate().map(\.message)

        self.deepStopsEnabled = settings.deepStops.isEnabled
        self.deepStopRows = calculatedDeepStops.map { DeepStopRow(stop: $0) }
        let liveCount = calculatedDeepStops.filter { $0.isLive }.count
        self.deepStopNote = settings.deepStops.isEnabled
            ? "\(calculatedDeepStops.count) aday, \(liveCount) canlı"
            : "Kapalı — ayarlardan açılabilir"

        self.targetDepthText = String(format: "%.0f m", targetDepth)
        self.targetDurationText = DurationFormatter.hoursMinutes(targetDuration)
        self.estimatedNDLText = DurationFormatter.clock(estimatedNDL)
    }
}

/// Dalış öncesi ayarların kalıcı değeri (ADIM 6).
public struct DiveSettings: Equatable, Codable, Sendable {

    public var gradientFactors: GradientFactors
    public var gasPlan: GasPlan
    public var deepStops: DeepStopCalculator.Settings
    public var experience: GradientFactorCatalog.Experience
    /// Dalış öncesi hedef derinlik (m) — gaz ve GF önerisi için
    public var targetDepth: Double
    /// Dalış öncesi hedef süre (saniye)
    public var targetDuration: TimeInterval

    // MARK: Enerji (ADIM 11)

    /// Enerji profili — pil/performance dengesi
    public var powerProfile: PowerProfile
    /// Gece modu tercihi
    public var nightModePreference: EnergyManager.NightModePreference
    /// AOD (Always-On Display) kullanımı — pilin en büyük tüketicisi
    public var allowsAlwaysOnDisplay: Bool
    /// Arka plan konum takibi (uçuş yasağı/complikasyon için) gerekiyor mu
    public var tracksSurfaceLocation: Bool

    public init(gradientFactors: GradientFactors = GradientFactors.conservative,
                gasPlan: GasPlan = .air(),
                deepStops: DeepStopCalculator.Settings = .disabled,
                experience: GradientFactorCatalog.Experience = .experienced,
                targetDepth: Double = 30,
                targetDuration: TimeInterval = 20 * 60,
                powerProfile: PowerProfile = .balanced,
                nightModePreference: EnergyManager.NightModePreference = .auto,
                allowsAlwaysOnDisplay: Bool = true,
                tracksSurfaceLocation: Bool = true) {
        self.gradientFactors = gradientFactors
        self.gasPlan = gasPlan
        self.deepStops = deepStops
        self.experience = experience
        self.targetDepth = targetDepth
        self.targetDuration = targetDuration
        self.powerProfile = powerProfile
        self.nightModePreference = nightModePreference
        self.allowsAlwaysOnDisplay = allowsAlwaysOnDisplay
        self.tracksSurfaceLocation = tracksSurfaceLocation
    }

    public static let recreational = DiveSettings(
        gradientFactors: .conservative,
        gasPlan: .air(),
        targetDepth: 30,
        targetDuration: 20 * 60)

    public static let nitrox = DiveSettings(
        gradientFactors: .balanced,
        gasPlan: .nitroxWithDeco(.ean32),
        targetDepth: 30,
        targetDuration: 25 * 60)

    // MARK: - Türetilmiş

    public var targetNitroxPercent: Int {
        NitroxPicker.recommendedPercent(targetDepth: targetDepth, maxPO2: gasPlan.maxPO2)
    }

    /// Seçilen gaz planı başlangıç gazını kullanarak geçerli mi?
    public var isStartGasUsable: Bool {
        guard let first = gasPlan.cylinders.first else { return false }
        return first.isUsable(at: targetDepth,
                              maxPO2: first.effectiveMaxPO2(planMaxPO2: gasPlan.maxPO2))
    }

    /// Ayarları `DiveConfiguration`'a çevirir (oturum başlatmadan önce).
    public func configuration(ascentRate: Double = DiveSafetyLimits.maximumAscentRate) -> DiveConfiguration {
        DiveConfiguration(water: gasPlan.water,
                          gradientFactors: gradientFactors,
                          gases: gasPlan.cylinders.map(\.gas),
                          startGasIndex: 0,
                          maxPO2: gasPlan.maxPO2,
                          maxAscentRate: ascentRate)
    }

    /// Hedefe uygun önerilen gaz planını üretir (EAN + deko O₂).
    public static func suggested(targetDepth: Double,
                                 targetDuration: TimeInterval,
                                 maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                 water: DivePhysics.WaterType = .salt) -> DiveSettings {
        let percent = NitroxPicker.recommendedPercent(targetDepth: targetDepth,
                                                      maxPO2: maxPO2, water: water)
        let mix = percent > 21 ? GasMix(oxygenPercent: Double(percent)) : GasMix.air
        let plan: GasPlan = mix == GasMix.air
            ? .air(maxPO2: maxPO2)
            : GasPlan.nitroxWithDeco(mix, maxPO2: maxPO2)

        let recommended = GradientFactorCatalog.recommended(maxDepth: targetDepth,
                                                            duration: targetDuration)
        return DiveSettings(gradientFactors: recommended.factors,
                            gasPlan: plan,
                            targetDepth: targetDepth,
                            targetDuration: targetDuration)
    }
}