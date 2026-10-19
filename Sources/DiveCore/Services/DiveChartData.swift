import Foundation

/// Grafik üzerindeki tek örnek.
public struct DiveChartPoint: Codable, Equatable, Sendable, Identifiable {
    public let elapsed: TimeInterval
    public let depth: Double
    public let temperature: Double?
    public let po2: Double?
    public let gf99: Double?
    public let ceiling: Double?
    public let ascentRate: Double?

    public var id: Double { elapsed }

    public init(elapsed: TimeInterval, depth: Double,
                temperature: Double? = nil, po2: Double? = nil,
                gf99: Double? = nil, ceiling: Double? = nil, ascentRate: Double? = nil) {
        self.elapsed = elapsed
        self.depth = depth
        self.temperature = temperature
        self.po2 = po2
        self.gf99 = gf99
        self.ceiling = ceiling
        self.ascentRate = ascentRate
    }

    /// `DiveSample`'dan nokta üretir.
    public init(sample: DiveSample) {
        self.init(elapsed: sample.elapsed, depth: sample.depth,
                  temperature: sample.temperature, po2: sample.po2,
                  gf99: sample.gf99, ceiling: sample.ceiling,
                  ascentRate: sample.ascentRate)
    }
}

/// Grafikte gösterilecek tek bir seri.
public struct DiveChartSeries: Equatable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Equatable, Codable, Sendable {
        case depth
        case temperature
        case po2
        case gf99
        case ceiling
        case ascentRate

        /// Serinin etiketi (Türkçe).
        public var title: String {
            switch self {
            case .depth: return "Derinlik"
            case .temperature: return "Sıcaklık"
            case .po2: return "PO₂"
            case .gf99: return "GF99"
            case .ceiling: return "Tavan"
            case .ascentRate: return "Çıkış hızı"
            }
        }

        /// Birim metni.
        public var unit: String {
            switch self {
            case .depth, .ceiling: return "m"
            case .temperature: return "°C"
            case .po2: return "bar"
            case .gf99: return "%"
            case .ascentRate: return "m/dk"
            }
        }

        /// Değer ekseni min/max ayarı (grafik otomatik ölçeklemesin).
        public var defaultDomain: ClosedRange<Double>? {
            switch self {
            case .depth, .ceiling: return 0...60
            case .temperature: return 4...30
            case .po2: return 0...1.6
            case .gf99: return 0...150
            case .ascentRate: return -20...20
            }
        }

        /// Derinlik ekseninde ters çizilir mi (aşağı doğru büyür)?
        public var isInverted: Bool { self == .depth || self == .ceiling }
    }

    public let kind: Kind
    public let points: [DiveChartPoint]
    public let colorRole: DiveColorRole

    public var id: String { kind.rawValue }

    public init(kind: Kind, points: [DiveChartPoint], colorRole: DiveColorRole) {
        self.kind = kind
        self.points = points
        self.colorRole = colorRole
    }

    /// Seri değerleri (grafik çizimi için).
    public var values: [(elapsed: TimeInterval, value: Double)] {
        points.compactMap { point in
            switch kind {
            case .depth: return (point.elapsed, point.depth)
            case .temperature: return point.temperature.map { (point.elapsed, $0) }
            case .po2: return point.po2.map { (point.elapsed, $0) }
            case .gf99: return point.gf99.map { (point.elapsed, $0) }
            case .ceiling: return point.ceiling.map { (point.elapsed, $0) }
            case .ascentRate: return point.ascentRate.map { (point.elapsed, $0) }
            }
        }
    }

    /// Gerçek değer aralığı.
    public var valueDomain: ClosedRange<Double> {
        let list = values.map(\.value)
        guard let minimum = list.min(), let maximum = list.max() else { return 0...1 }
        return minimum == maximum ? minimum...(minimum + 1) : minimum...maximum
    }
}

/// Bir dalışın tüm grafik serileri.
public struct DiveProfileChart: Equatable, Sendable {
    public let diveID: UUID
    public let startDate: Date
    public let duration: TimeInterval
    public let maxDepth: Double
    public let series: [DiveChartSeries]

    public init(diveID: UUID, startDate: Date, duration: TimeInterval,
                maxDepth: Double, series: [DiveChartSeries]) {
        self.diveID = diveID
        self.startDate = startDate
        self.duration = duration
        self.maxDepth = maxDepth
        self.series = series
    }

    /// Belirli türdeki seri.
    public func series(_ kind: DiveChartSeries.Kind) -> DiveChartSeries? {
        series.first { $0.kind == kind }
    }

    /// Zaman ekseni aralığı.
    public var timeDomain: ClosedRange<Double> { 0...max(duration, 1) }
}

/// Profil grafiğini `LoggedDive` / `LogEntry` örneklerinden üretir.
public enum DiveChartBuilder {

    /// En fazla bu kadar nokta kullanılır (watchOS çizim performansı).
    public static let defaultPointBudget = 120

    public static func make(from log: LogEntry,
                            pointBudget: Int = defaultPointBudget) -> DiveProfileChart {
        make(diveID: LoggedDive.stableID(for: log.startDate),
             startDate: log.startDate,
             samples: log.samples,
             duration: log.totalDiveTime,
             maxDepth: log.maxDepth,
             pointBudget: pointBudget)
    }

    public static func make(from dive: LoggedDive,
                            pointBudget: Int = defaultPointBudget) -> DiveProfileChart {
        make(diveID: dive.id, startDate: dive.startDate, samples: dive.samples,
             duration: dive.totalDiveTime, maxDepth: dive.maxDepth,
             pointBudget: pointBudget)
    }

    public static func make(diveID: UUID,
                            startDate: Date,
                            samples: [DiveSample],
                            duration: TimeInterval,
                            maxDepth: Double,
                            pointBudget: Int = defaultPointBudget) -> DiveProfileChart {
        let points = ChartDownsampler.minMax(
            samples.map(DiveChartPoint.init(sample:)),
            budget: max(2, pointBudget))

        let series: [DiveChartSeries] = [
            DiveChartSeries(kind: .depth, points: points, colorRole: .accent),
            DiveChartSeries(kind: .temperature, points: points, colorRole: .caution),
            DiveChartSeries(kind: .gf99, points: points, colorRole: .deco),
            DiveChartSeries(kind: .ceiling, points: points, colorRole: .danger)
        ]
        return DiveProfileChart(diveID: diveID, startDate: startDate,
                                duration: duration, maxDepth: maxDepth, series: series)
    }
}

/// Grafik noktalarını azaltır (downsampling).
///
/// **Min/max yöntemi** kullanılır: zaman kovalarına bölünür ve her kovalarda
/// en derin (maksimum) ile en sığ (minimum) noktalar korunur. Böylece profilin
/// gerçek şekli (tepe noktalar, plato, tavan geçişleri) küçültme sonrası da
/// görünür kalır — basit "her N. nokta" yönteminden çok daha güvenlidir.
public enum ChartDownsampler {

    /// Noktaları en fazla `budget` adede indirger.
    public static func minMax(_ points: [DiveChartPoint], budget: Int) -> [DiveChartPoint] {
        guard budget >= 2, points.count > budget else { return points }
        guard let first = points.first, let last = points.last else { return points }
        guard budget > 2 else { return [first, last] }

        // Her kova en fazla 2 nokta (derin + sığ) üretir → bütçe 2*kovalar+2
        let middleCount = points.count - 2
        let bucketCount = max(1, (budget - 2) / 2)
        let bucketSize = Double(middleCount) / Double(bucketCount)

        var result: [DiveChartPoint] = [first]
        for bucket in 0..<bucketCount {
            let start = Int((Double(bucket) * bucketSize).rounded(.up))
            let end = min(middleCount, Int((Double(bucket + 1) * bucketSize).rounded(.up)))
            guard start < end else { continue }

            let slice = points[(start + 1)..<(end + 1)]
            guard let deepest = slice.max(by: { $0.depth < $1.depth }),
                  let shallowest = slice.min(by: { $0.depth < $1.depth }) else { continue }
            result.append(deepest)
            if shallowest.elapsed != deepest.elapsed { result.append(shallowest) }
        }
        result.append(last)

        // Zaman sırasına göre sırala ve tekrarları at
        var unique: [DiveChartPoint] = []
        for point in result.sorted(by: { $0.elapsed < $1.elapsed }) {
            if let previous = unique.last, previous.elapsed == point.elapsed { continue }
            unique.append(point)
        }
        return unique
    }

    /// Değer dizisini eşit aralıklı indirger (yalnızca zaman ekseni baskın
    /// seriler için; min/max varyantı tercih edilir).
    public static func uniform(_ values: [(elapsed: TimeInterval, value: Double)],
                               budget: Int) -> [(elapsed: TimeInterval, value: Double)] {
        guard budget >= 2, values.count > budget else { return values }
        let stride = Double(values.count) / Double(budget - 1)
        var result: [(elapsed: TimeInterval, value: Double)] = []
        for index in 0..<(budget - 1) {
            result.append(values[min(values.count - 1, Int(Double(index) * stride))])
        }
        result.append(values[values.count - 1])
        return result
    }

    /// Derinlik profilinin alan altında doldurulacak kapalı poligonu
    /// (alan grafiği için).
    public static func closedArea(_ points: [DiveChartPoint],
                                  baseline: Double = 0) -> [(x: TimeInterval, y: Double)] {
        guard let first = points.first, let last = points.last else { return [] }
        var result: [(x: TimeInterval, y: Double)] = [(x: first.elapsed, y: baseline)]
        result.append(contentsOf: points.map { (x: $0.elapsed, y: $0.depth) })
        result.append((x: last.elapsed, y: baseline))
        return result
    }
}