import Foundation

/// ADIM 9 — komplikasyon **modları**.
///
/// watchOS'ta her komplikasyon ailesi (modüler, diyalog) tek bir veri
/// kaynağını okur. Dalış sırasında "anlık derinlik + NDL", dalış dışındayken
/// "son yüzey aralığı / uçuş yasağı" göstermek isteriz; ancak kullanıcı
/// komplikasyonu yüzeydeyken de görür. Bu nedenle her mod, kendi doğal
/// fazında **birincil**, diğerinde **yedek** (fallback) özellik gösterir.
///
/// ## Neden çekirdekte?
/// Hangi modun hangi fazda ne göstereceği bir *kural*dır ve kullanıcıya
/// göre değişmez; bu yüzden test edilebilir çekirdekte tutulur. watchOS
/// katmanı yalnızca `DiveComplicationData` üretilen veriyi çizer.
public enum DiveComplicationMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Dalış sırasında anlık derinlik + geçen süre
    case liveDepth
    /// Dalış sırasında anlık derinlik + kalan NDL (deko varsa tavan/TTS)
    case liveNDL
    /// Yüzeyde son yüzey aralığı + GF99 + desatürasyon
    case surfaceInterval
    /// Yüzeyde uçuş yasağı geri sayımı
    case noFly

    public var id: String { rawValue }

    /// Yalnızca dalış sırasında birincil anlam taşır.
    public var isLive: Bool { self == .liveDepth || self == .liveNDL }

    /// Yalnızca yüzeyde birincil anlam taşır.
    public var isSurface: Bool { self == .surfaceInterval || self == .noFly }

    /// Kullanıcıya gösterilecek ad.
    public var title: String {
        switch self {
        case .liveDepth: return "Canlı Derinlik"
        case .liveNDL: return "Canlı NDL"
        case .surfaceInterval: return "Yüzey Aralığı"
        case .noFly: return "Uçuş Yasağı"
        }
    }

    /// Kısa açıklama (ayarlar listesinde).
    public var detail: String {
        switch self {
        case .liveDepth: return "Anlık derinlik, süre ve gaz"
        case .liveNDL: return "Anlık derinlik ve kalan NDL/tavan"
        case .surfaceInterval: return "Son yüzey aralığı, GF99 ve desatürasyon"
        case .noFly: return "Uçuş yasağı geri sayımı ve kabin profili"
        }
    }

    /// Aynı fazın yedek modu (fallback).
    public var fallback: DiveComplicationMode {
        switch self {
        case .liveDepth: return .liveNDL
        case .liveNDL: return .liveDepth
        case .surfaceInterval: return .noFly
        case .noFly: return .surfaceInterval
        }
    }

    /// Dalış **sürerken** bu mod kullanılırsa gösterilecek canlı mod.
    public var liveAlternative: DiveComplicationMode {
        isLive ? self : .liveDepth
    }

    /// Dalış **dışındayken** bu mod kullanılırsa gösterilecek yüzey modu.
    public var surfaceAlternative: DiveComplicationMode {
        isSurface ? self : .surfaceInterval
    }

    /// Verilen fazda uygun mu?
    public func isSuitable(for state: DiveState, isDiving: Bool) -> Bool {
        let diving = isDiving && state.phase.isDiving
        return diving == isLive
    }
}

/// Komplikasyon modu çözümleyicisi.
///
/// Kural:
/// 1. Dalış sürüyorsa **canlı** modlar (derinlik / NDL) kullanılır.
/// 2. Yüzeydeyken **yüzey** modları kullanılır; ancak `noFly` modu ancak
///    uçuş yasağı gerçekten varsa anlamlıdır, yoksa `surfaceInterval`
///    gösterilir.
/// 3. Dalış yoksa (hiç dalış yapılmamış) her iki yüzey modu da nötr
///    karşılama gösterir.
public enum DiveComplicationModeResolver {

    /// Kurulu komplikasyonun **etkin** modu.
    public static func effective(mode: DiveComplicationMode,
                                 state: DiveState,
                                 isDiving: Bool,
                                 status: SurfaceIntervalStatus?) -> DiveComplicationMode {
        let diving = isDiving && state.phase.isDiving

        if diving {
            return mode.liveAlternative
        }

        // Yüzeyde: canlı modlar yüzey ailesine düşer. Yasa varsa daha
        // önemli olan `noFly` gösterilir.
        guard mode.isSurface else {
            let cleared = status?.isNoFlyCleared ?? true
            return cleared ? .surfaceInterval : .noFly
        }

        // `noFly` modu yalnızca yasa varken anlamlı
        if mode == .noFly, let status, status.isNoFlyCleared {
            return .surfaceInterval
        }
        return mode
    }

    /// Verilen faz için **tüm** uygun modlar (modüler yüz seçimi için).
    public static func availableModes(state: DiveState, isDiving: Bool,
                                      status: SurfaceIntervalStatus?) -> [DiveComplicationMode] {
        let diving = isDiving && state.phase.isDiving
        if diving { return [.liveDepth, .liveNDL] }
        guard let status, !status.isNoFlyCleared else {
            return [.surfaceInterval, .noFly]
        }
        return [.surfaceInterval]
    }
}

/// Yüzey modları için komplikasyon verisi üretimi (ADIM 9).
public enum SurfaceComplicationBuilder {

    /// Yüzey aralığı modu.
    ///
    /// - `circular`: merkezde GF99, çemberde geçen yüzey süresi oranı
    /// - `inline`   : "GF99 %23 · 2s 15dk"
    /// - `rectangular`: üstte desatürasyon, altta uçuş yasağı
    public static func build(mode: DiveComplicationMode,
                             status: SurfaceIntervalStatus,
                             cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel,
                             cabinRemaining: TimeInterval? = nil,
                             style: DiveComplicationData.Style) -> DiveComplicationData {
        let noFlyRemaining = cabinRemaining ?? status.noFlyRemaining
        // Gösterge: GF99 yüksekse dolu (yük kaldıkça dolu).
        let gauge = min(1, max(0, status.gf99 / 120))
        let role: DiveColorRole = status.isNoFlyCleared ? .safe : .caution
        let intent = status.isNoFlyCleared ? DiveActionIntent.startDive : DiveActionIntent.none
        // Yalnızca `noFly` modunda geri sayım bir "alarm" gibi sunulur;
        // yüzey aralığı modu yüksek GF99'u bilgi olarak gösterir.
        let alarming = mode == .noFly && !status.isNoFlyCleared

        switch style {
        case .inline:
            if mode == .noFly {
                return DiveComplicationData(
                    style: style,
                    primaryText: status.isNoFlyCleared
                        ? "Uçuş serbest"
                        : "Uçuş \(DurationFormatter.hoursMinutes(status.noFlyRemaining))",
                    secondaryText: status.gf99Text,
                    tertiaryText: "",
                    accentRole: role,
                    gauge: gauge,
                    isAlarmActive: !status.isNoFlyCleared,
                    intentLabel: intent.label)
            }
            return DiveComplicationData(
                style: style,
                primaryText: "GF99 \(status.gf99Text) · \(status.elapsedText)",
                secondaryText: status.recommendation,
                tertiaryText: "",
                accentRole: role,
                gauge: gauge,
                isAlarmActive: false,
                intentLabel: intent.label)

        case .circular:
            return DiveComplicationData(
                style: style,
                primaryText: (mode == .noFly && !status.isNoFlyCleared)
                    ? DurationFormatter.clock(status.noFlyRemaining)
                    : status.gf99Text,
                secondaryText: mode == .noFly ? "uçuş yasağı" : "GF99",
                tertiaryText: status.elapsedText,
                accentRole: role,
                gauge: gauge,
                isAlarmActive: alarming,
                intentLabel: intent.label)

        case .rectangular:
            return DiveComplicationData(
                style: style,
                primaryText: mode == .noFly
                    ? "Uçuş yasağı \(DurationFormatter.hoursMinutes(status.noFlyRemaining))"
                    : "Yüzey \(status.elapsedText)",
                secondaryText: "GF99 \(status.gf99Text) · desat \(DurationFormatter.clock(status.desaturationRemaining))",
                tertiaryText: cabin.title + " " + DurationFormatter.hoursMinutes(noFlyRemaining),
                accentRole: role,
                gauge: gauge,
                isAlarmActive: alarming,
                intentLabel: intent.label)

        case .corner:
            return DiveComplicationData(
                style: style,
                primaryText: (mode == .noFly && !status.isNoFlyCleared)
                    ? DurationFormatter.clock(status.noFlyRemaining)
                    : status.gf99Text,
                secondaryText: mode == .noFly ? "airplane" : "drop.degreesign.down",
                tertiaryText: status.elapsedText,
                accentRole: role,
                gauge: gauge,
                isAlarmActive: alarming,
                intentLabel: intent.label)
        }
    }
}

// MARK: - Canlı NDL modu

public extension DiveComplicationBuilder {

    /// `liveNDL` modu: anlık derinlik + kalan NDL (deko varsa tavan/TTS).
    ///
    /// - Note: `liveDepth` modu zaten derinlik + süre gösterdiği için
    ///   ayrı bir üreticiye gerek yoktur; burada yalnızca NDL varyantı var.
    static func buildLiveNDL(from state: DiveState,
                             style: DiveComplicationData.Style) -> DiveComplicationData {
        let display = DiveDisplayBuilder.build(from: state)

        // Göstergede derinlik doluluğu kullanılır (NDL'nin başlangıç değeri
        // dalış boyunca sabit olmadığından oran olarak anlamlı değildir);
        // NDL/tavan değeri metin olarak taşınır.
        let gauge = display.depthIndicator.fraction
        let value = display.hasNdl ? display.ndlText : display.deco.ceilingText
        let caption = display.hasNdl ? "NDL" : "tavan"

        let role: DiveColorRole = display.isAlarmActive ? .danger
            : (display.hasNdl ? .accent : .caution)

        switch style {
        case .inline:
            return DiveComplicationData(
                style: style,
                primaryText: "\(display.depthText)m · \(value)",
                secondaryText: display.gasLabel,
                tertiaryText: "",
                accentRole: role,
                gauge: gauge,
                isAlarmActive: display.isAlarmActive,
                intentLabel: DiveActionButtonResolver.intent(for: state,
                                                              isDiving: state.phase.isDiving).label)
        case .circular:
            return DiveComplicationData(
                style: style,
                primaryText: display.depthText,
                secondaryText: caption,
                tertiaryText: value,
                accentRole: role,
                gauge: gauge,
                isAlarmActive: display.isAlarmActive,
                intentLabel: DiveActionButtonResolver.intent(for: state,
                                                              isDiving: state.phase.isDiving).label)
        case .rectangular:
            return DiveComplicationData(
                style: style,
                primaryText: "\(display.depthText)m  \(display.maxDepthText)m",
                secondaryText: "\(caption) \(value) · \(display.gasLabel)",
                tertiaryText: display.diveTimeText,
                accentRole: role,
                gauge: gauge,
                isAlarmActive: display.isAlarmActive,
                intentLabel: DiveActionButtonResolver.intent(for: state,
                                                              isDiving: state.phase.isDiving).label)
        case .corner:
            return DiveComplicationData(
                style: style,
                primaryText: display.depthText,
                secondaryText: "gauge.with.dots.needle.bottom.50percent",
                tertiaryText: value,
                accentRole: role,
                gauge: gauge,
                isAlarmActive: display.isAlarmActive,
                intentLabel: DiveActionButtonResolver.intent(for: state,
                                                              isDiving: state.phase.isDiving).label)
        }
    }

    /// Etkin moda göre komplikasyon verisi (canlı + yüzey tek giriş noktası).
    static func build(mode: DiveComplicationMode,
                      state: DiveState,
                      isDiving: Bool,
                      style: DiveComplicationData.Style,
                      status: SurfaceIntervalStatus? = nil,
                      cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel,
                      cabinRemaining: TimeInterval? = nil) -> DiveComplicationData {
        let effective = DiveComplicationModeResolver.effective(
            mode: mode, state: state, isDiving: isDiving, status: status)

        switch effective {
        case .liveDepth:
            return DiveComplicationBuilder.build(from: state, style: style)
        case .liveNDL:
            return DiveComplicationBuilder.buildLiveNDL(from: state, style: style)
        case .surfaceInterval, .noFly:
            guard let status else {
                // Dalış kaydı yoksa nötr karşılama göster.
                return DiveComplicationBuilder.build(from: state, style: style)
            }
            return SurfaceComplicationBuilder.build(mode: effective,
                                                   status: status,
                                                   cabin: cabin,
                                                   cabinRemaining: cabinRemaining,
                                                   style: style)
        }
    }
}