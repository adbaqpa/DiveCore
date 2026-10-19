import Foundation

/// Günlük dalış defteri ekranı verisi (ADIM 5).
public struct LogbookDisplay: Equatable, Codable, Sendable {

    /// Tek bir kayıt satırı.
    public struct Row: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        public let title: String
        public let subtitle: String
        public let gradeText: String
        public let hasDeco: Bool
        public let depthFraction: Double

        public init(dive: LoggedDive, depthScale: Double = 60) {
            self.id = dive.id
            self.title = dive.displayTitle
            self.subtitle = dive.startDate.formatted(
                .dateTime.day().month(.abbreviated).hour().minute())
            self.gradeText = String(repeating: "★", count: dive.grade.stars)
                + String(repeating: "☆", count: 5 - dive.grade.stars)
            self.hasDeco = dive.hadDecoObligation
            self.depthFraction = min(1, max(0, dive.maxDepth / max(1, depthScale)))
        }
    }

    public let rows: [Row]
    public let statisticsLines: [String]
    public let today: DailyDiveTotals?
    public let todayAdvice: String
    public let syncLabel: String
    public let isEmpty: Bool

    public init(dives: [LoggedDive], statistics: DiveStatistics,
                today: DailyDiveTotals?, syncLabel: String = "") {
        let scale = max(30, statistics.deepestDive * 1.2)
        self.rows = dives.map { Row(dive: $0, depthScale: scale) }
        self.statisticsLines = [
            "\(statistics.diveCount) dalış · \(DurationFormatter.hoursMinutes(statistics.totalDiveTime))",
            "Azami \(String(format: "%.1f", statistics.deepestDive)) m · en uzun \(DurationFormatter.hoursMinutes(statistics.longestDiveTime))",
            "Deko: \(statistics.divesWithDeco) · emniyet durağı: \(statistics.completedSafetyStops)"
        ]
        self.today = today
        self.todayAdvice = today?.advice() ?? "Bugün henüz dalış yok"
        self.syncLabel = syncLabel
        self.isEmpty = dives.isEmpty
    }
}

/// Deko planının ekranda gösterilecek hâli.
public struct DecoPlanDisplay: Equatable, Codable, Sendable {

    /// Tek bir durak satırı.
    public struct Row: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        public let depthText: String
        public let holdText: String
        public let arrivalText: String
        public let departureText: String
        public let gasLabel: String
        public let isSafetyStop: Bool
        public let isOptional: Bool

        public init(stop: DecoStopPlan.Stop) {
            self.id = stop.id
            self.depthText = "\(Int(stop.depth)) m"
            self.holdText = DurationFormatter.clock(stop.holdTime)
            self.arrivalText = DurationFormatter.clock(stop.arrivalTime)
            self.departureText = DurationFormatter.clock(stop.departureTime)
            self.gasLabel = stop.gas.label
            self.isSafetyStop = stop.isSafetyStop
            self.isOptional = stop.isOptional
        }
    }

    public let rows: [Row]
    public let totalTimeText: String
    public let holdTimeText: String
    public let ascentTimeText: String
    public let ceilingText: String
    public let hasDecoObligation: Bool
    public let headline: String

    public init(plan: DecoStopPlan) {
        self.rows = plan.stops.map(Row.init(stop:))
        self.totalTimeText = DurationFormatter.clock(plan.totalTime)
        self.holdTimeText = DurationFormatter.clock(plan.totalHoldTime)
        self.ascentTimeText = DurationFormatter.clock(plan.ascentTime)
        self.ceilingText = plan.ceilingDepth > 0
            ? String(format: "%.1f m", plan.ceilingDepth) : "—"
        self.hasDecoObligation = plan.hasDecoObligation
        self.headline = plan.hasDecoObligation
            ? "\(plan.stops.count) durağ · toplam \(DurationFormatter.hoursMinutes(plan.totalTime))"
            : "Deko gerekmiyor · emniyet durağı \(DurationFormatter.clock(plan.totalTime))"
    }
}

/// Çıkış rehberinin ekranda gösterilecek hâli.
public struct GuidanceDisplay: Equatable, Codable, Sendable {

    public let instruction: String
    public let severity: AscentAdvisor.Guidance.Severity
    /// Tavanın üstüne çıkılmaması gereken derinlik ("6.0 m")
    public let maximumAllowedText: String
    public let nextStopText: String
    public let holdText: String
    public let timeToStopText: String
    public let ttsText: String
    public let colorRole: DiveColorRole
    public let isAboveCeiling: Bool

    public init(guidance: AscentAdvisor.Guidance) {
        self.instruction = guidance.instruction
        self.severity = guidance.severity
        self.maximumAllowedText = guidance.ceilingDepth > 0
            ? String(format: "%.1f m", guidance.maximumAllowedDepth) : "—"
        self.nextStopText = guidance.nextStopDepth.map { "\(Int($0)) m" } ?? "—"
        self.holdText = guidance.stopHoldTime > 0
            ? DurationFormatter.clock(guidance.stopHoldTime) : "—"
        self.timeToStopText = guidance.timeToStop > 0
            ? DurationFormatter.clock(guidance.timeToStop) : "—"
        self.ttsText = DurationFormatter.clock(guidance.timeToSurface)
        self.isAboveCeiling = guidance.isAboveCeiling

        switch guidance.severity {
        case .ok: self.colorRole = .safe
        case .caution: self.colorRole = .caution
        case .warning: self.colorRole = .deco
        case .critical: self.colorRole = .danger
        }
    }
}

/// Oksijen durumunun ekranda gösterilecek hâli (CNS/OTU/PO₂ kartı).
public struct OxygenDisplay: Equatable, Codable, Sendable {

    public struct Metric: Equatable, Codable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let valueText: String
        /// 0...1 ilerleme çubuğu
        public let progress: Double
        public let level: OxygenStatus.Level
        public let colorRole: DiveColorRole
    }

    public let metrics: [Metric]
    public let isAlarm: Bool
    public let message: String?
    public let headline: String

    public init(status: OxygenStatus) {
        func role(_ level: OxygenStatus.Level) -> DiveColorRole {
            switch level {
            case .ok: return .safe
            case .caution: return .caution
            case .warning: return .caution
            case .critical: return .danger
            }
        }
        self.metrics = [
            Metric(id: "po2", label: "PO₂",
                   valueText: String(format: "%.2f", status.po2),
                   progress: min(1, max(0, status.po2 / DiveSafetyLimits.maximumPO2)),
                   level: status.po2Level, colorRole: role(status.po2Level)),
            Metric(id: "cns", label: "CNS",
                   valueText: String(format: "%.0f%%", status.cnsPercent),
                   progress: min(1, status.cnsPercent / 100),
                   level: status.cnsLevel, colorRole: role(status.cnsLevel)),
            Metric(id: "otu", label: "OTU",
                   valueText: String(format: "%.0f", status.otuUnits),
                   progress: min(1, status.otuPercent / 100),
                   level: status.otuLevel, colorRole: role(status.otuLevel))
        ]
        self.isAlarm = status.isAlarm
        self.message = status.message
        self.headline = status.overallLevel.label
    }

    /// En yüksek riskli metrik (ekranda vurgulanacak).
    public var worstMetric: Metric? {
        metrics.max(by: { $0.level < $1.level })
    }
}

/// Yüzey aralığı ekranı verisi.
public struct SurfaceIntervalDisplay: Equatable, Codable, Sendable {

    public let elapsedText: String
    public let gf99Text: String
    public let gf99Progress: Double
    public let desaturationText: String
    public let noFlyText: String
    public let isCleared: Bool
    public let recommendation: String
    public let statusText: String
    public let colorRole: DiveColorRole

    public init(status: SurfaceIntervalStatus) {
        self.elapsedText = DurationFormatter.hoursMinutes(status.elapsed)
        self.gf99Text = status.gf99Text
        self.gf99Progress = min(1, max(0, status.gf99 / 100))
        self.desaturationText = DurationFormatter.clock(status.desaturationRemaining)
        self.noFlyText = DurationFormatter.clock(status.noFlyRemaining)
        self.isCleared = status.isNoFlyCleared
        self.recommendation = status.recommendation
        self.statusText = status.isNoFlyCleared ? "Serbest" : "Uçuş yasağı"
        self.colorRole = status.isNoFlyCleared ? .safe : .caution
    }
}

/// Dalış sonu raporunun ekranda gösterilecek zengin hâli.
public struct DiveReportDisplay: Equatable, Codable, Sendable {

    /// Not kesintilerinden biri.
    public struct PenaltyRow: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        public let icon: String
        public let reason: String
        public let colorRole: DiveColorRole

        public init(penalty: DivePenalty) {
            self.id = penalty.id
            self.reason = penalty.reason
            self.icon = PenaltyRow.icon(for: penalty.kind)
            self.colorRole = penalty.weight >= 2 ? .danger : .caution
        }

        static func icon(for kind: DivePenalty.Kind) -> String {
            switch kind {
            case .fastAscent, .fastDescent, .excessiveDescentRate:
                return "arrow.up.arrow.down.circle.fill"
            case .ceilingViolation:
                return "exclamationmark.triangle.fill"
            case .missingSafetyStop:
                return "pause.circle.fill"
            case .exceededMOD, .highCNS, .highOTU:
                return "drop.triangle.fill"
            case .deepDive:
                return "arrow.down.to.line.circle.fill"
            case .longDive:
                return "clock.fill"
            case .decoObligation, .skippedStops:
                return "list.bullet.rectangle.fill"
            }
        }
    }

    /// Deko durak kaydı satırı.
    public struct StopRow: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        public let label: String
        public let gasLabel: String

        public init(record: DecoStopRecord) {
            self.id = record.id
            self.label = "\(Int(record.depth)) m · \(DurationFormatter.clock(record.duration))"
            self.gasLabel = record.gas.label
        }
    }

    public let title: String
    public let gradeText: String
    public let gradeStars: Int
    public let score: Int
    public let maxDepthText: String
    public let averageDepthText: String
    public let totalTimeText: String
    public let bottomTimeText: String
    public let temperatureText: String
    public let maxRatesText: String
    public let gasText: String
    public let po2Text: String
    public let gf99Text: String
    public let cnsText: String
    public let otuText: String
    public let safetyStopText: String
    public let decoStopRows: [StopRow]
    public let totalDecoText: String
    public let penaltyRows: [PenaltyRow]
    public let noFlyText: String
    public let headline: String

    public init(report: DiveReport) {
        self.title = "Dalış Özeti"
        let grade = DiveGrade.grade(score: report.score)
        self.gradeText = String(repeating: "★", count: grade.stars)
            + String(repeating: "☆", count: 5 - grade.stars)
        self.gradeStars = report.grade.stars
        self.score = report.score
        self.maxDepthText = String(format: "%.1f m", report.maxDepth)
        self.averageDepthText = String(format: "%.1f m", report.averageDepth)
        self.totalTimeText = DurationFormatter.hoursMinutes(report.totalDiveTime)
        self.bottomTimeText = DurationFormatter.hoursMinutes(report.bottomTime)
        self.temperatureText = String(format: "%.0f - %.0f°C",
                                      report.minimumTemperature, report.maximumTemperature)
        self.maxRatesText = String(format: "↑%.1f / ↓%.0f m/dk",
                                   report.maxAscentRate, report.maxDescentRate)
        self.gasText = report.gases.map(\.label).joined(separator: " / ")
        self.po2Text = String(format: "%.2f bar", report.maxPO2)
        self.gf99Text = "%\(Int(report.maxGF99.rounded()))"
        self.cnsText = String(format: "%.0f%%", report.cnsPercent)
        self.otuText = String(format: "%.0f (%.0f%%)", report.otuUnits, report.oxygen.otuPercent)
        self.safetyStopText = report.safetyStopCompleted
            ? "Tamamlandı (\(DurationFormatter.clock(report.safetyStopAccumulated)))"
            : (report.safetyStopAccumulated > 0
               ? DurationFormatter.clock(report.safetyStopAccumulated) : "Yapılmadı")
        self.decoStopRows = report.decoStops.map(StopRow.init(record:))
        self.totalDecoText = report.decoStops.isEmpty
            ? "Deko yok" : DurationFormatter.clock(report.totalDecoTime)
        self.penaltyRows = report.penalties.map(PenaltyRow.init(penalty:))
        self.noFlyText = DurationFormatter.hoursMinutes(report.noFlyTime)
        self.headline = report.headline
    }
}