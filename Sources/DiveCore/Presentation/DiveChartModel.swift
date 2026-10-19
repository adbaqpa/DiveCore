import Foundation

/// ADIM 10 — **interaktif derinlik-zaman grafiğinin** çekirdek modeli.
///
/// Swift Charts'ta `chartXSelection`, `.chartScrollableAxes` ve `.chartXScale`
/// ile etkileşim kurulur; ancak "hangi aralık görünür, hangi nokta seçili,
/// araç ipucu ne söylüyor" kararları test edilebilir olmalıdır. Bu model o
/// kararları yapar; görünüm yalnızca uygular.
public struct DiveChartModel: Equatable, Sendable {

    /// Grafikte gösterilen metrik.
    public enum Metric: String, CaseIterable, Codable, Sendable, Identifiable {
        case depth
        case temperature
        case gasLoad
        case ascentRate
        case gf99

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .depth: return "Derinlik"
            case .temperature: return "Sıcaklık"
            case .gasLoad: return "Gaz yükü"
            case .ascentRate: return "Çıkış hızı"
            case .gf99: return "GF99"
            }
        }

        public var unit: String {
            switch self {
            case .depth: return "m"
            case .temperature: return "°C"
            case .gasLoad: return "bar"
            case .ascentRate: return "m/dk"
            case .gf99: return "%"
            }
        }

        /// Grafik yönü (derinlik aşağı doğru çizilir).
        public var isInverted: Bool { self == .depth }
    }

    /// Ekranda gösterilen veri noktası.
    public struct Point: Equatable, Sendable, Identifiable {
        public let id: Int
        /// Dalış başlangıcından itibaren süre (saniye)
        public let x: TimeInterval
        /// Metrik değeri
        public let y: Double
        /// Derinlik (metin/araç ipucu için)
        public let depth: Double

        public init(id: Int, x: TimeInterval, y: Double, depth: Double) {
            self.id = id
            self.x = x
            self.y = y
            self.depth = depth
        }
    }

    public let metric: Metric
    public let allPoints: [Point]
    /// Deko tavanı profili (grafiğe eklenebilir referans eğri)
    public let ceilingPoints: [Point]
    public let totalDuration: TimeInterval

    // MARK: Görünüm durumu

    /// Görünür zaman aralığı (saniye)
    public private(set) var visibleRange: ClosedRange<TimeInterval>
    /// Seçili nokta (nil = seçim yok)
    public private(set) var selection: Point?
    /// İmleç konumu (seçim yoksa gösterge çizgisi)
    public private(set) var cursor: TimeInterval?

    public init(metric: Metric, samples: [DiveSample], totalDuration: TimeInterval? = nil) {
        self.metric = metric
        let points = DiveChartModel.makePoints(metric: metric, samples: samples)
        self.allPoints = points
        self.ceilingPoints = DiveChartModel.ceilingPoints(from: samples)
        let duration = totalDuration ?? (points.last?.x ?? 0)
        self.totalDuration = max(duration, points.last?.x ?? 0)
        self.visibleRange = 0...max(1, self.totalDuration)
        self.selection = nil
        self.cursor = nil
    }

    // MARK: - Veri

    /// Metrik verisini örneklerden üretir.
    public static func makePoints(metric: Metric, samples: [DiveSample]) -> [Point] {
        samples.map { sample in
            let value: Double
            switch metric {
            case .depth: value = sample.depth
            case .temperature: value = sample.temperature
            case .gasLoad: value = sample.leadingTissuePressure
            case .ascentRate: value = sample.ascentRate
            case .gf99: value = sample.gf99
            }
            return Point(id: sample.id, x: sample.elapsed, y: value, depth: sample.depth)
        }
    }

    /// Görünür aralıktaki noktalar.
    public var visiblePoints: [Point] {
        allPoints.filter { visibleRange.contains($0.x) }
    }

    /// Görünür aralıktaki tavan noktaları.
    public var visibleCeilingPoints: [Point] {
        ceilingPoints.filter { visibleRange.contains($0.x) }
    }

    /// Görünür aralıktaki en uç değerler (eksen sınırları için).
    public var visibleExtent: ClosedRange<Double>? {
        let points = visiblePoints
        guard let first = points.first, let last = points.last else { return nil }
        let inner = points.reduce(Swift.min(first.y, last.y)) {
            Swift.min($0, $1.y)
        }
        let outer = points.reduce(Swift.max(first.y, last.y)) {
            Swift.max($0, $1.y)
        }
        return inner...outer
    }

    // MARK: - Etkileşim

    /// Yakınlaştırma (pinch / digital crown).
    ///
    /// - Parameters:
    ///   - scale: 1'den büyük = yakınlaştır (alt sınır `minimumWindow`)
    ///   - focus: Odak merkezi (nil = görünür merkez)
    public mutating func zoom(by scale: Double, focus: TimeInterval? = nil,
                              minimumWindow: TimeInterval = 60) {
        guard scale > 0 else { return }
        let window = max(minimumWindow, (visibleRange.upperBound - visibleRange.lowerBound) / scale)
        let center = focus ?? ((visibleRange.lowerBound + visibleRange.upperBound) / 2)
        setVisibleWindow(center: center, window: min(window, totalDuration))
    }

    /// Görünür pencereyi doğrudan ayarlar (sürükleme).
    public mutating func setVisibleWindow(center: TimeInterval, window: TimeInterval) {
        let clampedWindow = min(max(1, window), max(1, totalDuration))
        var lower = center - clampedWindow / 2
        lower = max(0, min(lower, totalDuration - clampedWindow))
        let upper = lower + clampedWindow
        visibleRange = lower...upper
    }

    /// Sürükleme (pan): tüm pencereyi kaydırır.
    public mutating func pan(by delta: TimeInterval) {
        let window = visibleRange.upperBound - visibleRange.lowerBound
        var lower = visibleRange.lowerBound + delta
        lower = max(0, min(lower, totalDuration - window))
        visibleRange = lower...(lower + window)
    }

    /// Tüm grafiği sığdır (sıfırla).
    public mutating func resetZoom() {
        visibleRange = 0...max(1, totalDuration)
    }

    /// Tam yakınlaştırma.
    public mutating func zoomIn(minimumWindow: TimeInterval = 60) {
        zoom(by: 2, focus: nil, minimumWindow: minimumWindow)
    }

    /// Uzaktalaştırma.
    public mutating func zoomOut() {
        zoom(by: 0.5, focus: nil, minimumWindow: 60)
    }

    /// İmleç hareketi (parmak sürükleme) — tam zaman çözünürlüğü yoktur.
    public mutating func moveCursor(to time: TimeInterval) {
        // Not: `cursor` bir `inout` özelliği olduğu için kapanış içinde
        // okunamaz (dışa özlülük ihlali / çalışma zamanı çökmesi).
        // Yerel bir kopya üzerinden karar verilir.
        let target = min(max(0, time), totalDuration)
        let nearest = allPoints.min(by: { abs($0.x - target) < abs($1.x - target) })
        cursor = target
        selection = nearest
    }

    /// İmleci kaldır (seçim korunur).
    public mutating func clearCursor() {
        cursor = nil
    }

    /// Yakındaki noktayı seç (dokunma).
    public mutating func select(nearest time: TimeInterval) {
        let target = min(max(0, time), totalDuration)
        let nearest = allPoints.min(by: { abs($0.x - target) < abs($1.x - target) })
        cursor = target
        selection = nearest
    }

    /// Seçimi temizle.
    public mutating func clearSelection() {
        selection = nil
        cursor = nil
    }

    /// Seçili noktanın okunabilir açıklaması.
    public var selectionText: String? {
        guard let selection else { return nil }
        // Not: `String(format:)` dönüşüm sayısı ile argüman sayısı
        // eşleşmezse tanımsız davranış verir; bu yüzden parçalar ayrı ayrı
        // biçimlendirilip birleştirilir.
        let prefix = metric == .gf99 ? "%" : ""
        let value = String(format: "%@%.1f", prefix, selection.y)
        return [DurationFormatter.clock(selection.x),
                metric.title,
                value + " " + metric.unit,
                String(format: "%.1f m", selection.depth)]
            .joined(separator: "  ·  ")
    }

    // MARK: - Eşleştirme (grafik ile dalış özeti senkronu)

    /// Belirli bir zamandaki derinlik.
    public func depth(at time: TimeInterval) -> Double? {
        allPoints.min(by: { abs($0.x - time) < abs($1.x - time) })?.depth
    }

    /// Deko tavanı profili (grafiğe eklenebilir).
    public static func ceilingPoints(from samples: [DiveSample]) -> [Point] {
        samples.map { sample in
            Point(id: sample.id, x: sample.elapsed, y: sample.ceiling, depth: sample.depth)
        }
    }
}
