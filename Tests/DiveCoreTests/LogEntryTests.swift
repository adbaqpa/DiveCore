import XCTest
@testable import DiveCore

/// `LogEntry` / `DiveSample`: türetilmiş seriler, özet ve kalıcılık.
final class LogEntryTests: XCTestCase {

    private func makeSamples() -> [DiveSample] {
        [
            DiveSample(elapsed: 0, depth: 0, temperature: 20, ambientPressure: 1.0, po2: 0.21),
            DiveSample(elapsed: 60, depth: 20, temperature: 19, ambientPressure: 3.0, po2: 0.63),
            DiveSample(elapsed: 300, depth: 30, temperature: 18, ambientPressure: 4.0, po2: 0.83,
                       ascentRate: 0, gf99: 42, ceiling: 0, leadingTissuePressure: 2.4),
            DiveSample(elapsed: 1500, depth: 30, temperature: 17, ambientPressure: 4.0, po2: 0.83,
                       gf99: 78, ceiling: 1.8, leadingTissuePressure: 3.1),
            DiveSample(elapsed: 2400, depth: 0, temperature: 20, ambientPressure: 1.0, po2: 0.21,
                       ascentRate: 5, gf99: 60, leadingTissuePressure: 1.9)
        ]
    }

    private func makeLog() -> LogEntry {
        LogEntry(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_002_400),
            location: "Kaş, Antalya",
            gases: [.air, .ean32],
            startGasIndex: 1,
            samples: makeSamples(),
            maxDepth: 30, averageDepth: 26.4, totalDiveTime: 2400,
            waterTemperatureStart: 19, waterTemperatureEnd: 20,
            waterTemperatureMin: 17, waterTemperatureMax: 20,
            cnsPercent: 12, otuUnits: 9.6, maxPO2: 0.83, maxGF99: 78,
            minimumNoDecompressionLimit: 0,
            gradientFactors: .conservative,
            hadDecoObligation: true, safetyStopCompleted: true, safetyStopAccumulated: 180,
            noFlyTime: 4 * 3600, recommendedSurfaceInterval: 5400,
            rating: 4, notes: "Akıntı güçlüydü"
        )
    }

    // MARK: - Seriler

    func testDerivedSeriesMatchSamples() {
        let log = makeLog()
        XCTAssertEqual(log.depthSeries, [0, 20, 30, 30, 0])
        XCTAssertEqual(log.temperatureSeries, [20, 19, 18, 17, 20])
        XCTAssertEqual(log.timeSeries, [0, 60, 300, 1500, 2400])
        XCTAssertEqual(log.gf99Series, [0, 0, 42, 78, 60])
        XCTAssertEqual(log.tissueLoadSeries, [0.79, 0.79, 2.4, 3.1, 1.9])
    }

    func testSeriesAreEmptyForEmptyLog() {
        let log = LogEntry(startDate: Date())
        XCTAssertTrue(log.depthSeries.isEmpty)
        XCTAssertTrue(log.temperatureSeries.isEmpty)
        XCTAssertEqual(log.totalVerticalDistance, 0)
        XCTAssertEqual(log.exitDepth, 0)
    }

    func testSeriesRespectSampleOrder() {
        let samples = makeSamples()
        let log = LogEntry(startDate: Date(), samples: samples)
        XCTAssertEqual(log.depthSeries, samples.map(\.depth))
    }

    // MARK: - Türetilmiş özetler

    func testTotalVerticalDistance() {
        // 0→20→30→30→0 = 20 + 10 + 0 + 30 = 60 m
        XCTAssertEqual(makeLog().totalVerticalDistance, 60, accuracy: 1e-9)
    }

    func testGasLabels() {
        let log = makeLog()
        XCTAssertEqual(log.startGas, .ean32)
        XCTAssertEqual(log.startGasLabel, "EAN32")
        XCTAssertEqual(log.exitGasLabel, "EAN32")
    }

    func testGasIndexOutOfRangeFallsBackToAir() {
        let log = LogEntry(startDate: Date(), gases: [.air], startGasIndex: 9)
        XCTAssertEqual(log.startGas, .air)
        XCTAssertEqual(log.exitGas, .air)
    }

    func testDurationUsesEndDateWhenPresent() {
        let log = makeLog()
        XCTAssertEqual(log.duration, 2400)
    }

    func testDurationFallsBackToTotalDiveTime() {
        let log = LogEntry(startDate: Date(), totalDiveTime: 1800)
        XCTAssertEqual(log.duration, 1800)
    }

    func testSummaryLine() {
        XCTAssertEqual(makeLog().summaryLine, "30.0 m · 40dk · EAN32")
    }

    func testEstimatedNoFlyClearance() {
        let log = makeLog()
        XCTAssertEqual(log.estimatedNoFlyClearance,
                       log.endDate!.addingTimeInterval(4 * 3600))
    }

    func testEstimatedNoFlyClearanceIsNilWithoutEndDate() {
        let log = LogEntry(startDate: Date(), noFlyTime: 3600)
        XCTAssertNil(log.estimatedNoFlyClearance)
    }

    // MARK: - Kimlik ve eşitlik

    func testIdentityIsStable() {
        let log = makeLog()
        XCTAssertEqual(log.id, log.id)
        XCTAssertNotEqual(log.id, makeLog().id)
    }

    // MARK: - Kalıcılık (WatchConnectivity / JSON aktarımı için)

    func testCodableRoundTrip() throws {
        let log = makeLog()
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(LogEntry.self, from: data)

        XCTAssertEqual(decoded, log)
        XCTAssertEqual(decoded.depthSeries, log.depthSeries)
        XCTAssertEqual(decoded.tissueLoadSeries, log.tissueLoadSeries)
        XCTAssertEqual(decoded.gases, log.gases)
        XCTAssertEqual(decoded.gradientFactors, log.gradientFactors)
    }

    func testSampleCodableRoundTrip() throws {
        let sample = DiveSample(elapsed: 120, depth: 18.5, temperature: 19.5,
                                ambientPressure: 2.85, po2: 0.588,
                                ascentRate: -7.2, gasIndex: 1, gf99: 55,
                                ceiling: 2.9, leadingTissuePressure: 2.2)
        let data = try JSONEncoder().encode(sample)
        XCTAssertEqual(try JSONDecoder().decode(DiveSample.self, from: data), sample)
    }

    func testJSONEncodingStaysCompact() throws {
        // Gözlemlenebilir veri boyutu sınırı (WatchConnectivity kuyruğu için)
        var log = LogEntry(startDate: Date())
        log.samples = (0..<500).map { index in
            DiveSample(elapsed: Double(index) * 10, depth: 30, temperature: 18,
                       ambientPressure: 4.0, po2: 0.83)
        }
        let data = try JSONEncoder().encode(log)
        XCTAssertLessThan(data.count, 100_000, "500 örnek 100 KB'ı aşmamalı")
    }
}