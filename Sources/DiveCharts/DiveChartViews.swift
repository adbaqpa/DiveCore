import SwiftUI
import Charts
import DiveCore

/// Dalış profil grafiği — derinlik alanı + sıcaklık/GF99 serileri.
///
/// Grafik verisi `DiveChartData` tarafından **indirgenerek** gelir; görünüm
/// yalnızca çizer. watchOS ve iOS'ta aynı kod kullanılır.
public struct DiveProfileChartView: View {

    /// Hangi seriler gösterilecek
    public struct Options: Equatable, Sendable {
        public var showsDepthArea = true
        public var showsTemperature = true
        public var showsGF99 = false
        public var showsCeiling = true
        public var showsLabels = true

        public init(showsDepthArea: Bool = true, showsTemperature: Bool = true,
                    showsGF99: Bool = false, showsCeiling: Bool = true,
                    showsLabels: Bool = true) {
            self.showsDepthArea = showsDepthArea
            self.showsTemperature = showsTemperature
            self.showsGF99 = showsGF99
            self.showsCeiling = showsCeiling
            self.showsLabels = showsLabels
        }
    }

    private let chart: DiveProfileChart
    private let options: Options

    public init(chart: DiveProfileChart, options: Options = Options()) {
        self.chart = chart
        self.options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if options.showsLabels {
                HStack {
                    Text("Profil")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(String(format: "%.0f dk", chart.duration / 60))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            plot
                .frame(height: 120)
        }
    }

    // MARK: - Gövde

    @ViewBuilder
    private var plot: some View {
        Chart {
            if options.showsDepthArea {
                ForEach(depthArea, id: \.x) { point in
                    AreaMark(x: .value("Süre", point.x), y: .value("Derinlik", point.y))
                        .foregroundStyle(
                            LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.08)],
                                           startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                ForEach(depthLine, id: \.x) { point in
                    LineMark(x: .value("Süre", point.x), y: .value("Derinlik", point.y))
                        .foregroundStyle(accent)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            if options.showsTemperature, let temperature {
                ForEach(temperature, id: \.x) { point in
                    LineMark(x: .value("Süre", point.x), y: .value("Sıcaklık", point.y))
                        .foregroundStyle(.yellow)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .interpolationMethod(.monotone)
                }
            }

            if options.showsGF99, let gf99 {
                ForEach(gf99, id: \.x) { point in
                    LineMark(x: .value("Süre", point.x), y: .value("GF99", point.y))
                        .foregroundStyle(.purple)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }

            if options.showsCeiling, let ceiling {
                ForEach(ceiling, id: \.x) { point in
                    LineMark(x: .value("Süre", point.x), y: .value("Tavan", point.y))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
        }
        .chartYScale(domain: 0...max(chart.maxDepth * 1.15, 10))
        .chartYAxis {
            if options.showsLabels {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let depth = value.as(Double.self) {
                            Text("\(Int(depth))")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
        }
        .chartXAxis {
            if options.showsLabels {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(DurationFormatter.clock(seconds))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Seri erişimi

    private var depthPoints: [(x: Double, y: Double)] {
        chart.series(.depth)?.values.map { (x: $0.elapsed, y: $0.value) } ?? []
    }

    private var depthLine: [(x: Double, y: Double)] { depthPoints }

    private var depthArea: [(x: Double, y: Double)] {
        ChartDownsampler.closedArea(chart.series(.depth)?.points ?? [])
    }

    private var temperature: [(x: Double, y: Double)]? {
        optional(chart.series(.temperature)?.values.map { (x: $0.elapsed, y: $0.value) })
    }

    private var gf99: [(x: Double, y: Double)]? {
        optional(chart.series(.gf99)?.values.map { (x: $0.elapsed, y: $0.value) })
    }

    private var ceiling: [(x: Double, y: Double)]? {
        optional(chart.series(.ceiling)?.values.map { (x: $0.elapsed, y: $0.value) })
    }

    /// Boş seriyi `nil` yapar (grafikte boş çizgi çizmemek için).
    private func optional(_ points: [(x: Double, y: Double)]?) -> [(x: Double, y: Double)]? {
        guard let points, points.count >= 2 else { return nil }
        return points
    }

    private var accent: Color {
        switch chart.series(.depth)?.colorRole {
        case .accent?: return .cyan
        default: return .blue
        }
    }
}

/// Günlük toplam kartı (grafik ekranında CNS/OTU barlarıyla).
public struct DailyTotalsChartView: View {
    private let totals: DailyDiveTotals

    public init(totals: DailyDiveTotals) {
        self.totals = totals
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Bugün")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            bar("OTU", percent: totals.otuPercent, limit: 100)
            bar("CNS", percent: totals.cnsPercent, limit: 100)
            Text(totals.advice())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private func bar(_ title: String, percent: Double, limit: Double) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(percent >= limit ? Color.red : Color.orange)
                        .frame(width: geometry.size.width * min(1, percent / limit))
                }
            }
            .frame(height: 6)
            Text("\(Int(percent))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

/// Aylık dalış sayısı grafiği (defter ekranı).
public struct MonthlyDivesChartView: View {
    private let groups: [(month: Date, dives: [LoggedDive])]

    public init(groups: [(month: Date, dives: [LoggedDive])]) {
        self.groups = groups
    }

    public var body: some View {
        Chart(groups, id: \.month) { group in
            BarMark(x: .value("Ay", group.month, unit: .month),
                    y: .value("Dalış", group.dives.count))
                .foregroundStyle(.cyan.gradient)
                .cornerRadius(3)
            RuleMark(y: .value("Sınır", 1))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        }
        .frame(height: 90)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
    }
}
