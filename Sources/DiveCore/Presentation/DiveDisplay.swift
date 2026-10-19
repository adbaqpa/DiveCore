import Foundation

// MARK: - Görsel roller

/// Ekranda kullanılan renk rolleri. SwiftUI `Color`'ı değil **anlamsal roller**
/// tutulur; böylece karar mantığı platformdan bağımsız test edilir ve
/// tema/palat değişikliği tek noktadan yapılır.
public enum DiveColorRole: String, Equatable, Codable, Sendable {
    /// Ana veri (derinlik rakamı)
    case hero
    /// İkincil metin
    case secondary
    /// Vurgu / aktif öğe
    case accent
    /// Güvenli durum (yeşil)
    case safe
    /// Dikkat (sarı)
    case caution
    /// Tehlike / hızlı çıkış (kırmızı)
    case danger
    /// Kritik alarm arka planı
    case criticalBackground
    /// Deko zorunluluğu
    case deco
}

/// Metin stilleri için anlamsal roller.
public enum DiveTextRole: String, Equatable, Codable, Sendable {
    /// Ana derinlik rakamı (dev)
    case hero
    /// Büyük ikincil (süre, NDL)
    case large
    /// Orta (tavan, gaz)
    case medium
    /// Küçük etiket
    case small
    /// Çok küçük (birim, tarih)
    case micro
    /// AOD sadeleştirilmiş
    case alwaysOn
}

// MARK: - Göstergeler

/// Çıkış hızı göstergesi durumu.
public enum AscentRateLevel: String, Equatable, Codable, Sendable {
    case safe
    case caution
    case danger
    case descending
    case surface

    /// Göstergenin renk rolü.
    public var colorRole: DiveColorRole {
        switch self {
        case .safe: return .safe
        case .caution: return .caution
        case .danger: return .danger
        case .descending: return .accent
        case .surface: return .secondary
        }
    }

    /// Gösterge sembolü.
    public var symbol: String {
        switch self {
        case .safe: return "checkmark"
        case .caution: return "exclamationmark"
        case .danger: return "arrow.up"
        case .descending: return "arrow.down"
        case .surface: return "minus"
        }
    }

    /// AOD'da kullanılacak tek karakter (daha okunaklı).
    public var aodSymbol: String {
        switch self {
        case .safe: return "✓"
        case .caution: return "!"
        case .danger: return "▲"
        case .descending: return "▼"
        case .surface: return "–"
        }
    }
}

/// Çıkış hızı göstergesi (dairesel/çubuk gösterge için).
public struct AscentRateIndicator: Equatable, Codable, Sendable {
    /// Yumuşatılmış hız (m/dk, pozitif = yukarı)
    public let rate: Double
    public let level: AscentRateLevel
    /// 0...1 arası dolgu oranı (0 = 0 m/dk, 1 = 15 m/dk)
    public let fill: Double
    /// "9.2" gibi gösterim
    public let text: String
    /// AOD'da tek satır etiket
    public let aodLabel: String

    public init(rate: Double, level: AscentRateLevel, fill: Double,
                text: String, aodLabel: String) {
        self.rate = rate
        self.level = level
        self.fill = fill
        self.text = text
        self.aodLabel = aodLabel
    }

    /// Hız ve durumdan gösterge üretir.
    public init(rate: Double, depth: Double, cautionThreshold: Double = DiveSafetyLimits.cautionAscentRate) {
        let level: AscentRateLevel
        switch AscentRateStatus.evaluate(rate: rate, depth: depth) {
        case .safe: level = .safe
        case .caution: level = .caution
        case .danger: level = .danger
        case .descending: level = .descending
        case .surface: level = .surface
        }
        self.rate = rate
        self.level = level
        self.fill = min(1.0, abs(rate) / 15.0)
        self.text = String(format: "%.1f", rate)
        self.aodLabel = abs(rate) < 0.5 ? "—" : String(format: "%.0f", abs(rate))
    }
}

/// Derinlik göstergesi (gösterge çubuğu/alan dolgusu).
public struct DepthIndicator: Equatable, Codable, Sendable {
    /// Anlık derinlik (m)
    public let depth: Double
    /// Dalışın azami derinliği (m)
    public let maxDepth: Double
    /// Ölçek derinliği (gösterge %100'e ulaşır) — en az 10 m
    public let scaleDepth: Double
    /// Anlık derinliğin ölçeğe oranı (0...1)
    public let fraction: Double
    /// Azami derinliğin ölçeğe oranı (0...1) — işaret olarak
    public let maxFraction: Double

    public init(depth: Double, maxDepth: Double) {
        let scale = max(10.0, maxDepth * 1.25)
        self.depth = depth
        self.maxDepth = maxDepth
        self.scaleDepth = scale
        self.fraction = min(1, max(0, depth / scale))
        self.maxFraction = min(1, max(0, maxDepth / scale))
    }
}

/// Pusola / yön göstergesi.
public struct CompassIndicator: Equatable, Codable, Sendable {
    /// Ana yön (derece, 0 = kuzey). `nil` ise pusola verisi yok.
    public let heading: Double?
    /// 16 yönlü Türkçe kısaltma (K, KD, D, GD, G, GB, B, KB)
    public let cardinal: String
    /// 0...360'e normalize edilmiş açı
    public let normalized: Double
    /// Kalibrasyon gerekip gerekmediği (konum servisi izni yoksa)
    public var needsCalibration: Bool { heading == nil }

    /// 16 yönlü Türkçe pusola kısaltmaları.
    /// K = Kuzey, D = Doğu, G = Güney, B = Batı
    private static let points: [(Double, String)] = [
        (0, "K"), (22.5, "KKD"), (45, "KD"), (67.5, "DKD"),
        (90, "D"), (112.5, "DGB"), (135, "GB"), (157.5, "GKB"),
        (180, "G"), (202.5, "GKB"), (225, "GB"), (247.5, "DGB"),
        (270, "B"), (292.5, "BKB"), (315, "KB"), (337.5, "KKB")
    ]

    public init(heading: Double?) {
        self.heading = heading
        if let heading {
            let normalized = heading.truncatingRemainder(dividingBy: 360)
            self.normalized = normalized < 0 ? normalized + 360 : normalized
            let index = Int(((self.normalized + 11.25) / 22.5).rounded(.down)) % 16
            self.cardinal = CompassIndicator.points[max(0, index)].1
        } else {
            self.normalized = 0
            self.cardinal = "—"
        }
    }

    /// Belirli bir kuzey kaydırma açısı için gösterge çubuğu kaydırması
    /// (UI çizimi için): -60°...+60°.
    public static func tickOffset(forHeading heading: Double, visibleDegrees: Double = 120) -> Double? {
        var delta = heading - 0
        delta = delta.truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        guard abs(delta) <= visibleDegrees / 2 else { return nil }
        return delta / (visibleDegrees / 2)
    }
}

/// Emniyet durağı göstergesi.
public struct SafetyStopIndicator: Equatable, Codable, Sendable {
    public let isActive: Bool
    public let isComplete: Bool
    public let wasAbandoned: Bool
    /// "03:00" gibi geri sayım
    public let remainingText: String
    /// 0...1 ilerleme
    public let progress: Double
    /// Başlık ("Emniyet Durağı")
    public let title: String
    /// Alt bilgi ("Tamamlandı" / "5 m'de 3 dk")
    public let subtitle: String

    public init(state: SafetyStopState) {
        self.isActive = state.isActive
        self.isComplete = state.isComplete
        self.wasAbandoned = state.wasAbandoned
        self.remainingText = DurationFormatter.clock(state.remaining)
        self.progress = state.progress
        self.title = "Emniyet Durağı"

        if state.isComplete {
            self.subtitle = "Tamamlandı ✓"
        } else if state.wasAbandoned {
            self.subtitle = "Tamamlanmadı"
        } else if state.isActive {
            self.subtitle = "3 dakika bekle"
        } else {
            self.subtitle = "\(Int(state.requiredDepth)) m'ye in"
        }
    }
}

/// Dekompresyon bilgisi göstergesi.
public struct DecoIndicator: Equatable, Codable, Sendable {
    public let hasObligation: Bool
    /// "3.0" veya "—"
    public let ceilingText: String
    /// "3 m" veya "—"
    public let nextStopText: String
    /// "08:24"
    public let ttsText: String
    /// "%112"
    public let gf99Text: String
    /// Tam sayı
    public let gf99: Int

    public init(state: DiveState) {
        self.hasObligation = state.ceilingDepth > 0
        self.ceilingText = state.ceilingDepth > 0
            ? String(format: "%.1f", state.ceilingDepth) : "—"
        self.nextStopText = state.nextStopDepth.map { "\(Int($0)) m" } ?? "—"
        self.ttsText = DurationFormatter.clock(state.timeToSurface)
        self.gf99 = Int(state.gf99.rounded())
        self.gf99Text = "\(gf99)%"
    }
}

// MARK: - Banner

/// Ekranda üstte gösterilen önemli mesaj.
public struct DiveBanner: Equatable, Codable, Sendable {

    public enum Kind: String, Equatable, Codable, Sendable {
        case fastAscent = "fastAscent"
        case ceilingViolation = "ceilingViolation"
        case ndlReached = "ndlReached"
        case oxygen = "oxygen"
        case cns = "cns"
        case otu = "otu"
        case mod = "mod"
        case safetyStop = "safetyStop"
        case gasSwitch = "gasSwitch"
    }

    public let kind: Kind
    public let severity: DiveWarning.Severity
    public let title: String
    public let message: String
    public let colorRole: DiveColorRole

    public init(kind: Kind, severity: DiveWarning.Severity,
                title: String, message: String) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.message = message
        self.colorRole = DiveBanner.colorRole(for: severity)
    }

    static func colorRole(for severity: DiveWarning.Severity) -> DiveColorRole {
        switch severity {
        case .info: return .accent
        case .caution: return .caution
        case .warning: return .caution
        case .critical: return .danger
        }
    }

    /// En kritik uyarıdan banner üretir (yoksa `nil`).
    public static func make(from warnings: [DiveWarning]) -> DiveBanner? {
        guard let worst = warnings.max(by: { $0.severity < $1.severity }) else { return nil }

        let kind: Kind
        let title: String
        switch worst.kind {
        case .fastAscent:
            kind = .fastAscent
            title = "HIZLI ÇIKIŞ"
        case .ceilingViolation:
            kind = .ceilingViolation
            title = "TAVAN İHLALİ"
        case .noDecoLimitReached:
            kind = .ndlReached
            title = "DEKO ZORUNLU"
        case .oxygenWarning:
            kind = .oxygen
            title = "OKSİJEN"
        case .cnsLimit:
            kind = .cns
            title = "CNS"
        case .otuLimit:
            kind = .otu
            title = "OTU"
        case .depthExceeded:
            kind = .mod
            title = "MOD AŞIMI"
        case .safetyStopSkipped:
            kind = .safetyStop
            title = "EMNİYET DURAĞI"
        case .gasSwitch:
            kind = .gasSwitch
            title = "GAZ"
        }
        return DiveBanner(kind: kind, severity: worst.severity,
                          title: title, message: worst.message)
    }
}

// MARK: - Ekran modu

/// Dalış ekranının hangi modda olduğu.
public enum DiveScreenMode: String, Equatable, Codable, Sendable {
    case preDive
    case diving
    case safetyStop
    case decoObligation
    case surfaced
    case summary
}

// MARK: - Görüntülenebilir durum

/// Ekranda gösterilecek **tüm** metin ve gösterge değerleri.
///
/// SwiftUI görünümleri yalnızca bu yapıyı okur; burada hiçbir karar
/// "görünüm içinde" verilmez. Böylece AOD/aktif ekran farkı dahil her şey
/// test edilir.
public struct DiveDisplayState: Equatable, Codable, Sendable {

    public var mode: DiveScreenMode
    /// Always-On Display modu (sadelik/ kontrast düşürülür)
    public var isAlwaysOn: Bool
    /// Ekran teması (ADIM 11) — pil optimizasyonunun görsel tarafı
    public var theme: DiveDisplayTheme
    /// Temaya göre arka plan rengi (RGB) — `DiveWatchUI` yalnızca çevirir
    public var backgroundRGB: DiveRGB
    /// Temaya göre bir rengin RGB karşılığı
    public var themeSpec: DiveThemeSpec
    /// İkincil ayrıntılar gösteriliyor mu (AOD/night tasarrufu)
    public var showsSecondaryDetails: Bool
    /// Saniye hanesi gösteriliyor mu
    public var showsSeconds: Bool

    // Ana veri
    public var depthText: String
    public var depthUnit: String
    public var maxDepthText: String
    public var diveTimeText: String
    public var temperatureText: String
    public var gasLabel: String
    public var phaseText: String

    // Dekompresyon
    public var ndlText: String
    public var hasNdl: Bool
    public var deco: DecoIndicator
    public var safetyStop: SafetyStopIndicator

    // Göstergeler
    public var depthIndicator: DepthIndicator
    public var ascentRate: AscentRateIndicator
    public var compass: CompassIndicator

    // Alarm
    public var banner: DiveBanner?
    public var isAlarmActive: Bool

    // Görsel roller
    public var depthColorRole: DiveColorRole
    public var ndlColorRole: DiveColorRole
    public var backgroundColorRole: DiveColorRole
    public var depthTextRole: DiveTextRole
    public var timeTextRole: DiveTextRole

    public init(mode: DiveScreenMode,
                isAlwaysOn: Bool,
                theme: DiveDisplayTheme = .standard,
                depthText: String,
                depthUnit: String,
                maxDepthText: String,
                diveTimeText: String,
                temperatureText: String,
                gasLabel: String,
                phaseText: String,
                ndlText: String,
                hasNdl: Bool,
                deco: DecoIndicator,
                safetyStop: SafetyStopIndicator,
                depthIndicator: DepthIndicator,
                ascentRate: AscentRateIndicator,
                compass: CompassIndicator,
                banner: DiveBanner?,
                isAlarmActive: Bool,
                depthColorRole: DiveColorRole,
                ndlColorRole: DiveColorRole,
                backgroundColorRole: DiveColorRole,
                depthTextRole: DiveTextRole,
                timeTextRole: DiveTextRole) {
        self.mode = mode
        self.isAlwaysOn = isAlwaysOn
        let spec = DiveThemeCatalog.spec(for: theme)
        self.theme = theme
        self.themeSpec = spec
        self.backgroundRGB = spec.background
        self.showsSecondaryDetails = spec.showsSecondaryDetails
        self.showsSeconds = spec.showsSeconds
        self.depthText = depthText
        self.depthUnit = depthUnit
        self.maxDepthText = maxDepthText
        self.diveTimeText = diveTimeText
        self.temperatureText = temperatureText
        self.gasLabel = gasLabel
        self.phaseText = phaseText
        self.ndlText = ndlText
        self.hasNdl = hasNdl
        self.deco = deco
        self.safetyStop = safetyStop
        self.depthIndicator = depthIndicator
        self.ascentRate = ascentRate
        self.compass = compass
        self.banner = banner
        self.isAlarmActive = isAlarmActive
        self.depthColorRole = depthColorRole
        self.ndlColorRole = ndlColorRole
        self.backgroundColorRole = backgroundColorRole
        self.depthTextRole = depthTextRole
        self.timeTextRole = timeTextRole
    }
}

// MARK: - Görüntü üreticisi

/// `DiveState` → `DiveDisplayState` dönüşümü (saf fonksiyon).
public enum DiveDisplayBuilder {

    /// AOD modunda gösterilecek azami satır sayısı (yalınlık).
    public static let alwaysOnLineLimit = 3

    public static func build(from state: DiveState,
                             isAlwaysOn: Bool = false,
                             theme: DiveDisplayTheme = .standard) -> DiveDisplayState {
        let mode = screenMode(for: state)
        let spec = DiveThemeCatalog.spec(for: theme)
        let deco = DecoIndicator(state: state)
        let safetyStop = SafetyStopIndicator(state: state.safetyStop)
        let depthIndicator = DepthIndicator(depth: state.currentDepth, maxDepth: state.maxDepth)
        let ascentRate = AscentRateIndicator(rate: state.ascentRate, depth: state.currentDepth)
        let compass = CompassIndicator(heading: state.heading)
        let banner = DiveBanner.make(from: state.warnings)

        let critical = banner?.severity == .critical
        let hasNdl = state.noDecompressionLimit > 0

        return DiveDisplayState(
            mode: mode,
            isAlwaysOn: isAlwaysOn,
            theme: theme,

            depthText: String(format: "%.1f", state.currentDepth),
            depthUnit: "m",
            // Pil tasarrufu: ikincil ayrıntılar gizlenebilir
            maxDepthText: spec.showsSecondaryDetails
                ? String(format: "%.1f", state.maxDepth) : "—",
            diveTimeText: spec.showsSeconds
                ? DurationFormatter.clock(state.diveTime)
                : DurationFormatter.minutesShort(state.diveTime),
            temperatureText: spec.showsSecondaryDetails
                ? String(format: "%.0f°C", state.waterTemperature) : "",
            gasLabel: spec.showsSecondaryDetails ? state.gas.label : "",
            phaseText: state.phase.displayName,

            ndlText: hasNdl ? DurationFormatter.clock(state.noDecompressionLimit) : "—",
            hasNdl: hasNdl,
            deco: deco,
            safetyStop: safetyStop,

            depthIndicator: depthIndicator,
            ascentRate: ascentRate,
            compass: compass,

            banner: (isAlwaysOn || !spec.showsInfoBanner)
                && banner?.severity != .critical ? nil : banner,
            isAlarmActive: critical,

            // Yüzeyde ve sığ sularda derinlik nötr (beyaz); derinlik arttıkça
            // vurgu rengi kullanılır — AOD'da kontrast okunabilirliği için.
            depthColorRole: state.currentDepth < 0.5 ? .secondary : .hero,
            ndlColorRole: ndlColorRole(for: state, mode: mode),
            backgroundColorRole: critical ? .criticalBackground : .hero,
            depthTextRole: isAlwaysOn ? .alwaysOn : .hero,
            timeTextRole: isAlwaysOn ? .alwaysOn : .large)
    }

    /// Ekran modu.
    public static func screenMode(for state: DiveState) -> DiveScreenMode {
        switch state.phase {
        case .preDive: return .preDive
        case .surfaced: return .surfaced
        case .ended: return .summary
        case .safetyStop: return .safetyStop
        case .decoStop: return .decoObligation
        default:
            return state.ceilingDepth > 0 ? .decoObligation : .diving
        }
    }

    /// NDL/tavan metninin rengi.
    public static func ndlColorRole(for state: DiveState,
                                    mode: DiveScreenMode) -> DiveColorRole {
        if state.warnings.contains(where: { $0.kind == .ceilingViolation }) {
            return .danger
        }
        if state.ceilingDepth > 0 { return .deco }
        if state.noDecompressionLimit <= 0 { return .caution }

        // Son 5 dakikada sarı, 2 dakikada kırmızı (NDL uyarısı)
        if state.noDecompressionLimit <= 120 { return .danger }
        if state.noDecompressionLimit <= 300 { return .caution }
        return .safe
    }
}