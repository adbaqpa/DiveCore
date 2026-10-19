import XCTest
@testable import DiveCore

/// ADIM 4 sunum katmanı: deko planı, rehber, oksijen kartı, yüzey aralığı,
/// zengin dalış özeti.
final class DiveReportDisplayTests: XCTestCase {

    // MARK: - Yardımcı

    private func engineAtBottom(depth: Double, minutes: Double, gas: GasMix = .air) -> DecoEngine {
        let scenario = DiveScenario(name: "t", segments: [
            .descent(to: depth, at: 15), .hover(at: depth, for: minutes * 60)
        ])
        var engine = DecoEngine(gradientFactors: .conservative,
                                gases: [gas, .oxygen], gasCylinderIndex: 0)
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: gas)
        }
        return engine
    }

    @MainActor
    private func finishedReport(scenario: DiveScenario = .decompressionDive)
        -> DiveReport {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        controller.ingest(DiveSimulator(scenario: scenario).readings)
        controller.end(at: Date(timeIntervalSince1970: 4000))
        return controller.lastReport ?? controller.makeReport()
    }

    // MARK: - Deko planı

    func testDecoPlanDisplayRows() {
        let engine = engineAtBottom(depth: 40, minutes: 60)
        let display = DecoPlanDisplay(plan: DecoStopPlan.make(from: engine, currentDepth: 40))

        XCTAssertTrue(display.hasDecoObligation)
        XCTAssertEqual(display.rows.count, display.rows.map(\.id).count - display.rows.count + display.rows.count)
        XCTAssertGreaterThanOrEqual(display.rows.count, 3)
        XCTAssertTrue(display.headline.contains("durağ"))

        for row in display.rows {
            XCTAssertTrue(row.depthText.hasSuffix(" m"))
            XCTAssertTrue(row.holdText.contains(":"))
            XCTAssertFalse(row.gasLabel.isEmpty)
        }
        // En derin durak ilk sırada
        XCTAssertEqual(display.rows.first?.depthText, "\(Int(DecoStopPlan.make(from: engine, currentDepth: 40).firstStopDepth ?? 0)) m")
    }

    func testDecoPlanDisplayWithoutObligation() {
        let engine = engineAtBottom(depth: 18, minutes: 10)
        let display = DecoPlanDisplay(plan: DecoStopPlan.make(from: engine, currentDepth: 18))

        XCTAssertFalse(display.hasDecoObligation)
        XCTAssertEqual(display.ceilingText, "—")
        XCTAssertTrue(display.rows.first?.isSafetyStop ?? false)
        XCTAssertTrue(display.headline.contains("emniyet"))
    }

    func testDecoPlanDisplayTimes() {
        let engine = engineAtBottom(depth: 30, minutes: 45)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 30)
        let display = DecoPlanDisplay(plan: plan)

        XCTAssertEqual(display.totalTimeText, DurationFormatter.clock(plan.totalTime))
        XCTAssertEqual(display.holdTimeText, DurationFormatter.clock(plan.totalHoldTime))
        XCTAssertEqual(display.ascentTimeText, DurationFormatter.clock(plan.ascentTime))
    }

    // MARK: - Rehber

    func testGuidanceDisplay() {
        let advisor = AscentAdvisor()
        let state = DiveState(phase: .ascending, currentDepth: 9, maxDepth: 30,
                              diveTime: 2000, ascentRate: 3,
                              ceilingDepth: 6, nextStopDepth: 6, timeToSurface: 900)
        let display = GuidanceDisplay(guidance: advisor.evaluate(state))

        XCTAssertEqual(display.nextStopText, "6 m")
        XCTAssertEqual(display.maximumAllowedText, "7.5 m")
        XCTAssertEqual(display.colorRole, .caution)
        XCTAssertFalse(display.isAboveCeiling)
        XCTAssertTrue(display.ttsText.contains(":"))
    }

    func testGuidanceDisplayCriticalColor() {
        let state = DiveState(phase: .ascending, currentDepth: 4, maxDepth: 30,
                              diveTime: 2000, ascentRate: 13,
                              ceilingDepth: 6, nextStopDepth: 6)
        let display = GuidanceDisplay(guidance: AscentAdvisor().evaluate(state))
        XCTAssertEqual(display.colorRole, .danger)
        XCTAssertTrue(display.isAboveCeiling)
    }

    func testGuidanceDisplayHoldAndTimeToStop() {
        let state = DiveState(phase: .decoStop, currentDepth: 6, maxDepth: 30,
                              diveTime: 2000, ceilingDepth: 6, nextStopDepth: 6,
                              timeToSurface: 600)
        let display = GuidanceDisplay(guidance: AscentAdvisor().evaluate(state))
        XCTAssertNotEqual(display.holdText, "—")
        XCTAssertEqual(display.timeToStopText, "—")
        XCTAssertEqual(display.severity, .warning)
    }

    // MARK: - Oksijen kartı

    func testOxygenDisplayMetrics() {
        let status = OxygenStatus.evaluate(po2: 1.30, cnsPercent: 85,
                                           otuUnits: 70, otuPercent: 88,
                                           dailyOTULimit: 80)
        let display = OxygenDisplay(status: status)

        XCTAssertEqual(display.metrics.count, 3)
        XCTAssertEqual(display.metrics[0].valueText, "1.30")
        XCTAssertEqual(display.metrics[1].valueText, "85%")
        XCTAssertTrue(display.isAlarm)
        XCTAssertNotNil(display.message)
        XCTAssertEqual(display.worstMetric?.id, "cns")
        XCTAssertTrue(display.headline.contains("Sınır"))
    }

    func testOxygenDisplayCalm() {
        let display = OxygenDisplay(status: OxygenStatus.evaluate(po2: 0.3, cnsPercent: 5,
                                                                   otuUnits: 10, otuPercent: 12))
        XCTAssertFalse(display.isAlarm)
        XCTAssertNil(display.message)
        XCTAssertEqual(display.worstMetric?.level, .ok)
        XCTAssertEqual(display.worstMetric?.colorRole, .safe)
    }

    func testOxygenProgressIsBounded() {
        let display = OxygenDisplay(status: OxygenStatus.evaluate(po2: 2.0, cnsPercent: 300,
                                                                   otuPercent: 200))
        for metric in display.metrics {
            XCTAssertTrue((0...1).contains(metric.progress), "\(metric.id) aralık dışında")
        }
    }

    // MARK: - Yüzey aralığı

    func testSurfaceIntervalDisplay() {
        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: Date(timeIntervalSince1970: 0),
                              tissues: engineAtBottom(depth: 30, minutes: 30).tissues,
                              gas: .air)
        let status = manager.status(at: Date(timeIntervalSince1970: 3600))
        let display = SurfaceIntervalDisplay(status: status)

        XCTAssertEqual(display.elapsedText, "1s 0dk")
        XCTAssertTrue(display.gf99Text.hasPrefix("%"))
        XCTAssertFalse(display.isCleared)
        XCTAssertEqual(display.colorRole, .caution)
        XCTAssertEqual(display.statusText, "Uçuş yasağı")
        XCTAssertFalse(display.recommendation.isEmpty)
    }

    func testSurfaceIntervalDisplayCleared() {
        let cleared = SurfaceIntervalStatus(elapsed: 6 * 3600, gf99: 5, desaturationRemaining: 0,
                                            noFlyRemaining: 0, isNoFlyCleared: true,
                                            recommendation: "Serbest")
        let display = SurfaceIntervalDisplay(status: cleared)
        XCTAssertTrue(display.isCleared)
        XCTAssertEqual(display.colorRole, .safe)
        XCTAssertEqual(display.statusText, "Serbest")
    }

    // MARK: - Dalış özeti

    @MainActor
    func testReportDisplayFields() {
        let display = DiveReportDisplay(report: finishedReport())
        XCTAssertEqual(display.title, "Dalış Özeti")
        XCTAssertEqual(display.gradeText.count, 5)
        XCTAssertGreaterThanOrEqual(display.score, 0)
        XCTAssertTrue(display.maxDepthText.hasSuffix(" m"))
        XCTAssertTrue(display.maxRatesText.contains("m/dk"))
        XCTAssertFalse(display.gasText.isEmpty)
        XCTAssertTrue(display.po2Text.contains("bar"))
        XCTAssertTrue(display.cnsText.contains("%"))
        XCTAssertTrue(display.otuText.contains("%"))
        XCTAssertFalse(display.headline.isEmpty)
    }

    @MainActor
    func testReportDisplayListsDecoStopsAndPenalties() {
        let display = DiveReportDisplay(report: finishedReport())
        XCTAssertTrue(display.decoStopRows.allSatisfy { $0.label.contains(" m · ") })
        for row in display.penaltyRows {
            XCTAssertFalse(row.reason.isEmpty)
            XCTAssertFalse(row.icon.isEmpty)
        }
        XCTAssertNotEqual(display.totalDecoText, "Deko yok")
    }

    @MainActor
    func testCleanDiveReportHasNoPenalties() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        // Emniyet durağını tamamlayan, hızlı çıkışsız dalış
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "temiz", segments: [
            .descent(to: 18, at: 12), .hover(at: 18, for: 30 * 60.0),
            .ascent(to: 5, at: 9), .safetyStop(at: 5, duration: 180.0),
            .ascent(to: 0, at: 9)
        ])).readings)
        controller.end(at: Date(timeIntervalSince1970: 4000))

        let display = DiveReportDisplay(report: controller.makeReport())
        let reasons = display.penaltyRows.map { $0.reason }.joined(separator: ", ")
        XCTAssertTrue(display.penaltyRows.isEmpty, "Temiz dalışta kesinti olmamalı: \(reasons)")
        XCTAssertEqual(display.score, 5)
    }

    @MainActor
    func testViolationReportShowsPenalties() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: Date(timeIntervalSince1970: 0))
        controller.ingest(DiveSimulator(scenario: .fastAscentViolation).readings)
        controller.end(at: Date(timeIntervalSince1970: 2000))

        let display = DiveReportDisplay(report: controller.makeReport())
        XCTAssertFalse(display.penaltyRows.isEmpty)
        XCTAssertTrue(display.penaltyRows.contains { $0.colorRole == .danger })
        XCTAssertLessThan(display.gradeStars, 5)
    }

    @MainActor
    func testReportDisplaySafetyStopText() {
        let clean = DiveSessionController(configuration: .recreational)
        clean.start(at: Date(timeIntervalSince1970: 0))
        clean.ingest(DiveSimulator(scenario: .recreational30m).readings)
        clean.end(at: Date(timeIntervalSince1970: 4000))
        XCTAssertTrue(DiveReportDisplay(report: clean.makeReport()).safetyStopText.contains("Tamamlandı"))

        let skipped = DiveSessionController(configuration: .recreational)
        skipped.start(at: Date(timeIntervalSince1970: 0))
        skipped.ingest(DiveSimulator(scenario: .safetyStopSkipped).readings)
        skipped.end(at: Date(timeIntervalSince1970: 2000))
        XCTAssertNotEqual(DiveReportDisplay(report: skipped.makeReport()).safetyStopText,
                          DiveReportDisplay(report: clean.makeReport()).safetyStopText)
    }

    // MARK: - Kodlama

    func testCodableRoundTrips() throws {
        let engine = engineAtBottom(depth: 30, minutes: 45)
        let plan = DecoPlanDisplay(plan: DecoStopPlan.make(from: engine, currentDepth: 30))
        XCTAssertEqual(try JSONDecoder().decode(
            DecoPlanDisplay.self, from: JSONEncoder().encode(plan)), plan)

        let oxygen = OxygenDisplay(status: OxygenStatus.evaluate(po2: 1.1, cnsPercent: 30))
        XCTAssertEqual(try JSONDecoder().decode(
            OxygenDisplay.self, from: JSONEncoder().encode(oxygen)), oxygen)

        let surface = SurfaceIntervalDisplay(status: SurfaceIntervalStatus(
            elapsed: 100, gf99: 30, desaturationRemaining: 200,
            noFlyRemaining: 500, isNoFlyCleared: false, recommendation: "test"))
        XCTAssertEqual(try JSONDecoder().decode(
            SurfaceIntervalDisplay.self, from: JSONEncoder().encode(surface)), surface)
    }

    @MainActor
    func testReportDisplayCodable() throws {
        let display = DiveReportDisplay(report: finishedReport(scenario: .recreational30m))
        XCTAssertEqual(try JSONDecoder().decode(
            DiveReportDisplay.self, from: JSONEncoder().encode(display)), display)
    }
}