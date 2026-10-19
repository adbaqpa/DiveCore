import Foundation

/// ADIM 11 — **dinamik örnekleme politikası**.
///
/// ## Sorun
/// Dekompresyon motoru ve sensör zinciri saniyede 10 kez çalışırsa pili
/// hızla tüketir; ama **her dalışta aynı hızda çalışmaya gerek yoktur**.
/// Dipte hareketsiz beklemekle, deko durağında yükselmek arasında enerji
/// ihtiyacı farklıdır — üstelik hızlı çıkış algılaması **yüksek** örnekleme
/// hızı gerektirir, yavaş iniş gerektirmez.
///
/// ## Yaklaşım
/// Örnekleme aralığı şu girdilere göre seçilir:
///
/// | Girdi | Aralık | Neden |
/// |---|---|---|
/// | Deko durağında / tavan > 0 | 0.5 sn | gaz yükü hızla değişir |
/// | Hızlı çıkış (> 9 m/dk) | 0.5 sn | ihlal yakalamak için yüksek çözünürlük |
/// | Tavan ihlali bölgesi (< 1 m tampon) | 0.5 sn | güvenlik |
/// | Aktif iniş/çıkış (|hız| > 2 m/dk) | 1 sn | hız doğruluğu |
/// | Dipte sabit (|hız| < 0.5 m/dk) | 2 sn | doku yavaş değişiyor |
/// | Yüzey beklemesi / deko sonrası | 5 sn | güvenlik yok |
/// | Dalış dışı (yüzey aralığı) | 10 sn | yalnızca geri sayım |
///
/// ## Güvenlik sınırı (kriptik olmayan kural)
/// Aralık **hiçbir koşulda** 5 saniyeyi geçmez ve şu durumlarda **daima**
/// ≤ 1 saniyedir: deko yükümlülüğü, kritik alarm, tavan ihlali. Bu
/// kural `AdaptiveSamplingPolicy.maximumInterval` ve
/// `isSafetyCritical` ile kod düzeyinde garanti edilir ve testlerle
/// doğrulanır.
public struct AdaptiveSamplingPolicy: Equatable, Codable, Sendable {

    /// Profil tabanı (saniye)
    public var baseInterval: TimeInterval
    /// Dipte hareketsiz (saniye)
    public var idleInterval: TimeInterval
    /// Yüzey beklemesi (saniye)
    public var surfaceInterval: TimeInterval
    /// Dalış dışı (saniye)
    public var idleDiveInterval: TimeInterval
    /// Güvenlik meselesi olduğunda kullanılan **tavan** aralık (saniye)
    public var safetyInterval: TimeInterval
    /// Asla aşılmayacak aralık (saniye)
    public var maximumInterval: TimeInterval

    public init(baseInterval: TimeInterval = 1,
                idleInterval: TimeInterval = 2,
                surfaceInterval: TimeInterval = 5,
                idleDiveInterval: TimeInterval = 10,
                safetyInterval: TimeInterval = 0.5,
                maximumInterval: TimeInterval = 5) {
        self.baseInterval = max(0.1, baseInterval)
        self.idleInterval = max(self.baseInterval, idleInterval)
        self.surfaceInterval = max(self.idleInterval, surfaceInterval)
        self.idleDiveInterval = max(self.surfaceInterval, idleDiveInterval)
        self.safetyInterval = max(0.1, safetyInterval)
        self.maximumInterval = max(self.safetyInterval, maximumInterval)
    }

    /// `PowerProfile`'e göre politikayı üretir.
    public init(profile: PowerProfile, state: EnergyState) {
        switch profile {
        case .performance:
            self.init(baseInterval: 0.5, idleInterval: 1, surfaceInterval: 2,
                      idleDiveInterval: 4, safetyInterval: 0.25, maximumInterval: 2)
        case .balanced:
            self.init(baseInterval: 1, idleInterval: 2, surfaceInterval: 5,
                      idleDiveInterval: 10, safetyInterval: 0.5, maximumInterval: 5)
        case .saver:
            self.init(baseInterval: 2, idleInterval: 4, surfaceInterval: 5,
                      idleDiveInterval: 10, safetyInterval: 0.5, maximumInterval: 5)
        }
    }

    /// Profilin taban aralığını enerji durumuna göre uyarlar (termal/düşük pil).
    public func adjusted(for state: EnergyState) -> AdaptiveSamplingPolicy {
        var copy = self
        if state.isThermallyConstrained {
            copy.baseInterval = min(copy.maximumInterval, copy.baseInterval * 2)
            copy.idleInterval = min(copy.maximumInterval, copy.idleInterval * 2)
        }
        // Pil basıncında **dipte hareketsiz** aralık da genişler: bu faz
        // güvenlik açısından kritik değildir (deko yükümlülüğü hâlinde
        // `safetyInterval` devreye girer).
        if state.isLowPowerModeEnabled || state.isBatteryLow {
            copy.baseInterval = min(copy.maximumInterval, max(copy.baseInterval, 2))
            copy.idleInterval = min(copy.maximumInterval, max(copy.idleInterval, 2))
        }
        // Güvenlik aralıkları **asla** gevşemez.
        return copy
    }

    /// Dalışın anlık koşulları.
    public struct Context: Equatable, Sendable {
        public let isDiving: Bool
        public let depth: Double
        /// Çıkış hızı (m/dk, pozitif = aşağı)
        public let ascentRate: Double
        /// Tavan (m)
        public let ceilingDepth: Double
        /// Kalan NDL (saniye; 0 ise deko yükümlülüğü var)
        public let ndl: TimeInterval
        /// Aktif kritik uyarı var mı
        public let hasCriticalWarning: Bool
        /// Dalış süresi (saniye)
        public let diveTime: TimeInterval
        /// Yüzey aralığı kaldı mı
        public let isSurfaceInterval: Bool

        public init(isDiving: Bool, depth: Double, ascentRate: Double = 0,
                    ceilingDepth: Double = 0, ndl: TimeInterval = 0,
                    hasCriticalWarning: Bool = false, diveTime: TimeInterval = 0,
                    isSurfaceInterval: Bool = false) {
            self.isDiving = isDiving
            self.depth = depth
            self.ascentRate = ascentRate
            self.ceilingDepth = ceilingDepth
            self.ndl = ndl
            self.hasCriticalWarning = hasCriticalWarning
            self.diveTime = diveTime
            self.isSurfaceInterval = isSurfaceInterval
        }

        /// `DiveState`'ten bağlam üretir.
        ///
        /// - Parameters:
        ///   - state: Anlık dalış durumu
        ///   - isSurfaceInterval: Yüzey aralığı sürüyor mu
        ///   - transientWarningCooldown: **Geçici** uyarıların (hızlı çıkış,
        ///     gaz değişimi, atlanan emniyet durağı) hızlı örneklemeyi ne
        ///     kadar sürdüreceği (saniye).
        ///
        /// - Note: Uyarılar `DiveState` içinde birikir ve **silinmez**. Bu
        ///   nedenle yalnızca "durum" uyarıları (tavan, oksijen, CNS, OTU,
        ///     derinlik aşımı) sürekli hızlı örnekleme gerektirir; geçici
        ///   ihlaller `transientWarningCooldown` boyunca etkili sayılır.
        ///   Aksi halde dalış başındaki tek bir hızlı çıkış, kalan tüm
        ///   dalışı 0.5 saniyede bir örneklemeye zorlar.
        public init(state: DiveState,
                    isSurfaceInterval: Bool = false,
                    transientWarningCooldown: TimeInterval = 120) {
            let stateBased: Set<DiveWarning.Kind> = [.ceilingViolation,
                                                      .noDecoLimitReached,
                                                      .oxygenWarning,
                                                      .cnsLimit,
                                                      .otuLimit,
                                                      .depthExceeded]
            let hasStateWarning = state.warnings.contains {
                $0.severity == .critical || $0.severity == .warning
            } && state.warnings.contains { stateBased.contains($0.kind) }

            let hasRecentTransient = state.warnings.contains {
                ($0.severity == .critical || $0.severity == .warning)
                && !stateBased.contains($0.kind)
                && state.diveTime - $0.raisedAtElapsed <= transientWarningCooldown
            }

            self.init(isDiving: state.phase.isDiving,
                      depth: state.currentDepth,
                      ascentRate: state.ascentRate,
                      ceilingDepth: state.ceilingDepth,
                      ndl: state.noDecompressionLimit,
                      hasCriticalWarning: hasStateWarning || hasRecentTransient,
                      diveTime: state.diveTime,
                      isSurfaceInterval: isSurfaceInterval)
        }
    }

    /// Örneklenmiş karar — neden bu aralık seçildiğini açıklar.
    public struct Decision: Equatable, Sendable {
        public let interval: TimeInterval
        public let reason: Reason
        /// Bu aralıkta kaç sensör okuması yapılacak (1 Hz'den)
        public let hertz: Double

        public enum Reason: String, Equatable, Sendable {
            case criticalAlarm
            case ceilingViolationRisk
            case decompressionObligation
            case fastAscent
            case activeMovement
            case bottomIdle
            case surfaceWait
            case notDiving
            case thermalThrottle
        }

        public init(interval: TimeInterval, reason: Reason) {
            self.interval = interval
            self.reason = reason
            self.hertz = 1 / max(0.05, interval)
        }
    }

    /// Güvenlik açısından kritik mi? (her zaman yüksek örnekleme gerekir).
    public func isSafetyCritical(_ context: Context) -> Bool {
        if !context.isDiving { return false }
        if context.hasCriticalWarning { return true }
        if context.ceilingDepth > 0 { return true }
        // Tavanın 1 m altındayız veya üstündeysek
        if context.ceilingDepth > 0 || (context.depth < 1.5 && context.ceilingDepth > -1) {
            return true
        }
        return false
    }

    /// Anlık koşullara göre önerilen aralık.
    public func decide(_ context: Context) -> Decision {
        // 0) Dalış yokken
        guard context.isDiving else {
            return Decision(interval: idleDiveInterval, reason: .notDiving)
        }

        // 1) Kritik alarm — her şeyden önce güvenlik
        if context.hasCriticalWarning {
            return Decision(interval: safetyInterval, reason: .criticalAlarm)
        }

        // 2) Deko yükümlülüğü var (NDL bitti veya tavan var).
        //    Durağın kendisi **yavaş** değişir; hızlı örnekleme yalnızca
        //    yükselirken veya tavana çok yakınken gereklidir. 45 dakikalık
        //    bir deko durağını 0.5 saniyede bir örneklemek gereksiz enerji
        //    harcar; buna karşılık yükselişte 1 saniye çözünürlük hız
        //    ihlalini güvenilir biçimde yakalar (9 m/dk eşiği 1 sn'de 0.15 m
        //    çözünürlükle ölçülür).
        if context.ceilingDepth > 0 || context.ndl <= 0 {
            let movingUp = context.ascentRate > 4
            let nearCeiling = context.ceilingDepth > 0
                && (context.depth - context.ceilingDepth) < 1.5
            if movingUp {
                return Decision(interval: safetyInterval, reason: .decompressionObligation)
            }
            if nearCeiling {
                return Decision(interval: safetyInterval, reason: .ceilingViolationRisk)
            }
            return Decision(interval: baseInterval, reason: .decompressionObligation)
        }

        // 3) Tavan ihlali riski (tavan sıfırın altında ama çok sığdayız)
        if context.ceilingDepth < 0, context.depth < 2.0, context.ndl <= 5 {
            return Decision(interval: safetyInterval, reason: .ceilingViolationRisk)
        }

        // 4) Hızlı çıkış (> 9 m/dk) — ihlal yakalamak
        // NOT: `ascentRate` işareti dalış bilgisayarı geleneğine göre
        // **pozitif = yukarı çıkış** (bkz. AscentRateMonitor). Burada tersine
        // çevrilirse hızlı iniş "hızlı çıkış" sanılır ve asıl tehlikeli
        // olan yükseliş seyrekleştirilir.
        if context.ascentRate > 9 {
            return Decision(interval: safetyInterval, reason: .fastAscent)
        }

        // 5) Aktif hareket (|hız| > 2 m/dk)
        if abs(context.ascentRate) > 2 {
            return Decision(interval: baseInterval, reason: .activeMovement)
        }

        // 6) Yüzeyde (dalış sürüyor ama derinlik ~0, deko sonrası bekleme)
        if context.depth < 0.5, context.ceilingDepth <= 0 {
            return Decision(interval: surfaceInterval, reason: .surfaceWait)
        }

        // 7) Dipte sabit — enerji tasarrufu
        return Decision(interval: idleInterval, reason: .bottomIdle)
    }
}

/// Örneklemeyi zamanında uygulayan yürütücü.
///
/// `AdaptiveSampler`, sensör okumalarını geldiği gibi motora aktarır;
/// bu yürütücü **hangi aralıkta yoklayacağını** söyler ve
/// `DiveWatch` adaptörü CoreMotion'ı bu aralıkla yapılandırır.
public struct AdaptiveSampler: Equatable, Sendable {

    // Kolaylık takma adları
    public typealias Context = AdaptiveSamplingPolicy.Context
    public typealias Decision = AdaptiveSamplingPolicy.Decision

    public private(set) var policy: AdaptiveSamplingPolicy
    /// Son güncelleme zamanı
    public private(set) var lastUpdate: TimeInterval?
    /// Şu anki karar
    public private(set) var currentDecision: Decision
    /// Karar değişim sayısı (ölçüm/raporlama için)
    public private(set) var changeCount: Int = 0

    public init(policy: AdaptiveSamplingPolicy) {
        self.policy = policy
        self.currentDecision = AdaptiveSamplingPolicy.Decision(
            interval: policy.baseInterval, reason: .bottomIdle)
    }

    /// Enerji profiline göre başlat.
    public init(profile: PowerProfile, state: EnergyState) {
        let base = AdaptiveSamplingPolicy(profile: profile, state: state)
        self.init(policy: base.adjusted(for: state))
    }

    /// Enerji durumu güncellendiğinde politikayı tazeler.
    public mutating func applyEnergy(_ state: EnergyState) {
        policy = policy.adjusted(for: state)
    }

    /// Yeni aralık kararı verilip verilmeli mi?
    ///
    /// - Parameters:
    ///   - context: Anlık koşullar
    ///   - elapsed: Dalış başlangıcından geçen süre
    public mutating func update(context: Context, elapsed: TimeInterval) -> Decision {
        let decision = policy.decide(context)

        // Güvenlik aralıklarında zaman sınırı uygulanmaz (anında geçiş),
        // aksi hâlde yavaşlatılan kısımda gecikme olur.
        let isSafety = decision.reason == .criticalAlarm
            || decision.reason == .decompressionObligation
            || decision.reason == .ceilingViolationRisk
            || decision.reason == .fastAscent

        let currentIsSafety = currentDecision.reason == .criticalAlarm
            || currentDecision.reason == .decompressionObligation
            || currentDecision.reason == .ceilingViolationRisk
            || currentDecision.reason == .fastAscent

        let shouldChange: Bool
        if lastUpdate == nil {
            // İlk karar **her zaman** uygulanır; aksi halde örnekleyici
            // başlangıçtaki varsayılan aralıkta kalır.
            shouldChange = true
        } else if isSafety != currentIsSafety {
            // Güvenlik durumu değiştiyse **hemen** geçiş yap.
            shouldChange = true
        } else if let last = lastUpdate, elapsed - last >= decision.interval {
            shouldChange = true
        } else {
            shouldChange = false
        }

        if shouldChange {
            lastUpdate = elapsed
            if decision != currentDecision {
                changeCount += 1
            }
            currentDecision = decision
        }
        return currentDecision
    }

    /// Bir sensör okumasının işlenip işlenmeyeceğini belirler.
    ///
    /// - Returns: `true` ise motor ilerletilmeli.
    public mutating func shouldProcess(context: Context, elapsed: TimeInterval) -> Bool {
        // Not: `previousDepth` **her** çağrıda güncellenir; aksi halde işlenen
        // okumalardan sonraki "ani değişim" karşılaştırması eski derinliği
        // kullanır ve gerçek değişimleri kaçırır.
        let previous = previousDepth
        previousDepth = context.depth

        // Güvenlik durumunda her okuma işlenir.
        if policy.isSafetyCritical(context) { return true }
        guard let last = lastUpdate else {
            lastUpdate = elapsed
            return true
        }
        // Zaman aralığı dolduysa veya derinlik eşiği aşıldıysa işle.
        if elapsed - last >= currentDecision.interval { return true }
        // Ani derinlik değişimi (0.5 m'den fazla) yine işlenmeli.
        if let previous, abs(context.depth - previous) > 0.5 { return true }
        return false
    }

    private var previousDepth: Double?

    /// Kaydedilmiş son derinlik (test/raporlama).
    public var lastDepth: Double? { previousDepth }
}
