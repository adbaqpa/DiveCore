import Foundation

// MARK: - Dalış fazı

/// Dalışın yaşam döngüsü fazı.
public enum DivePhase: String, Equatable, Codable, Sendable, CaseIterable {
    /// Dalış öncesi hazırlık (yüzeyde).
    case preDive = "preDive"
    /// İniş.
    case descending = "descending"
    /// Dipte / sabit derinlikte.
    case bottom = "bottom"
    /// Yükseliş.
    case ascending = "ascending"
    /// Zorunlu dekompresyon durağında.
    case decoStop = "decoStop"
    /// Emniyet durağı (5 m / 3 m).
    case safetyStop = "safetyStop"
    /// Yüzeye çıktı, dalış kapandı (yüzey aralığı).
    case surfaced = "surfaced"
    /// Dalış tamamen sonlandı.
    case ended = "ended"

    /// Dalış sürüyor mu?
    public var isDiving: Bool {
        switch self {
        case .preDive, .surfaced, .ended: return false
        default: return true
        }
    }

    public var displayName: String {
        switch self {
        case .preDive: return "Hazır"
        case .descending: return "İniş"
        case .bottom: return "Dipte"
        case .ascending: return "Çıkış"
        case .decoStop: return "Deko Durağı"
        case .safetyStop: return "Emniyet Durağı"
        case .surfaced: return "Yüzey"
        case .ended: return "Bitti"
        }
    }
}

// MARK: - Çıkış hızı durumu

/// Çıkış hızının güvenlik durumu (görsel + dokunsal alarm kaynağı).
public enum AscentRateStatus: String, Equatable, Codable, Sendable {
    case safe = "safe"                 // yeşil
    case caution = "caution"           // sarı
    case danger = "danger"             // kırmızı
    case descending = "descending"     // inişteyken
    case surface = "surface"           // yüzeydeyken

    /// Hız (m/dk) ve derinliğe göre durum.
    public static func evaluate(rate: Double, depth: Double) -> AscentRateStatus {
        if depth <= 0.2 { return .surface }
        if rate < -0.5 { return .descending }
        if rate > DiveSafetyLimits.maximumAscentRate { return .danger }
        if rate > DiveSafetyLimits.cautionAscentRate { return .caution }
        return .safe
    }

    /// Kısa simge (AOD ekranı için).
    public var symbol: String {
        switch self {
        case .safe: return "✓"
        case .caution: return "!"
        case .danger: return "▲"
        case .descending: return "▼"
        case .surface: return "—"
        }
    }
}

// MARK: - Emniyet durağı

/// Emniyet durağı (safety stop) durumu.
public struct SafetyStopState: Equatable, Codable, Sendable {
    /// Durağın gerektirdiği azami derinlik (m) — 5 m veya 3 m.
    public let requiredDepth: Double
    /// Toplam gereken süre (saniye).
    public let requiredDuration: TimeInterval
    /// Tamamlanan süre (saniye).
    public var accumulated: TimeInterval
    /// Durağın şu anda aktif olup olmadığı.
    public var isActive: Bool
    /// Dalgıç bu bölgeden ayrıldı mı (sayaç durduruldu).
    public var wasAbandoned: Bool

    public init(
        requiredDepth: Double = DiveSafetyLimits.safetyStopDepth,
        requiredDuration: TimeInterval = DiveSafetyLimits.safetyStopDuration,
        accumulated: TimeInterval = 0,
        isActive: Bool = false,
        wasAbandoned: Bool = false
    ) {
        self.requiredDepth = requiredDepth
        self.requiredDuration = requiredDuration
        self.accumulated = accumulated
        self.isActive = isActive
        self.wasAbandoned = wasAbandoned
    }

    public var remaining: TimeInterval { max(0, requiredDuration - accumulated) }
    public var progress: Double {
        guard requiredDuration > 0 else { return 1 }
        return (accumulated / requiredDuration).clamped(to: 0...1)
    }
    public var isComplete: Bool { accumulated >= requiredDuration }

    /// Kalan süreyi biçimlendirilmiş döndürür (mm:ss).
    public var remainingFormatted: String { DurationFormatter.clock(remaining) }
}

// MARK: - Uyarılar

/// Dalış sırasında üretilen uyarı. ADIM 4'te ekran/titreşim mantığına bağlanır.
public struct DiveWarning: Equatable, Codable, Sendable, Identifiable {

    public enum Kind: String, Equatable, Codable, Sendable {
        case fastAscent = "fastAscent"             // 10 m/dk üstü çıkış
        case ceilingViolation = "ceilingViolation" // tavan ihlali
        case noDecoLimitReached = "ndlReached"     // NDL doldu
        case oxygenWarning = "o2Warning"           // PO2 sınırına yaklaşıldı
        case cnsLimit = "cnsLimit"                 // CNS %80+
        case otuLimit = "otuLimit"                 // OTU %80+
        case gasSwitch = "gasSwitch"               // gaz değişikliği
        case safetyStopSkipped = "safetyStopSkipped"
        case depthExceeded = "depthExceeded"       // MOD aşımı
    }

    public enum Severity: Int, Equatable, Codable, Sendable, Comparable {
        case info = 0
        case caution = 1
        case warning = 2
        case critical = 3

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var displayName: String {
            switch self {
            case .info: return "Bilgi"
            case .caution: return "Dikkat"
            case .warning: return "Uyarı"
            case .critical: return "Kritik"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let severity: Severity
    public let message: String
    /// Alarmın ne zaman tekrar sesleneceği gerektiği (saniye) — ileride.
    public let raisedAtElapsed: TimeInterval

    public init(
        id: UUID = UUID(),
        kind: Kind,
        severity: Severity,
        message: String,
        raisedAtElapsed: TimeInterval
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.message = message
        self.raisedAtElapsed = raisedAtElapsed
    }
}

// MARK: - DiveState

/// Dalış bilgisayarının anlık, tam durumu.
///
/// Bu yapı **değer tipidir** ve `Codable`'dır; böylece
/// - SwiftUI tarafında `@Published` / ObservableObject ile yayınlanabilir,
/// - SwiftData'ya ve `WatchConnectivity` ile iPhone'a aktarılabilir.
public struct DiveState: Equatable, Codable, Sendable {

    // MARK: Yaşam döngüsü

    public var phase: DivePhase
    /// Dalışın başlangıç zamanı (epoch). Çekirdek modülde `Date` saklanır ama
    /// hesaplama mantığı `Date.now` çağırmaz — test determinizmini korur.
    public var startDate: Date?
    /// Dalışın bitiş zamanı.
    public var endDate: Date?

    // MARK: Derinlik

    /// Anlık derinlik (m)
    public var currentDepth: Double
    /// Dalıştaki azami derinlik (m)
    public var maxDepth: Double
    /// Ortalama derinlik (m)
    public var averageDepth: Double
    /// Ambient basınç (bar)
    public var ambientPressure: Double

    // MARK: Süreler

    /// Dalış süresi (saniye) — yüzeyden ayrıldığı andan itibaren.
    public var diveTime: TimeInterval
    /// Yüzeyde kalınan toplam süre (saniye).
    public var surfaceInterval: TimeInterval
    /// Önceki dalıştan bu dalışa kadar geçen yüzey aralığı (saniye).
    public var previousSurfaceInterval: TimeInterval

    // MARK: Ortam

    /// Su sıcaklığı (°C)
    public var waterTemperature: Double
    /// Yüzey sıcaklığı (°C)
    public var surfaceTemperature: Double
    public var water: DivePhysics.WaterType

    // MARK: Hareket

    /// Çıkış hızı (m/dk, pozitif = yukarı)
    public var ascentRate: Double
    /// İniş hızı (m/dk, pozitif değer)
    public var descentRate: Double
    /// Pusula yönü (derece, 0 = kuzey)
    public var heading: Double?

    // MARK: Gaz / oksijen

    public var gas: GasMix
    /// Kullanılan gazların dizisi (geçişler dahil)
    public var gases: [GasMix]
    public var gasIndex: Int
    /// Solunan PO2 (bar)
    public var oxygenPartialPressure: Double
    /// Maksimum çalışma derinliği (m)
    public var maximumOperatingDepth: Double

    // MARK: Dekompresyon

    /// NDL — kalan no-dive süresi (saniye). Deko yükümlülüğü varsa 0.
    public var noDecompressionLimit: TimeInterval
    /// Mevcut tavan (ceiling) (m)
    public var ceilingDepth: Double
    /// Sıradaki zorunlu durak (m); dekosyon yoksa `nil`.
    public var nextStopDepth: Double?
    /// Yüzeye çıkış süresi (TTS) (saniye)
    public var timeToSurface: TimeInterval
    /// GF99 (%)
    public var gf99: Double
    /// Aktif GF ayarı
    public var gradientFactors: GradientFactors
    /// En baskın kompartmanın N2 basıncı (bar)
    public var leadingTissuePressure: Double
    /// Dekompresyon yükümlülüğü var mı?
    public var hasDecoObligation: Bool { ceilingDepth > 0 }

    // MARK: Oksijen toksisitesi

    /// CNS (%)
    public var cnsPercent: Double
    /// OTU (kümülatif birim)
    public var otuUnits: Double
    /// OTU'nun günlük limitin yüzdesi (%)
    public var otuPercent: Double

    // MARK: Emniyet

    /// Emniyet durağı durumu
    public var safetyStop: SafetyStopState
    /// Çıkış hızı durumu
    public var ascentRateStatus: AscentRateStatus
    /// Aktif uyarılar (kritik olanlar önce)
    public var warnings: [DiveWarning]

    // MARK: Uçuş yasağı

    /// Mevcut kalan desatürasyon süresi (saniye, yüzeyde bekleme)
    public var desaturationRemaining: TimeInterval
    /// Tahmini uçuş yasağı süresi (saniye)
    public var noFlyTime: TimeInterval

    // MARK: - Oluşturucu

    public init(
        phase: DivePhase = .preDive,
        startDate: Date? = nil,
        endDate: Date? = nil,
        currentDepth: Double = 0,
        maxDepth: Double = 0,
        averageDepth: Double = 0,
        ambientPressure: Double = DivePhysics.surfacePressure,
        diveTime: TimeInterval = 0,
        surfaceInterval: TimeInterval = 0,
        previousSurfaceInterval: TimeInterval = 0,
        waterTemperature: Double = 20,
        surfaceTemperature: Double = 20,
        water: DivePhysics.WaterType = .salt,
        ascentRate: Double = 0,
        descentRate: Double = 0,
        heading: Double? = nil,
        gas: GasMix = .air,
        gases: [GasMix] = [.air],
        gasIndex: Int = 0,
        oxygenPartialPressure: Double = 0.21,
        maximumOperatingDepth: Double = GasMix.air.maximumOperatingDepth(),
        noDecompressionLimit: TimeInterval = 0,
        ceilingDepth: Double = 0,
        nextStopDepth: Double? = nil,
        timeToSurface: TimeInterval = 0,
        gf99: Double = 0,
        gradientFactors: GradientFactors = .default,
        leadingTissuePressure: Double = 0.79,
        cnsPercent: Double = 0,
        otuUnits: Double = 0,
        otuPercent: Double = 0,
        safetyStop: SafetyStopState = SafetyStopState(),
        ascentRateStatus: AscentRateStatus = .surface,
        warnings: [DiveWarning] = [],
        desaturationRemaining: TimeInterval = 0,
        noFlyTime: TimeInterval = 0
    ) {
        self.phase = phase
        self.startDate = startDate
        self.endDate = endDate
        self.currentDepth = currentDepth
        self.maxDepth = maxDepth
        self.averageDepth = averageDepth
        self.ambientPressure = ambientPressure
        self.diveTime = diveTime
        self.surfaceInterval = surfaceInterval
        self.previousSurfaceInterval = previousSurfaceInterval
        self.waterTemperature = waterTemperature
        self.surfaceTemperature = surfaceTemperature
        self.water = water
        self.ascentRate = ascentRate
        self.descentRate = descentRate
        self.heading = heading
        self.gas = gas
        self.gases = gases
        self.gasIndex = gasIndex
        self.oxygenPartialPressure = oxygenPartialPressure
        self.maximumOperatingDepth = maximumOperatingDepth
        self.noDecompressionLimit = noDecompressionLimit
        self.ceilingDepth = ceilingDepth
        self.nextStopDepth = nextStopDepth
        self.timeToSurface = timeToSurface
        self.gf99 = gf99
        self.gradientFactors = gradientFactors
        self.leadingTissuePressure = leadingTissuePressure
        self.cnsPercent = cnsPercent
        self.otuUnits = otuUnits
        self.otuPercent = otuPercent
        self.safetyStop = safetyStop
        self.ascentRateStatus = ascentRateStatus
        self.warnings = warnings
        self.desaturationRemaining = desaturationRemaining
        self.noFlyTime = noFlyTime
    }

    // MARK: - Türetilmiş yardımcılar

    public var isDiving: Bool { phase.isDiving }

    /// Anlık çıkış hızı durumu (kendinden hesaplar).
    public var computedAscentRateStatus: AscentRateStatus {
        AscentRateStatus.evaluate(rate: ascentRate, depth: currentDepth)
    }

    /// Formatlanmış derinlik: "24.6"
    public var depthFormatted: String { String(format: "%.1f", currentDepth) }
    /// Formatlanmış maksimum derinlik: "30.2"
    public var maxDepthFormatted: String { String(format: "%.1f", maxDepth) }
    /// Dalış süresi: "24:31"
    public var diveTimeFormatted: String { DurationFormatter.clock(diveTime) }
    /// NDL: "12:40" (sıfırsa "—")
    public var ndlFormatted: String {
        noDecompressionLimit > 0 ? DurationFormatter.clock(noDecompressionLimit) : "—"
    }
    /// Tavan: "3.2" veya "—"
    public var ceilingFormatted: String { ceilingDepth > 0 ? String(format: "%.1f", ceilingDepth) : "—" }
    /// TTS: "9:20"
    public var ttsFormatted: String { DurationFormatter.clock(timeToSurface) }
    /// Uçuş yasağı: "3h 25m"
    public var noFlyFormatted: String { DurationFormatter.hoursMinutes(noFlyTime) }
    /// Sıcaklık: "18°C"
    public var temperatureFormatted: String { String(format: "%.1f°C", waterTemperature) }
    /// CNS: "%34"
    public var cnsFormatted: String { String(format: "%.0f%%", cnsPercent) }
    /// GF99: "24"
    public var gf99Formatted: String { String(format: "%.0f", gf99) }

    /// En kritik uyarı (yoksa `nil`).
    public var mostCriticalWarning: DiveWarning? {
        warnings.max { $0.severity < $1.severity }
    }

    /// Aktif NDL yok ama tavan > 0 ise deko zorunlu.
    public var requiresDecompression: Bool { ceilingDepth > 0 }
}

// MARK: - Süre biçimlendirme

/// Süreleri dalış bilgisayarı standardında biçimlendirir.
public enum DurationFormatter {

    /// "mm:ss" veya "h:mm:ss" biçiminde.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "3h 25m" veya "45m".
    public static func hoursMinutes(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)s \(minutes)dk" }
        if minutes > 0 { return "\(minutes)dk" }
        return "\(total)s"
    }

    /// `clock(_:)` çıktısını saniyeye çevirir.
    ///
    /// - Note: Yalnızca `clock` biçimini ("mm:ss" / "h:mm:ss") çözer; testler
    ///   ve zaman çizelgesi doğrulaması için kullanılır.
    public static func parse(_ text: String) -> TimeInterval {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3:
            return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        case 2:
            return TimeInterval(parts[0] * 60 + parts[1])
        default:
            return 0
        }
    }

    /// "45dk" — dakika cinsinden kısa gösterim.
    public static func minutesShort(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        if minutes >= 60 {
            return "\(minutes / 60)s \(minutes % 60)"
        }
        return "\(minutes)"
    }
}