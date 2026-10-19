import XCTest
@testable import DiveCore

/// Deko durağı planı: durak listesi, süreler, TTS tutarlılığı.
final class DecoStopPlanTests: XCTestCase {

    // MARK: - Yardımcı

    /// Belirli bir profilde belirli bir ana kadar ilerletilmiş motor.
    private func engineAtBottom(depth: Double,
                                minutes: Double,
                                gas: GasMix = .air,
                                gradientFactors: GradientFactors = .conservative) -> DecoEngine {
        let scenario = DiveScenario(name: "test", segments: [
            .descent(to: depth, at: 15),
            .hover(at: depth, for: minutes * 60)
        ])
        var engine = DecoEngine(gradientFactors: gradientFactors,
                                gases: [gas, .oxygen], gasCylinderIndex: gas == .air ? 0 : 1)
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: gas)
        }
        return engine
    }

    // MARK: - Temel

    func testNoDecoObligationYieldsSafetyStopOnly() {
        let engine = engineAtBottom(depth: 20, minutes: 10)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 20)

        XCTAssertEqual(plan.stops.count, 1)
        XCTAssertEqual(plan.stops.first?.depth, DiveSafetyLimits.safetyStopDepth)
        XCTAssertEqual(plan.stops.first?.isSafetyStop, true)
        XCTAssertFalse(plan.hasDecoObligation)
        XCTAssertEqual(plan.ceilingDepth, 0, accuracy: 0.001)
    }

    func testDecoObligationProducesPlannedStops() {
        let engine = engineAtBottom(depth: 30, minutes: 45)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 30)

        XCTAssertTrue(plan.hasDecoObligation)
        XCTAssertGreaterThanOrEqual(plan.stops.count, 2)
        // Duraklar yüzeye doğru sığlaşır
        let depths = plan.stops.map(\.depth)
        XCTAssertEqual(depths, depths.sorted(by: >))
        // Izgara 3 m
        for depth in depths {
            XCTAssertEqual(depth.truncatingRemainder(dividingBy: 3), 0, accuracy: 0.001)
        }
        // En derin durak tavanın altında olmamalı
        XCTAssertLessThanOrEqual(depths.first ?? 0, plan.ceilingDepth + 3)
    }

    func testStopTimesAreMonotonic() {
        let engine = engineAtBottom(depth: 40, minutes: 60)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 40)

        var previousArrival: TimeInterval = -1
        for stop in plan.stops {
            XCTAssertGreaterThanOrEqual(stop.arrivalTime, previousArrival)
            XCTAssertGreaterThanOrEqual(stop.departureTime, stop.arrivalTime)
            XCTAssertGreaterThanOrEqual(stop.holdTime, 0)
            previousArrival = stop.arrivalTime
        }
        XCTAssertEqual(plan.ascentTime, plan.stops.first?.arrivalTime)
        XCTAssertGreaterThanOrEqual(plan.totalTime, plan.ascentTime)
    }

    func testDeepStopUsesAirShallowStopUsesOxygen() {
        let engine = engineAtBottom(depth: 45, minutes: 70)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 45)
        XCTAssertGreaterThanOrEqual(plan.stops.count, 3)

        for stop in plan.stops {
            if stop.depth <= 6 {
                XCTAssertEqual(stop.gas, .oxygen, "\(Int(stop.depth)) m'de O2 kullanılmalı")
            } else {
                XCTAssertEqual(stop.gas, .air, "\(Int(stop.depth)) m'de hava kullanılmalı")
            }
        }
    }

    func testPlanTotalTimeMatchesTimeToSurface() {
        let engine = engineAtBottom(depth: 30, minutes: 50)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 30)
        // Plan kendi simülasyonunu yapar; TTS ile aynı yöntemi kullandığı için
        // makul bir aralıkta örtüşmeli (fark, durak yuvarlamasından kaynaklanır).
        let tts = engine.timeToSurface(fromDepth: 30)
        XCTAssertEqual(plan.totalTime, tts, accuracy: max(120, tts * 0.1))
    }

    func testTotalHoldTimeAndAscentDistance() {
        let engine = engineAtBottom(depth: 35, minutes: 55)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 35)
        XCTAssertEqual(plan.totalHoldTime, plan.stops.reduce(0) { $0 + $1.holdTime })
        XCTAssertEqual(plan.totalAscentDistance, plan.stops.reduce(0) { $0 + $1.depth })

        // Toplam süre = duraklarda geçen süre + tüm çıkışlar (9 m/dk) + tampon
        let travel = 35.0 / DiveSafetyLimits.recommendedAscentRate * 60
        XCTAssertEqual(plan.totalTime, plan.totalHoldTime + travel + 60, accuracy: 1)
    }

    func testSlowerAscentRateIncreasesTotalTime() {
        let engine = engineAtBottom(depth: 40, minutes: 60)
        let fast = DecoStopPlan.make(from: engine, currentDepth: 40, ascentRate: 18)
        let safe = DecoStopPlan.make(from: engine, currentDepth: 40, ascentRate: 6)
        XCTAssertGreaterThan(safe.totalTime, fast.totalTime)
        XCTAssertEqual(safe.ascentRate, 6)
    }

    func testFirstStopDepthMatchesCeilingGrid() {
        let engine = engineAtBottom(depth: 30, minutes: 45)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 30)
        XCTAssertEqual(plan.firstStopDepth, TissueModel.roundToStopInterval(plan.ceilingDepth))
    }

    func testSurfaceTimeFromDate() {
        let engine = engineAtBottom(depth: 25, minutes: 40)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 25)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(plan.surfaceTime(from: start).timeIntervalSince(start),
                       plan.totalTime, accuracy: 0.001)
    }

    func testPlanDescriptionMentionsStopsAndSurface() {
        let engine = engineAtBottom(depth: 40, minutes: 60)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 40)
        let description = plan.describe()

        XCTAssertTrue(description.contains("m —"), "Durak satırları listelenmeli")
        XCTAssertTrue(description.contains("Yüzey"))
        XCTAssertTrue(description.contains(GasMix.oxygen.label),
                      "Sığ duraklarda O2 önerilmeli (\(GasMix.oxygen.label))")
        XCTAssertTrue(description.contains("toplam"))
        // Her durak satırda görünmeli
        XCTAssertEqual(description.components(separatedBy: "\n").count,
                       plan.stops.count + 1)
    }

    func testDeepDiveProducesLongerPlanThanShallow() {
        let deep = DecoStopPlan.make(from: engineAtBottom(depth: 45, minutes: 50), currentDepth: 45)
        let shallow = DecoStopPlan.make(from: engineAtBottom(depth: 20, minutes: 50), currentDepth: 20)
        XCTAssertGreaterThan(deep.totalTime, shallow.totalTime)
        XCTAssertGreaterThan(deep.stops.count, shallow.stops.count)
    }

    func testStopLabelFormat() {
        let engine = engineAtBottom(depth: 40, minutes: 60)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 30)
        let label = plan.stops.first?.label ?? ""
        XCTAssertTrue(label.contains(" m · "))
        XCTAssertTrue(label.contains(":"))
    }

    func testHoldTimeIsPositiveForRealStops() {
        let engine = engineAtBottom(depth: 42, minutes: 65)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 42)
        // En derin durakta gerçekten beklenmeli
        XCTAssertGreaterThan(plan.stops.first?.holdTime ?? 0, 60)
    }

    // MARK: - Oturum entegrasyonu

    @MainActor
    func testControllerPlanUsesSessionState() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start()
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "t", segments: [
            .descent(to: 30, at: 15), .hover(at: 30, for: 45 * 60.0)
        ])).readings)

        let plan = controller.decoPlan()
        XCTAssertTrue(plan.hasDecoObligation)
        XCTAssertEqual(plan.ceilingDepth, controller.state.ceilingDepth, accuracy: 3)
    }
}