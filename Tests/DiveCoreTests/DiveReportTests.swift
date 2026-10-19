import XCTest
@testable import DiveCore

/// Dalış sonu raporu: uç değerler, deko durakları, kesintiler, not.
final class DiveReportTests: XCTestCase {

    // MARK: - Yardımcı

    @MainActor
    private func finishedDive(scenario: DiveScenario,
                              configuration: DiveConfiguration = .recreational,
                              beforeEnd: ((DiveSessionController) -> Void)? = nil)
        -> (DiveSessionController, LogEntry, DiveReport) {
        let controller = DiveSessionController(configuration: configuration)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        controller.start(at: start)
        controller.ingest(DiveSimulator(scenario: scenario).readings)
        beforeEnd?(controller)
        let log = controller.end(at: start.addingTimeInterval(controller.state.diveTime))!
        return (controller, log, controller.lastReport ?? controller.makeReport(log: log))
    }

    private func extremes(maxAscent: Double = 0, maxDescent: Double = 0,
                          minTemperature: Double = 18, maxTemperature: Double = 24) -> DiveExtremes {
        DiveExtremes(maxAscentRate: maxAscent, maxDescentRate: maxDescent,
                     minimumTemperature: minTemperature, maximumTemperature: maxTemperature)
    }

    // MARK: - Temel alanlar

    @MainActor
    func testReportCarriesCoreStatistics() {
        let (_, log, report) = finishedDive(scenario: .recreational30m)

        XCTAssertEqual(report.maxDepth, log.maxDepth, accuracy: 0.5)
        XCTAssertEqual(report.totalDiveTime, log.totalDiveTime, accuracy: 1)
        XCTAssertEqual(report.averageDepth, log.averageDepth, accuracy: 0.5)
        XCTAssertGreaterThan(report.maxAscentRate, 5)
        XCTAssertGreaterThan(report.maxGF99, 50)
        XCTAssertTrue(report.gases.contains(.air))
    }

    @MainActor
    func testReportTracksExtremes() {
        let (controller, _, _) = finishedDive(scenario: .recreational30m)
        let measured = controller.measuredExtremes
        XCTAssertGreaterThan(measured.maxAscentRate, 5)
        XCTAssertGreaterThan(measured.maxDescentRate, 5)
        XCTAssertLessThan(measured.minimumTemperature, measured.maximumTemperature)
    }

    @MainActor
    func testExtremesDefaultWhenNoMeasurement() {
        let resolved = DiveExtremes().resolved
        XCTAssertEqual(resolved.minimumTemperature, 0)
        XCTAssertEqual(resolved.maximumTemperature, 0)
        XCTAssertEqual(resolved.maxAscentRate, 0)
    }

    @MainActor
    func testOxygenAssessmentInReport() {
        let (_, _, report) = finishedDive(scenario: .recreational30m)
        XCTAssertGreaterThan(report.maxPO2, 0.7)
        XCTAssertGreaterThanOrEqual(report.oxygen.cnsLevel, .ok)
        XCTAssertNotNil(report.oxygen.message ?? "ok")
        XCTAssertGreaterThanOrEqual(report.oxygen.po2Level, .ok)
    }

    // MARK: - Deko durakları

    @MainActor
    func testDecoStopsAreRecorded() {
        let (controller, _, report) = finishedDive(scenario: .decompressionDive)
        XCTAssertFalse(controller.recordedDecoStops.isEmpty,
                       "Deko dalışında duraklar kaydedilmeli")
        XCTAssertEqual(report.decoStops.count, controller.recordedDecoStops.count)
        XCTAssertGreaterThan(report.totalDecoTime, 0)

        // Duraklar yüzeye doğru sığlaşmalı ve en az 20 sn sürmeli
        let depths = report.decoStops.map(\.depth)
        XCTAssertEqual(depths, depths.sorted(by: >))
        for stop in report.decoStops {
            XCTAssertGreaterThanOrEqual(stop.duration, 20)
            XCTAssertGreaterThanOrEqual(stop.departureElapsed, stop.arrivalElapsed)
        }
    }

    @MainActor
    func testNoDecoDiveRecordsNoStops() {
        let (controller, _, report) = finishedDive(scenario: .beginner)
        XCTAssertTrue(controller.recordedDecoStops.isEmpty)
        XCTAssertEqual(report.totalDecoTime, 0)
    }

    @MainActor
    func testDecoStopIsNotRecordedWhileAtBottom() {
        // Tavan dipte oluşsa bile, dalgıç durakta değilse kayıt açılmaz
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "t", segments: [
            .descent(to: 30, at: 15), .hover(at: 30, for: 45 * 60.0)
        ])).readings)

        XCTAssertGreaterThan(controller.state.ceilingDepth, 0, "Tavan oluşmuş olmalı")
        XCTAssertTrue(controller.recordedDecoStops.isEmpty,
                      "Dipte otururken deko durağı kaydedilmemeli")
    }

    @MainActor
    func testDecoStopMarkersAreRecorded() {
        let (controller, _, _) = finishedDive(scenario: .decompressionDive)
        XCTAssertTrue(controller.markers.contains { $0.kind == .decoStop })
    }

    func testDecoStopRecordLabel() {
        let record = DecoStopRecord(depth: 6, arrivalElapsed: 1500,
                                    duration: 300, departureElapsed: 1800, gas: .oxygen)
        XCTAssertEqual(record.label, "6 m · 05:00")
    }

    // MARK: - Kesintiler ve not

    func testFastAscentProducesPenalty() {
        let state = DiveState(phase: .ended, maxDepth: 30, diveTime: 1200,
                              safetyStop: SafetyStopState())
        let report = DiveReport.analyze(state: state, log: nil, decoStops: [],
                                        extremes: extremes(maxAscent: 15))
        XCTAssertTrue(report.penalties.contains { $0.kind == .fastAscent })
        XCTAssertLessThanOrEqual(report.score, 3)
        XCTAssertNotEqual(report.grade, .excellent)
    }

    func testFastDescentProducesPenalty() {
        let state = DiveState(phase: .ended, maxDepth: 30, diveTime: 1200)
        let report = DiveReport.analyze(state: state, log: nil, decoStops: [],
                                        extremes: extremes(maxDescent: 35))
        XCTAssertTrue(report.penalties.contains { $0.kind == .fastDescent })
    }

    func testMissingSafetyStopProducesPenalty() {
        var stop = SafetyStopState()
        stop.accumulated = 30
        let state = DiveState(phase: .ended, maxDepth: 30, diveTime: 1200, safetyStop: stop)
        let report = DiveReport.analyze(state: state, log: nil, decoStops: [],
                                        extremes: extremes())
        XCTAssertTrue(report.penalties.contains { $0.kind == .missingSafetyStop })
    }

    func testDeepAndLongDivePenalties() {
        let state = DiveState(phase: .ended, maxDepth: 45, diveTime: 60 * 60)
        let report = DiveReport.analyze(state: state, log: nil, decoStops: [],
                                        extremes: extremes())
        XCTAssertTrue(report.penalties.contains { $0.kind == .deepDive })
        XCTAssertTrue(report.penalties.contains { $0.kind == .longDive })
    }

    func testCleanDiveHasFullScore() {
        var stop = SafetyStopState()
        stop.accumulated = 180
        let state = DiveState(phase: .ended, maxDepth: 18, diveTime: 45 * 60, safetyStop: stop)
        let report = DiveReport.analyze(state: state, log: nil, decoStops: [],
                                        extremes: extremes(maxAscent: 9, maxDescent: 15))
        XCTAssertEqual(report.score, 5)
        XCTAssertEqual(report.grade, .excellent)
        XCTAssertTrue(report.penalties.isEmpty)
    }

    func testScoreNeverGoesNegative() {
        let state = DiveState(phase: .ended, maxDepth: 60, diveTime: 90 * 60)
        let report = DiveReport.analyze(state: state, log: nil, decoStops: [],
                                        extremes: extremes(maxAscent: 40, maxDescent: 60))
        XCTAssertGreaterThanOrEqual(report.score, 0)
        XCTAssertEqual(report.grade, .poor)
    }

    func testGradeMappingFromScore() {
        XCTAssertEqual(DiveGrade.grade(score: 5), .excellent)
        XCTAssertEqual(DiveGrade.grade(score: 4), .good)
        XCTAssertEqual(DiveGrade.grade(score: 3), .good)
        XCTAssertEqual(DiveGrade.grade(score: 2), .fair)
        XCTAssertEqual(DiveGrade.grade(score: 0), .poor)
    }

    @MainActor
    func testViolationScenarioIsPenalized() {
        let (_, _, report) = finishedDive(scenario: .fastAscentViolation)
        XCTAssertTrue(report.penalties.contains { $0.kind == .fastAscent })
        XCTAssertLessThan(report.grade.stars, 5)
        XCTAssertFalse(report.headline.isEmpty)
    }

    // MARK: - Türetilmiş alanlar

    @MainActor
    func testBottomTimeIsPositive() {
        let (_, _, report) = finishedDive(scenario: .recreational30m)
        XCTAssertGreaterThan(report.bottomTime, 0)
        XCTAssertLessThan(report.bottomTime, report.totalDiveTime)
    }

    @MainActor
    func testMarkerAndGasChangeCounts() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 300))
        controller.addMarker(label: "Balık")
        controller.addMarker(label: "Kaya")
        controller.switchGas(to: 0)
        let report = controller.makeReport()

        XCTAssertEqual(report.markerCount, 2)
        XCTAssertEqual(report.gasChangeCount, 1)
    }

    @MainActor
    func testReportIsProducedOnEnd() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        XCTAssertNil(controller.lastReport)
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        controller.end(at: Date(timeIntervalSince1970: 1800))
        XCTAssertNotNil(controller.lastReport)
        XCTAssertEqual(controller.lastReport?.maxDepth ?? 0, controller.state.maxDepth, accuracy: 0.5)
    }

    // MARK: - Kodlama

    @MainActor
    func testReportCodableRoundTrip() throws {
        let (_, _, report) = finishedDive(scenario: .recreational30m)
        let data = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(DiveReport.self, from: data), report)
    }

    func testPenaltyCarriesReason() {
        let penalty = DivePenalty(kind: .highCNS, reason: "CNS %85", weight: 1)
        XCTAssertTrue(penalty.reason.contains("85"))
        XCTAssertEqual(penalty.weight, 1)
        XCTAssertEqual(penalty.kind, .highCNS)
    }
}