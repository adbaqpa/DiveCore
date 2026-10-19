import Foundation

/// Çıkış sırasında dalgıcı yönlendiren rehber.
///
/// ADIM 4 gereksinimlerinin canlı karşılığı:
/// - **Derin iniş / hızlı çıkış** alarmları için anlık değerlendirme,
/// - Tavan üstündeki tampon ("3 m kuralı"),
/// - Hangi durağa, ne kadar süre kalınacağı rehberliği.
public struct AscentAdvisor: Sendable {

    // MARK: - Ayarlar

    /// Çıkış hızı sınırı (m/dk)
    public var maximumAscentRate: Double
    /// Dikkat çıkış hızı eşiği (m/dk)
    public var cautionAscentRate: Double
    /// Azami iniş hızı (m/dk)
    public var maximumDescentRate: Double
    /// Tavan üstünde bırakılacak tampon (m) — "3 m kuralı"nın yarısı
    public var ceilingBuffer: Double
    /// Emniyet durağı derinliği (m)
    public var safetyStopDepth: Double

    public init(maximumAscentRate: Double = DiveSafetyLimits.maximumAscentRate,
                cautionAscentRate: Double = DiveSafetyLimits.cautionAscentRate,
                maximumDescentRate: Double = DiveSafetyLimits.maximumDescentRate,
                ceilingBuffer: Double = 1.5,
                safetyStopDepth: Double = DiveSafetyLimits.safetyStopDepth) {
        self.maximumAscentRate = maximumAscentRate
        self.cautionAscentRate = cautionAscentRate
        self.maximumDescentRate = maximumDescentRate
        self.ceilingBuffer = ceilingBuffer
        self.safetyStopDepth = safetyStopDepth
    }

    // MARK: - Sonuç

    /// Rehberin anlık değerlendirmesi.
    public struct Guidance: Equatable, Sendable {
        /// Genel durum
        public enum Severity: String, Equatable, Codable, Sendable, Comparable {
            case ok
            case caution
            case warning
            case critical

            private var order: Int {
                switch self {
                case .ok: return 0
                case .caution: return 1
                case .warning: return 2
                case .critical: return 3
                }
            }
            public static func < (lhs: Severity, rhs: Severity) -> Bool {
                lhs.order < rhs.order
            }
        }

        public let currentDepth: Double
        public let ceilingDepth: Double
        /// Bu derinliğin **üstüne çıkılmamalı** (tavan + tampon)
        public let maximumAllowedDepth: Double
        /// Planlanan bir sonraki durağın derinliği
        public let nextStopDepth: Double?
        /// O durağa kadar tahmini süre (saniye)
        public let timeToStop: TimeInterval
        /// O durakta kalınacak süre (saniye, 0 ise durağa gerek yok)
        public let stopHoldTime: TimeInterval
        /// Yüzeye çıkış süresi (saniye)
        public let timeToSurface: TimeInterval
        /// Anlık çıkış hızı (m/dk, pozitif = yukarı)
        public let ascentRate: Double
        /// Anlık iniş hızı (m/dk, pozitif)
        public let descentRate: Double
        public let severity: Severity
        /// Kullanıcıya gösterilecek tek satırlık talimat
        public let instruction: String
        /// Tavan ihlali var mı?
        public var isAboveCeiling: Bool {
            ceilingDepth > 0 && currentDepth < ceilingDepth - 0.5
        }
        /// Duraklamak gerekiyor mu?
        public var shouldStop: Bool { stopHoldTime > 0 }

        public init(currentDepth: Double, ceilingDepth: Double, maximumAllowedDepth: Double,
                    nextStopDepth: Double?, timeToStop: TimeInterval,
                    stopHoldTime: TimeInterval, timeToSurface: TimeInterval,
                    ascentRate: Double, descentRate: Double,
                    severity: Severity, instruction: String) {
            self.currentDepth = currentDepth
            self.ceilingDepth = ceilingDepth
            self.maximumAllowedDepth = maximumAllowedDepth
            self.nextStopDepth = nextStopDepth
            self.timeToStop = timeToStop
            self.stopHoldTime = stopHoldTime
            self.timeToSurface = timeToSurface
            self.ascentRate = ascentRate
            self.descentRate = descentRate
            self.severity = severity
            self.instruction = instruction
        }
    }

    /// Mevcut `DiveState`'e göre rehber üretir (saf fonksiyon).
    public func evaluate(_ state: DiveState) -> Guidance {
        let depth = state.currentDepth
        let ceiling = state.ceilingDepth
        let rate = state.ascentRate
        let descentRate = max(0, -state.ascentRate)

        // Dalgıç şu an bir yerde bekliyorsa emniyet/emniyet dışı durak
        var stopDepth = state.nextStopDepth
        var holdTime: TimeInterval = 0
        if state.safetyStop.isActive, !state.safetyStop.isComplete {
            stopDepth = safetyStopDepth
            holdTime = state.safetyStop.remaining
        } else if let stop = stopDepth {
            holdTime = stopHoldTimeForStop(depth: stop, ceiling: ceiling)
        }

        let timeToStop: TimeInterval = {
            guard let stop = stopDepth else { return 0 }
            return max(0, depth - stop) / max(1, DiveSafetyLimits.recommendedAscentRate) * 60
        }()

        var severity: Guidance.Severity = .ok
        var instruction = "Serbest — yüzeye çıkabilirsin"

        if ceiling > 0 {
            if depth < ceiling - 0.5 {
                severity = .critical
                instruction = "Tavanın ÜSTÜNDESİN — \(Int((ceiling - depth).rounded())) m düş!"
            } else if holdTime > 0, let stop = stopDepth, abs(depth - stop) < 1.5 {
                severity = .warning
                instruction = "\(Int(stop)) m'de \(DurationFormatter.clock(holdTime)) bekle"
            } else if let stop = stopDepth {
                severity = .caution
                instruction = "\(Int(stop)) m'ye yavaşça in (\(DurationFormatter.clock(timeToStop)))"
            } else {
                severity = .caution
                instruction = "Yüzeye yavaşça çık (\(DurationFormatter.clock(state.timeToSurface)))"
            }
        }

        // Hız ihlali, durum ne olursa olsun yükseltir
        if rate > maximumAscentRate {
            severity = max(severity, .critical)
            instruction = String(format: "YAVAŞLA! %.1f m/dk (sınır %.0f)", rate, maximumAscentRate)
        } else if rate > cautionAscentRate, severity < .warning {
            severity = max(severity, .caution)
            instruction = String(format: "Çıkışı yavaşlat (%.1f m/dk)", rate)
        }

        // Aşırı hızlı iniş (derin iniş riski)
        if descentRate > maximumDescentRate, severity < .caution {
            severity = .caution
            instruction = String(format: "İniş çok hızlı (%.0f m/dk) — yavaşla", descentRate)
        }

        return Guidance(
            currentDepth: depth,
            ceilingDepth: ceiling,
            maximumAllowedDepth: ceiling > 0 ? ceiling + ceilingBuffer : 0,
            nextStopDepth: stopDepth,
            timeToStop: timeToStop,
            stopHoldTime: holdTime,
            timeToSurface: state.timeToSurface,
            ascentRate: rate,
            descentRate: descentRate,
            severity: severity,
            instruction: instruction)
    }

    /// Bir dekompresyon durağında geçirilmesi gereken süre (saniye).
    ///
    /// Doku durumu verilmezse, tavan ile durağın farkından **doğrusal tahmin**
    /// yapılır (dokular çıkışla birlikte hızla temizlendiği için
    /// fikirsel tahmin bilinçli olarak hızlıdır). Gerçek plan için
    /// `DecoStopPlan` kullanılmalıdır.
    public func stopHoldTimeForStop(depth stop: Double, ceiling: Double) -> TimeInterval {
        // Tavan bu durağın **üstüne** çıkmışsa beklemek gerekmez.
        // (Tavan == durak → hâlâ bu durakta olmak zorunluyken.)
        guard ceiling >= stop, stop > 0 else { return 0 }
        // 3 m'lik tavan farkı başına kaba tahmin (en az 1 dk)
        let steps = ceil((ceiling - stop) / DiveSafetyLimits.decoStopInterval)
        return max(60, steps * 120)
    }
}