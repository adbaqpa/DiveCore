import Foundation

/// Bir dalış profilindeki tek bir aşama.
public struct DiveSegment: Equatable, Codable, Sendable {

    public enum Kind: String, Equatable, Codable, Sendable {
        /// Hedef derinliğe in
        case descent = "descent"
        /// Derinlikte bekle
        case hover = "hover"
        /// Yüzeye doğru çık
        case ascent = "ascent"
        /// Emniyet durağı
        case safetyStop = "safetyStop"
        /// Zorunlu deko durağı
        case decoStop = "decoStop"
        /// Yüzeyde kal
        case surface = "surface"
    }

    public var kind: Kind
    /// Aşamanın hedef derinliği (m)
    public var targetDepth: Double
    /// Aşamanın süresi (saniye)
    public var duration: TimeInterval
    /// İniş hızı sınırı (m/dk)
    public var descentRate: Double
    /// Çıkış hızı sınırı (m/dk)
    public var ascentRate: Double

    public init(kind: Kind,
                targetDepth: Double,
                duration: TimeInterval,
                descentRate: Double = 15,
                ascentRate: Double = DiveSafetyLimits.maximumAscentRate) {
        self.kind = kind
        self.targetDepth = targetDepth
        self.duration = duration
        self.descentRate = descentRate
        self.ascentRate = ascentRate
    }

    // MARK: - Kısayol kurucular

    public static func descent(to depth: Double,
                               at rate: Double = 15,
                               minimumDuration: TimeInterval = 0) -> DiveSegment {
        let duration = max(minimumDuration, depth / max(0.1, rate) * 60)
        return DiveSegment(kind: .descent, targetDepth: depth, duration: duration, ascentRate: rate)
    }

    public static func hover(at depth: Double, for duration: TimeInterval) -> DiveSegment {
        DiveSegment(kind: .hover, targetDepth: depth, duration: duration)
    }

    /// Yüzeye doğru çık
    ///
    /// Süre `0` verilirse simülatör tarafından gerçek mesafeye göre hesaplanır.
    public static func ascent(to depth: Double,
                              at rate: Double = 9,
                              minimumDuration: TimeInterval = 0) -> DiveSegment {
        DiveSegment(kind: .ascent, targetDepth: depth,
                    duration: minimumDuration, ascentRate: rate)
    }

    public static func safetyStop(at depth: Double = DiveSafetyLimits.safetyStopDepth,
                                  duration: TimeInterval = DiveSafetyLimits.safetyStopDuration) -> DiveSegment {
        DiveSegment(kind: .safetyStop, targetDepth: depth, duration: duration)
    }

    public static func decoStop(at depth: Double,
                                duration: TimeInterval = 60) -> DiveSegment {
        DiveSegment(kind: .decoStop, targetDepth: depth, duration: duration)
    }

    public static func surface(for duration: TimeInterval = 60.0) -> DiveSegment {
        DiveSegment(kind: .surface, targetDepth: 0, duration: duration)
    }
}

/// Tam bir dalış senaryosu.
public struct DiveScenario: Equatable, Codable, Sendable {

    public var name: String
    public var segments: [DiveSegment]
    /// Yüzey su sıcaklığı (°C)
    public var surfaceTemperature: Double
    /// Dipteki su sıcaklığı (°C)
    public var bottomTemperature: Double
    /// Termoklin derinliği (m) — bu derinliğin altında sıcaklık hızla düşer
    public var thermoclineDepth: Double
    /// Örnek üretim aralığı (saniye)
    public var sampleInterval: TimeInterval
    /// Gürültü/gürbürültü üreticisi için tohum — deterministik testler için
    public var seed: UInt64
    /// Nefes salınımı genliği (m) — dalış filigranı gerçekçiliği
    public var breathingAmplitude: Double

    public init(name: String,
                segments: [DiveSegment],
                surfaceTemperature: Double = 24,
                bottomTemperature: Double = 19,
                thermoclineDepth: Double = 12,
                sampleInterval: TimeInterval = 1,
                seed: UInt64 = 42,
                breathingAmplitude: Double = 0.035) {
        self.name = name
        self.segments = segments
        self.surfaceTemperature = surfaceTemperature
        self.bottomTemperature = bottomTemperature
        self.thermoclineDepth = thermoclineDepth
        self.sampleInterval = sampleInterval
        self.seed = seed
        self.breathingAmplitude = breathingAmplitude
    }

    /// Toplam süre (saniye)
    public var totalDuration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    /// En derin aşama hedefi (m)
    public var maxDepth: Double { segments.map(\.targetDepth).max() ?? 0 }

    // MARK: - Hazır senaryolar

    /// Başlangıç (rekreasyonel) dalışı: 12 m, 40 dk.
    public static let beginner = DiveScenario(
        name: "Başlangıç 12 m",
        segments: [
            .descent(to: 12, at: 12),
            .hover(at: 12, for: 40 * 60.0),
            .ascent(to: 0, at: 9)
        ],
        surfaceTemperature: 25, bottomTemperature: 21, thermoclineDepth: 8)

    /// Klasik rekreasyonel dalış: 30 m, 20 dk + 5 m emniyet durağı.
    public static let recreational30m = DiveScenario(
        name: "30 m / 20 dk (klasik)",
        segments: [
            .descent(to: 30, at: 15),
            .hover(at: 30, for: 20 * 60.0),
            .ascent(to: 5, at: 9),
            .safetyStop(at: 5, duration: 180.0),
            .ascent(to: 0, at: 9)
        ],
        surfaceTemperature: 26, bottomTemperature: 20, thermoclineDepth: 14)

    /// EAN32 ile derin dalış.
    public static let nitrox30m = DiveScenario(
        name: "EAN32 / 30 m / 25 dk",
        segments: [
            .descent(to: 30, at: 15),
            .hover(at: 30, for: 25 * 60.0),
            .ascent(to: 5, at: 9),
            .safetyStop(at: 5, duration: 180.0),
            .ascent(to: 0, at: 9)
        ],
        surfaceTemperature: 26, bottomTemperature: 20, thermoclineDepth: 14)

    /// Derin dalış: 45 m, 15 dk.
    public static let deep45m = DiveScenario(
        name: "Derin 45 m / 15 dk",
        segments: [
            .descent(to: 45, at: 15),
            .hover(at: 45, for: 15 * 60.0),
            .ascent(to: 5, at: 9),
            .safetyStop(at: 5, duration: 180.0),
            .ascent(to: 0, at: 9)
        ],
        surfaceTemperature: 24, bottomTemperature: 18, thermoclineDepth: 12)

    /// ⚠️ Hızlı çıkış ihlali: 18 m/dk (> 10 m/dk sınırı) — alarm testi.
    public static let fastAscentViolation = DiveScenario(
        name: "Hızlı çıkış (18 m/dk)",
        segments: [
            .descent(to: 30, at: 15),
            .hover(at: 30, for: 12 * 60.0),
            .ascent(to: 0, at: 18)
        ],
        surfaceTemperature: 26, bottomTemperature: 20, thermoclineDepth: 14)

    /// ⚠️ Aşırı hızlı iniş (30 m/dk) — emniyet durağı atlama senaryosu.
    public static let safetyStopSkipped = DiveScenario(
        name: "Emniyet durağı atlandı",
        segments: [
            .descent(to: 25, at: 18),
            .hover(at: 25, for: 10 * 60.0),
            .ascent(to: 0, at: 12)
        ],
        surfaceTemperature: 26, bottomTemperature: 20, thermoclineDepth: 12)

    /// Deko zorunluluğu doğuran uzun dalış.
    public static let decompressionDive = DiveScenario(
        name: "Deko dalışı 30 m / 45 dk",
        segments: [
            .descent(to: 30, at: 15),
            .hover(at: 30, for: 45 * 60.0),
            .ascent(to: 5, at: 9),
            .safetyStop(at: 5, duration: 180.0),
            .ascent(to: 0, at: 9)
        ],
        surfaceTemperature: 26, bottomTemperature: 20, thermoclineDepth: 14)
}

/// Deterministik dalış simülatörü.
///
/// - Gerçekçi iniş/çıkış hızı (yumuşak başlangıç/bitiş eğrileri ile)
/// - Nefes kaynaklı salınım + ölçüm gürültüsü (tohumlanabilir, deterministik)
///   Genlikler bilinçli olarak küçük tutulmuştur: 1 Hz örneklemede yüksek
///   frekanslı genlik, çıkış hızı alarmında sahte ihlal üretir.
/// - Termoklin profili ile sıcaklık
/// - `CoreMotion` verisi gibi `Date` damgalı `DepthReading` üretir
public struct DiveSimulator: Sendable {

    public let scenario: DiveScenario
    public let water: DivePhysics.WaterType

    /// Başlangıç zaman damgası (okumaların `timestamp` alanı için).
    public let startDate: Date

    /// Üretilen tüm okumalar (tüm profili bir kerede üretmek için).
    public private(set) var readings: [DepthReading] = []

    /// Profilin segment aralıkları — testler ve UI için.
    public private(set) var segmentRanges: [SegmentRange] = []

    /// Canlı kullanımda sıradaki okunacak kaydın indeksi.
    public private(set) var cursor: Int = 0

    /// Üretilen profilin bir aşamasının zaman aralığı.
    public struct SegmentRange: Equatable, Sendable {
        public let kind: DiveSegment.Kind
        public let targetDepth: Double
        public let startElapsed: TimeInterval
        public let endElapsed: TimeInterval
        public let startIndex: Int
        public let endIndex: Int

        public var duration: TimeInterval { endElapsed - startElapsed }

        /// Bu aralıktaki okumalar.
        public func readings(in readings: [DepthReading]) -> [DepthReading] {
            Array(readings[startIndex..<endIndex])
        }
    }

    // MARK: - Oluşturucu

    public init(scenario: DiveScenario = .recreational30m,
                water: DivePhysics.WaterType = .salt,
                startDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.scenario = scenario
        self.water = water
        self.startDate = startDate
        generate()
    }

    // MARK: - Profil üretimi

    private mutating func generate() {
        readings = []
        segmentRanges = []
        cursor = 0

        var rng = SeededGenerator(seed: scenario.seed)
        var depth = 0.0
        var elapsed: TimeInterval = 0
        let dt = scenario.sampleInterval

        for segment in scenario.segments {
            let segmentStartIndex = readings.count
            let segmentStartElapsed = elapsed
            // İniş/çıkış segmentlerinde süre, gerçek mesafeye göre hesaplanır.
            // (Hedef derinlikten hesaplamak, 30 m'den 5 m'ye çıkışı 33 sn yapardı.)
            let isTravel = segment.kind == .descent || segment.kind == .ascent
            let distance = abs(segment.targetDepth - depth)
            let rate = segment.targetDepth < depth ? segment.ascentRate : segment.descentRate
            // Yumuşatma eğrisi (başlangıç/ bitiş rampası) mesafenin bir kısmını
            // yutar; bu kayıp süreye bölünerek telafi edilir, aksi halde segment
            // hedefe ulaşamaz ve sonraki durak segmenti "iniş" sanılır.
            let computedDuration = distance / max(0.1, rate) * 60 / DiveSimulator.easingEfficiency
            let segmentDuration = (isTravel && segment.duration <= 0)
                ? computedDuration
                : max(segment.duration, isTravel ? computedDuration : 0)

            let steps = max(1, Int((segmentDuration / dt).rounded(.up)))
            let stepDuration = segmentDuration / Double(steps)

            for step in 0..<steps {
                let progress = Double(step) / Double(steps)

                depth = DiveSimulator.stepDepth(
                    current: depth,
                    target: segment.targetDepth,
                    segment: segment,
                    progress: progress,
                    stepDuration: stepDuration)

                // Nefes salınımı (dalış filigranı)
                let breathing = scenario.breathingAmplitude * sin(elapsed / 5.0)
                // Ölçüm gürültüsü
                let noise = (rng.next() - 0.5) * 0.02

                let reported = max(0, depth + breathing + noise)
                readings.append(DepthReading(
                    depth: reported,
                    ambientPressure: DivePhysics.ambientPressure(depthMeters: reported, water: water),
                    timestamp: startDate.addingTimeInterval(elapsed),
                    elapsed: elapsed,
                    temperature: DiveSimulator.temperature(
                        at: reported,
                        surface: scenario.surfaceTemperature,
                        bottom: scenario.bottomTemperature,
                        thermocline: scenario.thermoclineDepth),
                    isSimulated: true,
                    water: water))
                elapsed += dt
            }

            segmentRanges.append(SegmentRange(
                kind: segment.kind,
                targetDepth: segment.targetDepth,
                startElapsed: segmentStartElapsed,
                endElapsed: elapsed,
                startIndex: segmentStartIndex,
                endIndex: readings.count))
        }
    }

    /// Bir zaman adımında derinliği ilerletir.
    ///
    /// - Hız sınırı aşınmaz (`m/dk` → `m/s` dönüşümü ile).
    /// - Aşamanın ilk/son %12'sinde hız yumuşakça sıfıra iner (sivri köşe yok).
    /// - Hedefe son 6 saniyede yaklaşırken yavaşlar.
    ///
    /// - Important: Yumuşatma rampaları ve hedefe yaklaşma freni ortalama
    ///   hareketi `easingEfficiency` oranına düşürür; segment süresi buna göre
    ///   telafi edilir, aksi halde segment hedefe ulaşamazdı.
    static let easingEfficiency: Double = 0.82

    static func stepDepth(current: Double,
                          target: Double,
                          segment: DiveSegment,
                          progress: Double,
                          stepDuration: TimeInterval) -> Double {
        let remaining = target - current
        guard abs(remaining) > 0.01 else { return target }

        // Başlangıç ve bitişte yumuşatma
        let edge = 0.12
        let ramp: Double
        if progress < edge {
            ramp = progress / edge
        } else if progress > 1 - edge {
            ramp = max(0, (1 - progress) / edge)
        } else {
            ramp = 1
        }
        let eased = ramp * ramp * (3 - 2 * ramp)      // smoothstep

        // Gerçek hız sınırı (m/s)
        let ratePerSecond = (remaining < 0 ? segment.ascentRate : segment.descentRate) / 60.0

        // Hedefe son 6 saniyede yumuşak yaklaşım
        let brakingDistance = ratePerSecond * 6
        let speedFactor = min(1.0, max(0.15, abs(remaining) / max(0.001, brakingDistance)))

        let delta = min(abs(remaining), ratePerSecond * stepDuration * eased * speedFactor)
        return remaining > 0 ? current + delta : current - delta
    }

    /// Termoklin profili ile su sıcaklığı.
    static func temperature(at depth: Double,
                            surface: Double,
                            bottom: Double,
                            thermocline: Double) -> Double {
        guard depth > 0 else { return surface }
        let transitionTop = max(0.1, thermocline * 0.75)
        let transitionBottom = thermocline * 1.6

        if depth <= transitionTop {
            let t = depth / transitionTop
            return surface + (bottom - surface) * t * 0.35
        } else if depth < transitionBottom {
            let t = (depth - transitionTop) / (transitionBottom - transitionTop)
            let eased = t * t * (3 - 2 * t)
            return surface + (bottom - surface) * (0.35 + 0.55 * eased)
        } else {
            return bottom
        }
    }

    // MARK: - Canlı erişim

    /// Profilin toplam okuma sayısı.
    public var readingCount: Int { readings.count }

    /// Üretilen profilin toplam süresi (saniye).
    public var profileDuration: TimeInterval {
        guard let last = readings.last else { return 0 }
        return last.elapsed + scenario.sampleInterval
    }

    /// Verilen türdeki ilk segment aralığı (yoksa `nil`).
    public func range(of kind: DiveSegment.Kind) -> SegmentRange? {
        segmentRanges.first { $0.kind == kind }
    }

    /// Verilen türdeki tüm segment aralıkları.
    public func ranges(of kind: DiveSegment.Kind) -> [SegmentRange] {
        segmentRanges.filter { $0.kind == kind }
    }

    /// Sıradaki okumayı döndürür ve imleci ilerletir.
    public mutating func next() -> DepthReading? {
        guard cursor < readings.count else { return nil }
        defer { cursor += 1 }
        return readings[cursor]
    }

    /// Belirli bir zaman damgasına (veya indekse) ait okumayı döndürür.
    public func reading(atElapsed elapsed: TimeInterval) -> DepthReading? {
        let index = Int((elapsed / scenario.sampleInterval).rounded())
        guard index >= 0 && index < readings.count else { return nil }
        return readings[index]
    }

    /// Belirli bir zaman aralığındaki okumalar.
    public func readings(from start: TimeInterval, to end: TimeInterval) -> [DepthReading] {
        readings.filter { $0.elapsed >= start && $0.elapsed <= end }
    }

    /// Profil bitti mi?
    public var isFinished: Bool { cursor >= readings.count }

    /// Kalan okuma süresi (saniye)
    public var remainingDuration: TimeInterval {
        guard cursor < readings.count else { return 0 }
        return readings[cursor].elapsed
    }

    /// Simülatörü başa sar.
    public mutating func reset() {
        cursor = 0
    }

    /// Senaryoyu değiştirip yeniden üretir.
    public mutating func apply(scenario: DiveScenario) {
        let newSelf = DiveSimulator(scenario: scenario, water: water, startDate: startDate)
        self = newSelf
    }
}

/// Deterministik sözde rastgele üreteç (kalibrasyon/test tekrarlanabilirliği için).
public struct SeededGenerator: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    /// 0...1 arası tekdüze değer.
    public mutating func next() -> Double {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545F4914F6CDD1D
        return Double(value >> 11) / Double(1 << 53)
    }
}