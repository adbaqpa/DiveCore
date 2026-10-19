import Foundation

/// Dalış sırasında geçilen **zorunlu deko durağı** kaydı.
public struct DecoStopRecord: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    /// Durağın planlanan derinliği (m)
    public let depth: Double
    /// Durağa varış (saniye)
    public let arrivalElapsed: TimeInterval
    /// Durağa kalış süresi (saniye)
    public let duration: TimeInterval
    /// Kalkış (saniye)
    public let departureElapsed: TimeInterval
    /// Kullanılan gaz
    public let gas: GasMix

    public init(id: UUID = UUID(), depth: Double,
                arrivalElapsed: TimeInterval, duration: TimeInterval,
                departureElapsed: TimeInterval, gas: GasMix) {
        self.id = id
        self.depth = depth
        self.arrivalElapsed = arrivalElapsed
        self.duration = duration
        self.departureElapsed = departureElapsed
        self.gas = gas
    }

    /// "6 m · 04:12" etiketi.
    public var label: String { "\(Int(depth)) m · \(DurationFormatter.clock(duration))" }
}

/// Dalış kalite puanı kesintileri (neden düşüldüğünü açıklar).
public struct DivePenalty: Equatable, Codable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Codable, Sendable {
        case fastAscent
        case fastDescent
        case ceilingViolation
        case missingSafetyStop
        case exceededMOD
        case highCNS
        case highOTU
        case deepDive
        case longDive
        case decoObligation
        case skippedStops
        case excessiveDescentRate
    }

    public let id: UUID
    public let kind: Kind
    /// Kullanıcıya gösterilecek açıklama
    public let reason: String
    /// Puan kesintisi
    public let weight: Int

    public init(kind: Kind, reason: String, weight: Int) {
        self.id = UUID()
        self.kind = kind
        self.reason = reason
        self.weight = weight
    }
}

/// Dalış sonu **raporu** — ADIM 4'ün "post-dive summary" veri modeli.
///
/// `DiveSummaryDisplay` yalnızca ekranda gösterilecek metinleri üretir;
/// bu yapı ise analizin tamamını (uç değerler, duraklar, kesintiler) taşır.
public struct DiveReport: Equatable, Codable, Sendable {

    // Kimlik
    public var startDate: Date
    public var endDate: Date
    public var totalDiveTime: TimeInterval

    // Profil
    public var maxDepth: Double
    public var averageDepth: Double
    public var maxAscentRate: Double
    public var maxDescentRate: Double
    public var minimumTemperature: Double
    public var maximumTemperature: Double

    // Gaz / oksijen
    public var gases: [GasMix]
    public var startGas: GasMix
    public var maxPO2: Double
    public var cnsPercent: Double
    public var otuUnits: Double
    public var oxygen: OxygenStatus

    // Deko
    public var hadDecoObligation: Bool
    public var decoStops: [DecoStopRecord]
    public var safetyStopCompleted: Bool
    public var safetyStopAccumulated: TimeInterval
    public var maxGF99: Double
    public var finalGF99: Double
    public var noFlyTime: TimeInterval
    /// Dalış sonu doku yükleri (16 kompartman, bar)
    public var finalTissues: [Double]

    // Not
    public var penalties: [DivePenalty]
    public var score: Int
    public var grade: DiveGrade
    public var markerCount: Int
    public var gasChangeCount: Int

    public init(startDate: Date, endDate: Date, totalDiveTime: TimeInterval,
                maxDepth: Double, averageDepth: Double,
                maxAscentRate: Double, maxDescentRate: Double,
                minimumTemperature: Double, maximumTemperature: Double,
                gases: [GasMix], startGas: GasMix,
                maxPO2: Double, cnsPercent: Double, otuUnits: Double, oxygen: OxygenStatus,
                hadDecoObligation: Bool, decoStops: [DecoStopRecord],
                safetyStopCompleted: Bool, safetyStopAccumulated: TimeInterval,
                maxGF99: Double, finalGF99: Double, noFlyTime: TimeInterval,
                finalTissues: [Double], penalties: [DivePenalty],
                score: Int, grade: DiveGrade, markerCount: Int, gasChangeCount: Int) {
        self.startDate = startDate
        self.endDate = endDate
        self.totalDiveTime = totalDiveTime
        self.maxDepth = maxDepth
        self.averageDepth = averageDepth
        self.maxAscentRate = maxAscentRate
        self.maxDescentRate = maxDescentRate
        self.minimumTemperature = minimumTemperature
        self.maximumTemperature = maximumTemperature
        self.gases = gases
        self.startGas = startGas
        self.maxPO2 = maxPO2
        self.cnsPercent = cnsPercent
        self.otuUnits = otuUnits
        self.oxygen = oxygen
        self.hadDecoObligation = hadDecoObligation
        self.decoStops = decoStops
        self.safetyStopCompleted = safetyStopCompleted
        self.safetyStopAccumulated = safetyStopAccumulated
        self.maxGF99 = maxGF99
        self.finalGF99 = finalGF99
        self.noFlyTime = noFlyTime
        self.finalTissues = finalTissues
        self.penalties = penalties
        self.score = score
        self.grade = grade
        self.markerCount = markerCount
        self.gasChangeCount = gasChangeCount
    }

    // MARK: - Türetilmiş

    /// Toplam deko durağı süresi (saniye).
    public var totalDecoTime: TimeInterval { decoStops.reduce(0) { $0 + $1.duration } }

    /// Su altında geçen süre (saniye) — iniş+çıkış hariç tahmin.
    public var bottomTime: TimeInterval {
        max(0, totalDiveTime - maxAscentTime - maxDescentTime)
    }

    private var maxAscentTime: TimeInterval { maxDepth / 9 * 60 }
    private var maxDescentTime: TimeInterval { maxDepth / 15 * 60 }

    /// Kısa özet cümlesi (widget / bildirim için).
    public var headline: String {
        String(format: "%@ m · %@ · %@",
               String(format: "%.1f", maxDepth),
               DurationFormatter.hoursMinutes(totalDiveTime),
               grade == .excellent ? " kusursuz" : grade.rawValue.lowercased())
    }

    // MARK: - Analiz

    /// `DiveSessionController` çıktısından rapor üretir.
    ///
    /// - Parameters:
    ///   - state: Dalış sonu `DiveState`
    ///   - log: Dalış günlüğü (yoksa yalnızca durumdan analiz yapılır)
    ///   - decoStops: Oturumun kaydettiği deko durakları
    ///   - extremes: Dalış boyunca ölçülen uç değerler
    public static func analyze(state: DiveState,
                               log: LogEntry?,
                               decoStops: [DecoStopRecord],
                               extremes: DiveExtremes,
                               config: DiveConfiguration = .recreational) -> DiveReport {
        var penalties: [DivePenalty] = []

        // 1) Hızlı çıkış
        if extremes.maxAscentRate > DiveSafetyLimits.maximumAscentRate {
            penalties.append(DivePenalty(
                kind: .fastAscent,
                reason: String(format: "Çıkış hızı %.1f m/dk (sınır %.0f)",
                               extremes.maxAscentRate, DiveSafetyLimits.maximumAscentRate),
                weight: 2))
        }
        // 2) Hızlı iniş
        if extremes.maxDescentRate > DiveSafetyLimits.maximumDescentRate {
            penalties.append(DivePenalty(
                kind: .fastDescent,
                reason: String(format: "İniş hızı %.0f m/dk (sınır %.0f)",
                               extremes.maxDescentRate, DiveSafetyLimits.maximumDescentRate),
                weight: 1))
        }
        // 3) Tavan ihlali
        if let log, log.samples.contains(where: { $0.depth + 0.5 < $0.ceiling }) {
            penalties.append(DivePenalty(kind: .ceilingViolation,
                                         reason: "Tavanın üstüne çıkıldı", weight: 2))
        }
        // 4) Emniyet durağı
        if !state.safetyStop.isComplete && state.maxDepth > 6 {
            penalties.append(DivePenalty(
                kind: .missingSafetyStop,
                reason: "Emniyet durağı tamamlanmadı (\(DurationFormatter.clock(state.safetyStop.accumulated)))",
                weight: 1))
        }
        // 5) MOD aşımı
        if let log, log.maxPO2 > config.maxPO2 {
            penalties.append(DivePenalty(
                kind: .exceededMOD,
                reason: String(format: "PO₂ %.2f bar (azami %.1f)", log.maxPO2, config.maxPO2),
                weight: 2))
        }
        // 6) Oksijen toksisitesi
        let oxygen = OxygenStatus.evaluate(
            po2: log?.maxPO2 ?? state.oxygenPartialPressure,
            maximumOperatingDepth: state.maximumOperatingDepth,
            cnsPercent: log?.cnsPercent ?? state.cnsPercent,
            otuUnits: log?.otuUnits ?? state.otuUnits,
            otuPercent: log.map { $0.otuUnits / max(1, config.dailyOTULimit) * 100 } ?? state.otuPercent,
            maxPO2: config.maxPO2,
            warningPercent: config.oxygenWarningPercent,
            dailyOTULimit: config.dailyOTULimit)
        if oxygen.cnsLevel >= .warning {
            penalties.append(DivePenalty(
                kind: .highCNS,
                reason: String(format: "CNS %%%.0f", oxygen.cnsPercent), weight: 1))
        }
        // Not: OTU **günlük** biriktirmedir. Tek bir 18 m/30 dk hava dalışı
        // zaten ~140 birim (günlük limitin ~%175'i) harcar; bu normaldir.
        // Bu yüzden dalış notuna kesinti olarak yansıtılmaz, yalnızca
        // bilgi olarak raporlanır (bkz. `OxygenStatus` / `OxygenDisplay`).
        // Günlük toplam değerlendirmesi ADIM 5'te yapılacak.
        // 7) Derin / uzun dalış
        if state.maxDepth > 40 {
            penalties.append(DivePenalty(
                kind: .deepDive,
                reason: String(format: "Derin dalış: %.0f m", state.maxDepth), weight: 1))
        }
        if state.diveTime > 45 * 60 {
            penalties.append(DivePenalty(
                kind: .longDive,
                reason: "Uzun dalış (\(DurationFormatter.hoursMinutes(state.diveTime)))", weight: 1))
        }
        // 8) Deko
        let hadDeco = log?.hadDecoObligation ?? decoStops.isEmpty == false
        if hadDeco && state.safetyStop.isComplete == false && decoStops.isEmpty {
            penalties.append(DivePenalty(kind: .skippedStops,
                                         reason: "Deko zorunluluğu var", weight: 1))
        }

        let score = max(0, 5 - penalties.reduce(0) { $0 + $1.weight })

        let leading = log?.samples.last?.leadingTissuePressure ?? state.leadingTissuePressure
        let finalTissues = leading > 0 ? [leading] : []

        return DiveReport(
            startDate: state.startDate ?? Date(),
            endDate: state.endDate ?? Date(),
            totalDiveTime: state.diveTime,
            maxDepth: state.maxDepth,
            averageDepth: state.averageDepth,
            maxAscentRate: extremes.maxAscentRate,
            maxDescentRate: extremes.maxDescentRate,
            minimumTemperature: extremes.minimumTemperature,
            maximumTemperature: extremes.maximumTemperature,
            gases: state.gases,
            startGas: state.gases.indices.contains(state.gasIndex)
                ? state.gases[state.gasIndex] : state.gas,
            maxPO2: log?.maxPO2 ?? state.oxygenPartialPressure,
            cnsPercent: log?.cnsPercent ?? state.cnsPercent,
            otuUnits: log?.otuUnits ?? state.otuUnits,
            oxygen: oxygen,
            hadDecoObligation: hadDeco,
            decoStops: decoStops,
            safetyStopCompleted: state.safetyStop.isComplete,
            safetyStopAccumulated: state.safetyStop.accumulated,
            maxGF99: log?.maxGF99 ?? state.gf99,
            finalGF99: state.gf99,
            noFlyTime: state.noFlyTime,
            finalTissues: finalTissues,
            penalties: penalties,
            score: score,
            grade: DiveGrade.grade(score: score),
            markerCount: 0,
            gasChangeCount: 0)
    }
}

/// Dalış boyunca ölçülen uç değerler (oturumun topladığı istatistikler).
public struct DiveExtremes: Equatable, Codable, Sendable {
    public var maxAscentRate: Double = 0
    public var maxDescentRate: Double = 0
    public var minimumTemperature: Double = .greatestFiniteMagnitude
    public var maximumTemperature: Double = -.greatestFiniteMagnitude

    public init() {}

    public init(maxAscentRate: Double, maxDescentRate: Double,
                minimumTemperature: Double, maximumTemperature: Double) {
        self.maxAscentRate = maxAscentRate
        self.maxDescentRate = maxDescentRate
        self.minimumTemperature = minimumTemperature
        self.maximumTemperature = maximumTemperature
    }

    /// Henüz ölçüm yoksa makul aralıkta kalan "boş" uç değerler.
    public var resolved: DiveExtremes {
        var copy = self
        if minimumTemperature == .greatestFiniteMagnitude { copy.minimumTemperature = 0 }
        if maximumTemperature == -.greatestFiniteMagnitude { copy.maximumTemperature = 0 }
        return copy
    }
}

extension DiveGrade {
    /// Puan doğrudan verildiğinde sınıflandırma.
    public static func grade(score: Int) -> DiveGrade {
        switch score {
        case 5: return .excellent
        case 3...4: return .good
        case 2: return .fair
        default: return .poor
        }
    }
}