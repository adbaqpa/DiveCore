import XCTest
@testable import DiveCore

/// ADIM 6 — Derin durak (deep stop) algoritması ve deko planı entegrasyonu.
final class DeepStopCalculatorTests: XCTestCase {

    // MARK: - Yardımcı

    /// Belirli bir profilde belirli bir ana kadar ilerletilmiş motor.
    private func engineAtBottom(depth: Double,
                                minutes: Double,
                                gas: GasMix = .air) -> DecoEngine {
        engineAtBottomGF(depth: depth, minutes: minutes, gas: gas, gf: .conservative)
    }

    private func engineAtBottomGF(depth: Double,
                                  minutes: Double,
                                  gas: GasMix = .air,
                                  gf: GradientFactors = .conservative) -> DecoEngine {
        let scenario = DiveScenario(name: "t", segments: [
            .descent(to: depth, at: 15), .hover(at: depth, for: minutes * 60)
        ])
        var engine = DecoEngine(gradientFactors: gf,
                                gases: [gas, .oxygen], gasCylinderIndex: 0)
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: gas)
        }
        return engine
    }

    // MARK: - Temel

    func testDisabledProducesNoStops() {
        let engine = engineAtBottom(depth: 45, minutes: 60)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: 12, settings: .disabled)
        XCTAssertTrue(stops.isEmpty)
    }

    func testShallowDiveProducesNoDeepStops() {
        let engine = engineAtBottom(depth: 20, minutes: 15)   // deko yok
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: 0, settings: .standard)
        XCTAssertTrue(stops.isEmpty, "20 m sığ dalışta derin durak olmamalı")
    }

    func testDeepDiveProducesCandidates() {
        // 40 m / 60 dk (GF 80/85) → tavan 14.4 m, 15 m ve 18 m'de canlı duraklar
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let firstStop = TissueModel.roundToStopInterval(
            engine.ceiling(atDepth: 40).depthMeters)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: firstStop, settings: .standard)

        XCTAssertFalse(stops.isEmpty)
        XCTAssertTrue(stops.allSatisfy { $0.depth > firstStop })
        XCTAssertLessThanOrEqual(stops.map(\.depth).max() ?? 0, engine.tissues.maxDepth + 0.1)
    }

    func testNoDeepStopsWithoutDecoObligation() {
        // Tavan yoksa (ilk deko durağı = 0) derin durak hesaplanmaz
        let engine = engineAtBottom(depth: 20, minutes: 15)
        XCTAssertEqual(engine.ceiling(atDepth: 20).depthMeters, 0, accuracy: 0.5)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: 0, settings: .standard)
        XCTAssertTrue(stops.isEmpty)
    }

    func testStopsAreSortedDeepToShallow() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let firstStop = TissueModel.roundToStopInterval(
            engine.ceiling(atDepth: 40).depthMeters)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: firstStop, settings: .standard)

        let depths = stops.map(\.depth)
        XCTAssertEqual(depths, depths.sorted(by: >), "Derinlemeden yüzeye sıralı olmalı")
    }

    func testStopsAreOnGrid() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let firstStop = TissueModel.roundToStopInterval(
            engine.ceiling(atDepth: 45).depthMeters)
        let settings = DeepStopCalculator.Settings(isEnabled: true, interval: 3,
                                                   firstStopDepth: 6, lastStopDepth: 45)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: firstStop, settings: settings)

        for stop in stops {
            XCTAssertEqual(stop.depth.truncatingRemainder(dividingBy: 3), 0, accuracy: 0.001)
        }
    }

    func testCustomIntervalRespected() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let firstStop = TissueModel.roundToStopInterval(
            engine.ceiling(atDepth: 45).depthMeters)
        let settings = DeepStopCalculator.Settings(isEnabled: true, interval: 6,
                                                   firstStopDepth: 6, lastStopDepth: 45)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: firstStop, settings: settings)

        for stop in stops {
            XCTAssertEqual(stop.depth.truncatingRemainder(dividingBy: 6), 0, accuracy: 0.001)
        }
        XCTAssertFalse(stops.isEmpty)
    }

    func testDeeperDiveHasMoreDeepStops() {
        let shallowEngine = engineAtBottomGF(depth: 30, minutes: 50, gf: .conservative)
        let deepEngine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)

        func deepestStop(_ engine: DecoEngine) -> Double {
            let firstStop = TissueModel.roundToStopInterval(
                engine.ceiling(atDepth: engine.tissues.maxDepth).depthMeters)
            return DeepStopCalculator.deepStops(
                tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
                firstDecoStopDepth: firstStop, settings: .standard)
                .filter(\.isLive).map(\.depth).max() ?? 0
        }

        XCTAssertGreaterThan(deepestStop(deepEngine), deepestStop(shallowEngine),
                             "Daha derin dalışta derin durak daha derinde olmalı")
    }

    // MARK: - Yuvarlama (round-off) etkisi

    func testRoundingIncreasesTissuePressure() {
        let model = TissueModel(nitrogenPressures: Array(repeating: 5.05, count: 16))
        let rounded = model.roundedOff(incrementPressure: 0.1)
        XCTAssertGreaterThan(rounded.leadingNitrogenPressure, model.leadingNitrogenPressure)
        XCTAssertEqual(rounded.nitrogenPressures[0], 5.1, accuracy: 0.001)
    }

    func testRoundingWithZeroIncrementIsNoOp() {
        let model = TissueModel(nitrogenPressures: Array(repeating: 5.05, count: 16))
        XCTAssertEqual(model.roundedOff(incrementPressure: 0).nitrogenPressures,
                       model.nitrogenPressures)
    }

    func testRoundingKeepsGradientFactors() {
        let model = TissueModel(nitrogenPressures: Array(repeating: 4.0, count: 16),
                                gradientFactors: .conservative)
        XCTAssertEqual(model.roundedOff(incrementPressure: 0.3).gradientFactors, .conservative)
    }

    func testIncrementPressureScalesWithInterval() {
        let narrow = DeepStopCalculator.Settings(isEnabled: true, interval: 1)
        let wide = DeepStopCalculator.Settings(isEnabled: true, interval: 6)
        XCTAssertGreaterThan(wide.incrementPressure(atDepth: 20),
                             narrow.incrementPressure(atDepth: 20))
    }

    func testLiveStopDetection() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let firstStop = TissueModel.roundToStopInterval(
            engine.ceiling(atDepth: 40).depthMeters)
        let stops = DeepStopCalculator.deepStops(
            tissues: engine.tissues, maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: firstStop, settings: .standard)

        for stop in stops {
            if stop.isLive {
                XCTAssertGreaterThan(stop.holdTime, 0, "Canlı durakta bekleme süresi olmalı")
            } else {
                XCTAssertEqual(stop.holdTime, 0)
            }
        }
    }

    func testHoldTimeAndCountHelpers() {
        let stops = [
            DeepStopCalculator.DeepStop(depth: 12, isLive: true, roundedPressure: 2.4, holdTime: 60),
            DeepStopCalculator.DeepStop(depth: 9, isLive: false, roundedPressure: 2.0, holdTime: 0)
        ]
        XCTAssertEqual(DeepStopCalculator.liveStopCount(stops), 1)
        XCTAssertEqual(DeepStopCalculator.totalHoldTime(stops), 60)
    }

    func testDeepStopLabel() {
        let stop = DeepStopCalculator.DeepStop(depth: 12, isLive: true,
                                               roundedPressure: 2.4, holdTime: 40)
        XCTAssertEqual(stop.label, "12 m")
    }

    func testSettingsValidation() {
        XCTAssertFalse(DeepStopCalculator.Settings(isEnabled: true, interval: 3,
                                                   firstStopDepth: 30, lastStopDepth: 20).hasRoom)
        XCTAssertTrue(DeepStopCalculator.Settings.standard.hasRoom)
        XCTAssertEqual(DeepStopCalculator.Settings(isEnabled: true, interval: 0).interval, 0.5,
                       "Çok küçük aralık sınırlanır")
    }

    // MARK: - Deko planı entegrasyonu

    func testPlanCarriesDeepStops() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 40,
                                     deepStopSettings: .standard)
        XCTAssertFalse(plan.deepStops.isEmpty)
        XCTAssertGreaterThanOrEqual(plan.liveDeepStopCount, 1)
        XCTAssertGreaterThan(plan.deepStopHoldTime, 0)
        XCTAssertTrue(plan.describe().contains("derin durak"))
    }

    func testPlanWithoutDeepStopsByDefault() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let plan = DecoStopPlan.make(from: engine, currentDepth: 40)
        XCTAssertTrue(plan.deepStops.isEmpty, "Varsayılan olarak kapalı olmalı")
        XCTAssertEqual(plan.liveDeepStopCount, 0)
        XCTAssertEqual(plan.deepStopHoldTime, 0)
    }

    func testDeepStopsDoNotChangeStandardStopTimes() {
        let engine = engineAtBottomGF(depth: 40, minutes: 60, gf: .conservative)
        let withoutDeep = DecoStopPlan.make(from: engine, currentDepth: 40)
        let withDeep = DecoStopPlan.make(from: engine, currentDepth: 40,
                                          deepStopSettings: .standard)
        // 3 m'lik zorunlu duraklar aynı kalmalı (derin duraklar ek bilgidir)
        XCTAssertEqual(withoutDeep.stops.map(\.depth), withDeep.stops.map(\.depth))
        XCTAssertEqual(withoutDeep.totalTime, withDeep.totalTime, accuracy: 0.001)
    }

    @MainActor
    func testControllerPlanUsesSettings() {
        let config = DiveConfiguration.nitrox(.ean32)
        let controller = DiveSessionController(configuration: config)
        controller.start()
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "t", segments: [
            .descent(to: 45, at: 15), .hover(at: 45, for: 70 * 60.0)
        ])).readings)

        XCTAssertTrue(controller.decoPlan().deepStops.isEmpty,
                      "Varsayılan ayarda derin durak kapalı")
        XCTAssertEqual(config.gases.first, .ean32)
    }
}