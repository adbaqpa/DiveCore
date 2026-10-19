import Foundation

// MARK: - Action Button

/// Apple Watch Ultra Action Button (ve dijital taç) için niyet.
///
/// ADIM 3 gereksinimi: "Dalışı başlat/bitir veya yer imi/marker atma".
/// Niyet kararı platformdan bağımsız bir makine ile verilir; watchOS tarafında
/// yalnızca `DiveSystem` bunu yürütür.
public enum DiveActionIntent: String, Equatable, Codable, Sendable {
    /// Dalışı başlat
    case startDive = "startDive"
    /// Yer imi ekle
    case placeMarker = "placeMarker"
    /// Alarmı onayla / sustur
    case acknowledgeAlarm = "acknowledgeAlarm"
    /// Dalışı bitir
    case endDive = "endDive"
    /// Hiçbir şey yapma
    case none = "none"

    /// Niyetin kullanıcıya ne söyleyeceği (onboarding ipucu olarak).
    public var label: String {
        switch self {
        case .startDive: return "Dalışı Başlat"
        case .placeMarker: return "İşaret Koy"
        case .acknowledgeAlarm: return "Aları Sustur"
        case .endDive: return "Dalışı Bitir"
        case .none: return "—"
        }
    }

    /// Buton ikonu için SF Symbol adı.
    public var symbolName: String {
        switch self {
        case .startDive: return "play.fill"
        case .placeMarker: return "mappin"
        case .acknowledgeAlarm: return "bell.slash"
        case .endDive: return "stop.fill"
        case .none: return "circle"
        }
    }
}

/// Action Button niyet çözümleyicisi.
///
/// Öncelik sırası:
/// 1. Kritik alarm varsa → `acknowledgeAlarm` (önce güvenlik),
/// 2. Dalış sürüyorsa → `placeMarker`,
/// 3. Dalış bitmişse → `none`,
/// 4. Yüzeydeyse → `startDive`.
public enum DiveActionButtonResolver {

    public static func intent(for state: DiveState, isDiving: Bool) -> DiveActionIntent {
        // 1) Kritik alarm önce gelir
        if state.warnings.contains(where: { $0.severity == .critical }) {
            return .acknowledgeAlarm
        }
        // 2) Dalış sürüyor → işaret
        if isDiving && state.phase.isDiving {
            return .placeMarker
        }
        // 3) Bitti / yüzeyde
        switch state.phase {
        case .preDive:
            return .startDive
        case .surfaced, .ended:
            return .none
        default:
            return .placeMarker
        }
    }

    /// İkincil eylem (uzun basış / Crown): dalışı bitir.
    public static func secondaryIntent(for state: DiveState, isDiving: Bool) -> DiveActionIntent {
        guard isDiving, state.phase.isDiving else { return .none }
        return .endDive
    }

    /// Niyeti çalıştırır ve yapılacak işi döndürür (test edilebilir yan etki).
    public enum Outcome: Equatable, Sendable {
        case started
        case markerAdded
        case alarmAcknowledged
        case ended
        case ignored
    }
}

// MARK: - Saat yüzü komplikasyonu verisi

/// Saat yüzü komplikasyonlarında (accessoryCircular / Rectangular / Inline)
/// gösterilecek veri.
///
/// watchOS bileşenlerinin veri ihtiyacı platformdan bağımsızdır; bu yapı
/// hem komplikasyonu hem de AOD "always-on" varyantını besler.
public struct DiveComplicationData: Equatable, Codable, Sendable {

    public enum Style: String, Equatable, Codable, Sendable, CaseIterable {
        /// accessoryInline — tek satır metin
        case inline
        /// accessoryCircular — dairesel kadran
        case circular
        /// accessoryRectangular — dikdörtgen blok
        case rectangular
        /// accessoryCorner — köşe
        case corner
    }

    public let style: Style
    /// Ana değer (derinlik veya geri sayım)
    public let primaryText: String
    /// İkincil değer
    public let secondaryText: String
    /// Üçüncül değer (zaman)
    public let tertiaryText: String
    /// Hız/sınır durumu rengi
    public let accentRole: DiveColorRole
    /// 0...1 gösterge dolgusu
    public let gauge: Double
    /// Alarm aktif mi
    public let isAlarmActive: Bool
    /// Niyet etiketi
    public let intentLabel: String

    public init(style: Style,
                primaryText: String,
                secondaryText: String,
                tertiaryText: String,
                accentRole: DiveColorRole,
                gauge: Double,
                isAlarmActive: Bool,
                intentLabel: String) {
        self.style = style
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.accentRole = accentRole
        self.gauge = gauge
        self.isAlarmActive = isAlarmActive
        self.intentLabel = intentLabel
    }
}

/// `DiveState` → komplikasyon verisi dönüşümü.
public enum DiveComplicationBuilder {

    public static func build(from state: DiveState, style: DiveComplicationData.Style) -> DiveComplicationData {
        let display = DiveDisplayBuilder.build(from: state)
        let intent = DiveActionButtonResolver.intent(for: state, isDiving: state.phase.isDiving)

        switch style {
        case .inline:
            // "24.6m · 12:40 · EAN32"
            let depth = "\(display.depthText)m"
            let middle = display.mode == .surfaced || display.mode == .summary
                ? display.phaseText : display.diveTimeText
            return DiveComplicationData(
                style: style,
                primaryText: "\(depth) · \(middle)",
                secondaryText: display.gasLabel,
                tertiaryText: "",
                accentRole: display.isAlarmActive ? .danger : display.ascentRate.level.colorRole,
                gauge: display.depthIndicator.fraction,
                isAlarmActive: display.isAlarmActive,
                intentLabel: intent.label)

        case .circular:
            // Dairesel: merkezde derinlik, çemberde hız göstergesi
            return DiveComplicationData(
                style: style,
                primaryText: display.depthText,
                secondaryText: display.ascentRate.aodLabel,
                tertiaryText: display.diveTimeText,
                accentRole: display.isAlarmActive ? .danger : display.ascentRate.level.colorRole,
                gauge: max(display.depthIndicator.fraction,
                           display.ascentRate.fill),
                isAlarmActive: display.isAlarmActive,
                intentLabel: intent.label)

        case .rectangular:
            // Dikdörtgen: üst satır gaz, orta derinlik, alt süre
            let ndl = display.hasNdl ? display.ndlText : display.deco.ceilingText
            return DiveComplicationData(
                style: style,
                primaryText: "\(display.depthText)m  \(display.maxDepthText)m",
                secondaryText: display.gasLabel,
                tertiaryText: display.diveTimeText + (display.hasNdl ? "  NDL \(ndl)" : "  TTS \(display.deco.ttsText)"),
                accentRole: display.isAlarmActive ? .danger : display.ascentRate.level.colorRole,
                gauge: display.depthIndicator.fraction,
                isAlarmActive: display.isAlarmActive,
                intentLabel: intent.label)

        case .corner:
            return DiveComplicationData(
                style: style,
                primaryText: display.depthText,
                secondaryText: display.ascentRate.level.aodSymbol,
                tertiaryText: display.diveTimeText,
                accentRole: display.isAlarmActive ? .danger : display.ascentRate.level.colorRole,
                gauge: display.depthIndicator.fraction,
                isAlarmActive: display.isAlarmActive,
                intentLabel: intent.label)
        }
    }
}

// MARK: - Dalış sonu özeti

/// Dalış bittiğinde gösterilecek özet (ADIM 4'te doldurulacak).
public struct DiveSummaryDisplay: Equatable, Codable, Sendable {

    public var title: String
    public var maxDepthText: String
    public var averageDepthText: String
    public var diveTimeText: String
    public var temperatureText: String
    public var decoText: String
    public var gf99Text: String
    public var cnsText: String
    public var otuText: String
    public var noFlyText: String
    public var surfaceIntervalText: String
    public var safetyStopText: String
    public var gradeText: String

    public init(state: DiveState, log: LogEntry? = nil) {
        let deco = DecoIndicator(state: state)
        self.title = state.phase == .ended ? "Dalış Tamamlandı" : "Dalış Özeti"
        self.maxDepthText = "\(String(format: "%.1f", state.maxDepth)) m"
        self.averageDepthText = "\(String(format: "%.1f", state.averageDepth)) m"
        self.diveTimeText = DurationFormatter.hoursMinutes(state.diveTime)
        self.temperatureText = String(format: "%.0f - %.0f°C",
                                      log?.waterTemperatureMin ?? state.waterTemperature,
                                      log?.waterTemperatureMax ?? state.waterTemperature)
        self.decoText = deco.hasObligation ? "Deko yapıldı" : "Deko yok"
        self.gf99Text = "\(Int(state.gf99.rounded()))%"
        self.cnsText = String(format: "%.0f%%", state.cnsPercent)
        self.otuText = String(format: "%.1f", state.otuUnits)
        self.noFlyText = DurationFormatter.hoursMinutes(state.noFlyTime)
        self.surfaceIntervalText = DurationFormatter.hoursMinutes(state.desaturationRemaining)
        self.safetyStopText = state.safetyStop.isComplete
            ? "Tamamlandı"
            : "\(DurationFormatter.clock(state.safetyStop.accumulated))"
        self.gradeText = DiveGrade.text(for: state, log: log)
    }
}

/// Dalış kalite notu (UI'da renk/yıldız olarak gösterilir).
public enum DiveGrade: String, Equatable, Codable, Sendable {
    case excellent = "Mükemmel"
    case good = "İyi"
    case fair = "Orta"
    case poor = "Kötü"

    /// 1...5 arası yıldız.
    public var stars: Int {
        switch self {
        case .excellent: return 5
        case .good: return 4
        case .fair: return 3
        case .poor: return 2
        }
    }

    public static func text(for state: DiveState, log: LogEntry? = nil) -> String {
        let grade = grade(for: state, log: log)
        return "\(String(repeating: "★", count: grade.stars))\(String(repeating: "☆", count: 5 - grade.stars))"
    }

    /// Kalite değerlendirmesi: hız ihlali, eksik emniyet durağı, yüksek CNS.
    public static func grade(for state: DiveState, log: LogEntry? = nil) -> DiveGrade {
        let hadFastAscent = log.map { entry in
            entry.samples.contains { $0.ascentRate > DiveSafetyLimits.maximumAscentRate }
        } ?? state.warnings.contains { $0.kind == .fastAscent }
        let stopComplete = log?.safetyStopCompleted ?? state.safetyStop.isComplete
        let cns = log?.cnsPercent ?? state.cnsPercent

        var score = 5
        if hadFastAscent { score -= 2 }
        if !stopComplete { score -= 1 }
        if cns > 80 { score -= 1 }
        if state.maxDepth > 40 { score -= 1 }

        switch score {
        case 5: return .excellent
        case 3...4: return .good
        case 2: return .fair
        default: return .poor
        }
    }
}