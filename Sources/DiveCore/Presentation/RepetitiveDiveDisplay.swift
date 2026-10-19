import Foundation

/// Tekrar dalış hesaplayıcısının ekran verisi (ADIM 8).
///
/// SwiftUI katmanı yalnızca bu yapıyı tüketir; hesap mantığı
/// `RepetitiveDiveCalculator` içinde, test edilebilir biçimde kalır.
public struct RepetitiveDiveDisplay: Equatable, Codable, Sendable, Identifiable {

    public let id: String

    // MARK: Giriş
    public let targetDepthText: String
    public let plannedDurationText: String

    // MARK: NDL karşılaştırması
    public let effectiveNDLText: String
    public let freshNDLText: String
    public let lossText: String
    public let lossPercent: Double

    // MARK: Deko ve uçuş
    public let decoStatusText: String
    public let decoRows: [Row]
    public let noFlyText: String
    public let noFlyCabinText: String

    // MARK: Gaz
    public let gasLabel: String
    public let gasModText: String
    /// Dalış sonundaki yüzey GF99 metni
    public let gf99Label: String

    // MARK: Uyarılar
    public let warnings: [String]

    /// Ekrandaki tek satırlık bölüm.
    public struct Row: Equatable, Codable, Sendable, Identifiable {
        public let id: String
        public let depthText: String
        public let durationText: String
        public let isSafetyStop: Bool
        public let gasLabel: String

        public init(id: String, depthText: String, durationText: String,
                    isSafetyStop: Bool, gasLabel: String) {
            self.id = id
            self.depthText = depthText
            self.durationText = durationText
            self.isSafetyStop = isSafetyStop
            self.gasLabel = gasLabel
        }
    }

    // MARK: - Kurulum

    public init(id: String = "repetitive",
                targetDepthText: String,
                plannedDurationText: String,
                effectiveNDLText: String,
                freshNDLText: String,
                lossText: String,
                lossPercent: Double,
                decoStatusText: String,
                decoRows: [Row],
                noFlyText: String,
                noFlyCabinText: String,
                gasLabel: String,
                gasModText: String,
                gf99Label: String,
                warnings: [String]) {
        self.id = id
        self.targetDepthText = targetDepthText
        self.plannedDurationText = plannedDurationText
        self.effectiveNDLText = effectiveNDLText
        self.freshNDLText = freshNDLText
        self.lossText = lossText
        self.lossPercent = lossPercent
        self.decoStatusText = decoStatusText
        self.decoRows = decoRows
        self.noFlyText = noFlyText
        self.noFlyCabinText = noFlyCabinText
        self.gasLabel = gasLabel
        self.gasModText = gasModText
        self.gf99Label = gf99Label
        self.warnings = warnings
    }

    /// Hesaplayıcı sonucundan ekran verisi üretir.
    ///
    /// - Parameters:
    ///   - result: Hesap sonucu
    ///   - cabinNoFly: Kabin profiline göre uçuş yasağı (saniye)
    ///   - cabinTitle: Kabin profilinin adı
    public init(result: RepetitiveDiveCalculator.Result,
                cabinNoFly: TimeInterval,
                cabinTitle: String) {
        self.init(
            id: "repetitive-\(Int(result.targetDepth))",
            targetDepthText: String(format: "%.0f m", result.targetDepth),
            plannedDurationText: DurationFormatter.clock(result.plannedDuration),
            effectiveNDLText: result.effectiveNDL > 0
                ? DurationFormatter.clock(result.effectiveNDL) : "Yok",
            freshNDLText: DurationFormatter.clock(result.freshNDL),
            lossText: result.ndlLossPercent > 0.5
                ? String(format: "%%%.0f kısalma", result.ndlLossPercent)
                : "Etkisi yok",
            lossPercent: result.ndlLossPercent / 100,
            decoStatusText: result.hasDecoObligation
                ? String(format: "Deko zorunlu · %@ toplam",
                         DurationFormatter.clock(result.plan.totalTime))
                : "Deko gerekmiyor",
            decoRows: result.plan.stops.map { stop in
                Row(id: "stop-\(Int(stop.depth))",
                    depthText: String(format: "%.0f m", stop.depth),
                    durationText: DurationFormatter.clock(stop.holdTime),
                    isSafetyStop: stop.isSafetyStop,
                    gasLabel: stop.gas.label)
            },
            noFlyText: DurationFormatter.hoursMinutes(result.noFlyTime),
            noFlyCabinText: "\(cabinTitle): " + DurationFormatter.hoursMinutes(cabinNoFly),
            gasLabel: result.suggestedGas.label,
            gasModText: String(format: "MOD %.0f m",
                               result.suggestedGas.maximumOperatingDepth(maxPO2: 1.4)),
            gf99Label: "GF99 %\(Int(result.endTissues.gf99(atDepth: 0).rounded()))",
            warnings: result.warnings)
    }

    /// Artık yük etkisi görünür mü?
    public var showsResidualPenalty: Bool { lossPercent > 0.005 }

    /// Deko satırları var mı?
    public var hasDecoRows: Bool { !decoRows.isEmpty }
}

/// Yüzey aralığı / uçuş yasağı ekranı verisi (ADIM 8 ana ekranı).
public struct NoFlyDisplay: Equatable, Codable, Sendable {

    public let title: String
    public let countdown: String
    public let progress: Double
    public let gf99Text: String
    public let cabinTitle: String
    public let cabinCountdown: String
    public let nextCheckText: String?
    public let colorRole: DiveColorRole
    public let isActive: Bool

    public init(status: SurfaceIntervalStatus,
                cabin: FlightAltitudeCalculator.CabinProfile,
                cabinRemaining: TimeInterval,
                nextCheck: Date?,
                now: Date) {
        self.title = status.isNoFlyCleared ? "Uçuş serbest" : "Uçuş yasağı"
        self.countdown = status.isNoFlyCleared
            ? DurationFormatter.hoursMinutes(status.elapsed)
            : DurationFormatter.hoursMinutes(status.noFlyRemaining)
        self.progress = min(1, max(0, status.gf99 / 120))
        self.gf99Text = status.gf99Text
        self.cabinTitle = cabin.title
        self.cabinCountdown = DurationFormatter.hoursMinutes(cabinRemaining)
        self.nextCheckText = nextCheck.map { date in
            let delta = date.timeIntervalSince(now)
            return "Sonraki kontrol: " + DurationFormatter.clock(delta)
        }
        self.colorRole = status.isNoFlyCleared ? .safe : .caution
        self.isActive = !status.isNoFlyCleared
    }
}