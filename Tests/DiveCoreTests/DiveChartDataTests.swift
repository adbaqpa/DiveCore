import XCTest
@testable import DiveCore

/// Profil grafiği verisi, seriler ve indirgeme (downsampling).
final class DiveChartDataTests: XCTestCase {

    // MARK: - Yardımcı

    private func samples(count: Int = 60,
                        maxDepth: Double = 30,
                        duration: TimeInterval = 600) -> [DiveSample] {
        (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return DiveSample(elapsed: t * duration,
                              depth: sin(t * .pi) * maxDepth,   // iniş-dip-çıkış profili
                              temperature: 26 - t * 8,
                              ambientPressure: DivePhysics.ambientPressure(depthMeters: sin(t * .pi) * maxDepth),
                              po2: 0.5 + t * 0.4,
                              ascentRate: cos(t * .pi) * 9,
                              gasIndex: 0,
                              gf99: 30 + t * 80,
                              ceiling: t > 0.6 ? 3 : 0,
                              leadingTissuePressure: 1.5)
        }
    }

    private func chart(pointBudget: Int = DiveChartBuilder.defaultPointBudget) -> DiveProfileChart {
        DiveChartBuilder.make(diveID: UUID(), startDate: Date(),
                              samples: samples(), duration: 600, maxDepth: 30,
                              pointBudget: pointBudget)
    }

    // MARK: - Noktalar

    func testPointFromSample() {
        let point = DiveChartPoint(sample: samples(count: 2)[1])
        XCTAssertEqual(point.depth, 0, accuracy: 0.01)   // sin(π) = 0 → yüzey
        // t = 1.0 → sıcaklık 26 − 8 = 18 °C, GF99 = 30 + 80 = %110
        XCTAssertEqual(point.temperature ?? 0, 18, accuracy: 0.01)
        XCTAssertEqual(point.gf99 ?? 0, 110, accuracy: 0.01)
    }

    func testPointIdIsElapsed() {
        let point = DiveChartPoint(elapsed: 42, depth: 10)
        XCTAssertEqual(point.id, 42)
    }

    // MARK: - Seriler

    func testSeriesValues() {
        let points = samples(count: 10).map(DiveChartPoint.init(sample:))
        let depth = DiveChartSeries(kind: .depth, points: points, colorRole: .accent)
        let temperature = DiveChartSeries(kind: .temperature, points: points, colorRole: .caution)

        XCTAssertEqual(depth.values.count, 10)
        XCTAssertGreaterThan(depth.values.map(\.value).max() ?? 0, 20)
        // Sıcaklık serisi azalan bir profil
        XCTAssertLessThan(temperature.values.last!.value, temperature.values.first!.value)
    }

    func testValueDomain() {
        let points = [DiveChartPoint(elapsed: 0, depth: 5),
                      DiveChartPoint(elapsed: 10, depth: 25)]
        let series = DiveChartSeries(kind: .depth, points: points, colorRole: .hero)
        XCTAssertEqual(series.valueDomain.lowerBound, 5)
        XCTAssertEqual(series.valueDomain.upperBound, 25)
    }

    func testValueDomainForFlatSeries() {
        let points = [DiveChartPoint(elapsed: 0, depth: 5), DiveChartPoint(elapsed: 10, depth: 5)]
        let series = DiveChartSeries(kind: .depth, points: points, colorRole: .hero)
        XCTAssertEqual(series.valueDomain.lowerBound, 5)
        XCTAssertGreaterThan(series.valueDomain.upperBound, 5)
    }

    func testSeriesMetadata() {
        XCTAssertEqual(DiveChartSeries.Kind.depth.title, "Derinlik")
        XCTAssertEqual(DiveChartSeries.Kind.depth.unit, "m")
        XCTAssertEqual(DiveChartSeries.Kind.gf99.unit, "%")
        XCTAssertEqual(DiveChartSeries.Kind.ascentRate.unit, "m/dk")
        XCTAssertTrue(DiveChartSeries.Kind.depth.isInverted)
        XCTAssertFalse(DiveChartSeries.Kind.temperature.isInverted)
        XCTAssertEqual(DiveChartSeries.Kind.allCases.count, 6)
    }

    // MARK: - Grafik kurulumu

    func testChartContainsAllSeries() {
        let chart = chart()
        XCTAssertNotNil(chart.series(.depth))
        XCTAssertNotNil(chart.series(.temperature))
        XCTAssertNotNil(chart.series(.gf99))
        XCTAssertNotNil(chart.series(.ceiling))
        XCTAssertNil(chart.series(.po2), "Örneklerde po2 serisi yok")
        XCTAssertEqual(chart.duration, 600)
        XCTAssertEqual(chart.maxDepth, 30)
        XCTAssertEqual(chart.timeDomain, 0...600)
    }

    func testChartFromLoggedDive() {
        let dive = DiveSampleFixtures.dive(at: 0, maxDepth: 30)
        let chart = DiveChartBuilder.make(from: dive)
        XCTAssertEqual(chart.diveID, dive.id)
        XCTAssertEqual(chart.startDate, dive.startDate)
        XCTAssertEqual(chart.duration, dive.totalDiveTime)
    }

    @MainActor
    func testChartFromLogEntry() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        let log = controller.end(at: Date(timeIntervalSince1970: 2000))!

        let chart = DiveChartBuilder.make(from: log)
        XCTAssertNotNil(chart.series(.depth))
        XCTAssertGreaterThan(chart.duration, 0)
    }

    func testEmptyChartIsSafe() {
        let chart = DiveChartBuilder.make(diveID: UUID(), startDate: Date(),
                                          samples: [], duration: 0, maxDepth: 0)
        XCTAssertEqual(chart.series(.depth)?.points.count, 0)
        XCTAssertEqual(chart.timeDomain, 0...1)
    }

    // MARK: - İndirgeme

    func testDownsamplerKeepsShortSeriesIntact() {
        let points = samples(count: 20).map(DiveChartPoint.init(sample:))
        XCTAssertEqual(ChartDownsampler.minMax(points, budget: 100).count, 20)
        XCTAssertEqual(ChartDownsampler.minMax(points, budget: 20).count, 20)
    }

    func testDownsamplerReducesPointCount() {
        let points = samples(count: 600).map(DiveChartPoint.init(sample:))
        let reduced = ChartDownsampler.minMax(points, budget: 60)
        XCTAssertLessThanOrEqual(reduced.count, 60)
        XCTAssertGreaterThan(reduced.count, 10)
    }

    func testDownsamplerPreservesExtremes() {
        let points = samples(count: 600).map(DiveChartPoint.init(sample:))
        let reduced = ChartDownsampler.minMax(points, budget: 40)

        let originalMax = points.map(\.depth).max() ?? 0
        let originalMin = points.map(\.depth).min() ?? 0
        XCTAssertEqual(reduced.map(\.depth).max() ?? 0, originalMax, accuracy: 0.001,
                       "En derin nokta korunmalı")
        XCTAssertEqual(reduced.map(\.depth).min() ?? 0, originalMin, accuracy: 0.001)
    }

    func testDownsamplerKeepsEndpointsAndOrdering() {
        let points = samples(count: 300).map(DiveChartPoint.init(sample:))
        let reduced = ChartDownsampler.minMax(points, budget: 30)

        XCTAssertEqual(reduced.first?.elapsed, points.first?.elapsed)
        XCTAssertEqual(reduced.last?.elapsed, points.last?.elapsed)

        let elapsed = reduced.map(\.elapsed)
        XCTAssertEqual(elapsed, elapsed.sorted(), "Zaman sırası korunmalı")
        XCTAssertEqual(Set(elapsed).count, elapsed.count, "Aynı zaman iki kez olmamalı")
    }

    func testDownsamplerBudgetOfTwoKeepsEndpoints() {
        let points = samples(count: 100).map(DiveChartPoint.init(sample:))
        let reduced = ChartDownsampler.minMax(points, budget: 2)
        XCTAssertEqual(reduced.count, 2)
        XCTAssertEqual(reduced.first?.elapsed, points.first?.elapsed)
        XCTAssertEqual(reduced.last?.elapsed, points.last?.elapsed)
    }

    func testUniformDownsampler() {
        let values = (0..<100).map { (elapsed: Double($0), value: Double($0)) }
        let reduced = ChartDownsampler.uniform(values, budget: 10)
        XCTAssertEqual(reduced.count, 10)
        XCTAssertEqual(reduced.last?.elapsed, 99)
        XCTAssertEqual(reduced.first?.elapsed, 0)
    }

    func testClosedAreaClosesPolygon() {
        let points = samples(count: 5).map(DiveChartPoint.init(sample:))
        let area = ChartDownsampler.closedArea(points)
        XCTAssertEqual(area.count, points.count + 2, "Başlangıç ve bitiş taban çizgisi eklenir")
        XCTAssertEqual(area.first?.y, 0)
        XCTAssertEqual(area.last?.y, 0)
        XCTAssertEqual(area.first?.x, points.first?.elapsed)
        XCTAssertEqual(area.last?.x, points.last?.elapsed)
    }

    func testClosedAreaOnEmptySeries() {
        XCTAssertTrue(ChartDownsampler.closedArea([]).isEmpty)
    }

    // MARK: - Kodlama

    func testChartPointCodable() throws {
        let point = DiveChartPoint(elapsed: 30, depth: 12, temperature: 20,
                                   po2: 1.0, gf99: 50, ceiling: 0, ascentRate: 2)
        let data = try JSONEncoder().encode(point)
        XCTAssertEqual(try JSONDecoder().decode(DiveChartPoint.self, from: data), point)
    }

    // MARK: - LogbookDisplay

    @MainActor
    func testLogbookDisplayRows() throws {
        let store = InMemoryDiveLogStore()
        let logbook = DiveLogbook(store: store)
        try logbook.addAll([
            DiveSampleFixtures.dive(at: 0, maxDepth: 30),
            DiveSampleFixtures.dive(at: -86400, maxDepth: 18)
        ])

        let display = logbook.display()
        XCTAssertFalse(display.isEmpty)
        XCTAssertEqual(display.rows.count, 2)
        XCTAssertTrue(display.rows[0].title.contains("30.0"))
        XCTAssertEqual(display.rows[0].gradeText.count, 5)
        XCTAssertLessThanOrEqual(display.rows[0].depthFraction, 1)
        XCTAssertFalse(display.statisticsLines.isEmpty)
        XCTAssertFalse(display.todayAdvice.isEmpty)
    }

    @MainActor
    func testLogbookDisplayEmpty() {
        let logbook = DiveLogbook(store: InMemoryDiveLogStore())
        let display = logbook.display()
        XCTAssertTrue(display.isEmpty)
        XCTAssertNil(display.today)
        XCTAssertTrue(display.todayAdvice.contains("Bugün"))
    }
}