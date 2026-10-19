import XCTest
@testable import DiveCore

/// Çıkış rehberi: tavan tamponu, sonraki dura, talimat, hız/derin iniş uyarıları.
final class AscentAdvisorTests: XCTestCase {

    // MARK: - Yardımcı

    private func state(depth: Double,
                       ceiling: Double = 0,
                       nextStop: Double? = nil,
                       ndl: TimeInterval = 0,
                       ascentRate: Double = 0,
                       tts: TimeInterval = 0,
                       safetyStop: SafetyStopState = SafetyStopState()) -> DiveState {
        DiveState(
            phase: depth <= 0.3 ? .surfaced : .ascending,
            currentDepth: depth,
            maxDepth: 30,
            diveTime: 1800,
            ascentRate: ascentRate,
            noDecompressionLimit: ndl,
            ceilingDepth: ceiling,
            nextStopDepth: nextStop,
            timeToSurface: tts,
            safetyStop: safetyStop)
    }

    // MARK: - Serbest çıkış

    func testNoObligationAllowsSurfacing() {
        let guidance = AscentAdvisor().evaluate(state(depth: 8, ndl: 600, tts: 120))
        XCTAssertEqual(guidance.severity, .ok)
        XCTAssertNil(guidance.nextStopDepth)
        XCTAssertEqual(guidance.maximumAllowedDepth, 0)
        XCTAssertTrue(guidance.instruction.contains("yüzeye"))
    }

    func testAtSurfaceGuidance() {
        let guidance = AscentAdvisor().evaluate(state(depth: 0))
        XCTAssertEqual(guidance.severity, .ok)
        XCTAssertEqual(guidance.currentDepth, 0)
    }

    // MARK: - Tavan

    func testCeilingBufferIsApplied() {
        let advisor = AscentAdvisor(ceilingBuffer: 1.5)
        let guidance = advisor.evaluate(state(depth: 9, ceiling: 6, nextStop: 6))
        XCTAssertEqual(guidance.maximumAllowedDepth, 7.5, accuracy: 0.001)
    }

    func testAboveCeilingIsCritical() {
        let guidance = AscentAdvisor().evaluate(state(depth: 5.2, ceiling: 6, nextStop: 6))
        XCTAssertEqual(guidance.severity, .critical)
        XCTAssertTrue(guidance.isAboveCeiling)
        XCTAssertTrue(guidance.instruction.contains("Tavanın ÜSTÜNDE"))
    }

    func testAtCeilingIsNotViolation() {
        let guidance = AscentAdvisor().evaluate(state(depth: 6.2, ceiling: 6, nextStop: 6))
        XCTAssertFalse(guidance.isAboveCeiling)
        XCTAssertLessThan(guidance.severity, .critical)
    }

    func testDescendingIntoStopGivesInstruction() {
        let guidance = AscentAdvisor().evaluate(state(depth: 10, ceiling: 9, nextStop: 6))
        XCTAssertEqual(guidance.severity, .caution)
        XCTAssertTrue(guidance.instruction.contains("6 m'ye"))
        XCTAssertGreaterThan(guidance.timeToStop, 0)
        XCTAssertEqual(guidance.timeToStop, 4.0 / 9.0 * 60, accuracy: 1)
    }

    func testHoldingAtStopGivesWaitInstruction() {
        let guidance = AscentAdvisor().evaluate(state(depth: 6, ceiling: 6, nextStop: 6))
        XCTAssertEqual(guidance.severity, .warning)
        XCTAssertTrue(guidance.shouldStop)
        XCTAssertGreaterThan(guidance.stopHoldTime, 0)
        XCTAssertTrue(guidance.instruction.contains("bekle"))
    }

    func testStopHoldTimeIsZeroWhenCeilingCleared() {
        // Bekleme gerekmiyorsa: tavan tamamen temizlenmiş, sonraki durak yok
        let cleared = AscentAdvisor().evaluate(state(depth: 6.1, ceiling: 0, nextStop: nil))
        XCTAssertNil(cleared.nextStopDepth)
        XCTAssertEqual(cleared.stopHoldTime, 0)
        XCTAssertFalse(cleared.shouldStop)

        // Taraf sıfırı: dekor zorunluluğu olması durumunda tavan her zaman
        // durağın üzerindedir, dolayısıyla bekleme süresi daima pozitiftir.
        XCTAssertGreaterThan(AscentAdvisor().stopHoldTimeForStop(depth: 6, ceiling: 6), 0)
        XCTAssertGreaterThan(AscentAdvisor().stopHoldTimeForStop(depth: 6, ceiling: 8), 0)
    }

    func testStopHoldEstimateScalesWithDepthGap() {
        let advisor = AscentAdvisor()
        XCTAssertEqual(advisor.stopHoldTimeForStop(depth: 6, ceiling: 3), 0)
        XCTAssertEqual(advisor.stopHoldTimeForStop(depth: 0, ceiling: 6), 0)
        XCTAssertEqual(advisor.stopHoldTimeForStop(depth: 3, ceiling: 3), 60,
                       "Tavan == durakken en az 1 dk beklenir")
        XCTAssertEqual(advisor.stopHoldTimeForStop(depth: 3, ceiling: 6), 120)
        XCTAssertEqual(advisor.stopHoldTimeForStop(depth: 3, ceiling: 15), 480)
    }

    // MARK: - Emniyet durağı

    func testSafetyStopTakesPrecedenceForHoldTime() {
        var stop = SafetyStopState()
        stop.isActive = true
        stop.accumulated = 60

        let guidance = AscentAdvisor(safetyStopDepth: 5)
            .evaluate(state(depth: 4.9, safetyStop: stop))
        XCTAssertEqual(guidance.nextStopDepth, 5)
        XCTAssertEqual(guidance.stopHoldTime, 120, accuracy: 1)
        XCTAssertTrue(guidance.shouldStop)
    }

    // MARK: - Hız uyarıları

    func testFastAscentOverridesEverything() {
        let guidance = AscentAdvisor().evaluate(state(depth: 12, ceiling: 6, nextStop: 6,
                                                      ascentRate: 14))
        XCTAssertEqual(guidance.severity, .critical)
        XCTAssertTrue(guidance.instruction.contains("YAVAŞLA"))
    }

    func testCautionRateBand() {
        let guidance = AscentAdvisor().evaluate(state(depth: 12, ndl: 900, ascentRate: 8))
        XCTAssertEqual(guidance.severity, .caution)
        XCTAssertTrue(guidance.instruction.contains("yavaşlat"))
    }

    func testSlowRateProducesNoCaution() {
        // 7-10 m/dk bandı "dikkat" (sarı), 10 üstü alarm üretir
        let guidance = AscentAdvisor().evaluate(state(depth: 12, ndl: 900, ascentRate: 6))
        XCTAssertEqual(guidance.severity, .ok)

        let band = AscentAdvisor().evaluate(state(depth: 12, ndl: 900, ascentRate: 9))
        XCTAssertEqual(band.severity, .caution, "Önerilen 9 m/dk sarı bantta")
    }

    func testFastDescentTriggersCaution() {
        let guidance = AscentAdvisor().evaluate(
            state(depth: 25, ndl: 1200, ascentRate: -30))
        XCTAssertEqual(guidance.descentRate, 30)
        XCTAssertEqual(guidance.severity, .caution)
        XCTAssertTrue(guidance.instruction.contains("İniş"))
    }

    func testSeverityOrdering() {
        XCTAssertGreaterThan(AscentAdvisor.Guidance.Severity.critical, .warning)
        XCTAssertGreaterThan(AscentAdvisor.Guidance.Severity.warning, .caution)
        XCTAssertGreaterThan(AscentAdvisor.Guidance.Severity.caution, .ok)
    }

    // MARK: - Özel ayarlar

    func testCustomLimitsAreRespected() {
        let advisor = AscentAdvisor(maximumAscentRate: 6, cautionAscentRate: 4,
                                   maximumDescentRate: 15)
        XCTAssertEqual(advisor.evaluate(state(depth: 12, ndl: 900, ascentRate: 7)).severity, .critical)
        XCTAssertEqual(advisor.evaluate(state(depth: 12, ndl: 900, ascentRate: 5)).severity, .caution)
        XCTAssertEqual(advisor.evaluate(state(depth: 20, ndl: 900, ascentRate: -20)).severity, .caution)
    }

    // MARK: - Oturum entegrasyonu

    @MainActor
    func testControllerGuidanceFollowsLiveState() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start()
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "t", segments: [
            .descent(to: 40, at: 15), .hover(at: 40, for: 60 * 60.0),
            .ascent(to: 0, at: 9)
        ])).readings)

        let guidance = controller.guidance
        // Deko dalışında tavan > 0 olmalı ve rehber durak göstermeli
        XCTAssertGreaterThan(controller.state.ceilingDepth, 0)
        XCTAssertNotNil(guidance.nextStopDepth)
        XCTAssertLessThanOrEqual(guidance.maximumAllowedDepth,
                                 controller.state.ceilingDepth + 1.6)
    }
}