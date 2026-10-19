import XCTest
@testable import DiveCore

/// Dalış simülatörü: profil doğruluğu, hız sınırları, sıcaklık profili, determinizm.
final class DiveSimulatorTests: XCTestCase {

    // MARK: - Yardımcılar

    /// Üretilen okumaları 30 saniyelik ortalama hızlara indirger (gürültüyü eler).
    private func averageRate(_ readings: [DepthReading], window: Int = 15) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        var index = 0
        while index + window < readings.count {
            let slice = readings[index..<(index + window)]
            let dt = slice.last!.elapsed - slice.first!.elapsed
            guard dt > 0 else { index += window; continue }
            let rate = (slice.last!.depth - slice.first!.depth) / dt * 60
            result.append((slice.first!.elapsed, rate))
            index += window
        }
        return result
    }

    // MARK: - Profil yapısı

    func testScenarioDurationAndMaxDepth() {
        XCTAssertEqual(DiveScenario.beginner.maxDepth, 12)
        XCTAssertEqual(DiveScenario.recreational30m.maxDepth, 30)
        XCTAssertEqual(DiveScenario.deep45m.maxDepth, 45)

        // Not: `totalDuration` yalnızca sabit süreli segmentleri toplar;
        // iniş/çıkış süreleri mesafeye göre simülasyonda hesaplanır.
        let simulator = DiveSimulator(scenario: .recreational30m)
        let total = simulator.profileDuration
        XCTAssertGreaterThan(total, 26 * 60)
        XCTAssertLessThan(total, 32 * 60)
    }

    func testSegmentRangesCoverWholeProfile() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        XCTAssertEqual(simulator.segmentRanges.count, simulator.scenario.segments.count)
        XCTAssertEqual(simulator.segmentRanges.first?.startIndex, 0)
        XCTAssertEqual(simulator.segmentRanges.last?.endIndex, simulator.readings.count)

        // Aralıklar kesintisiz ve sürekli
        for index in 1..<simulator.segmentRanges.count {
            XCTAssertEqual(simulator.segmentRanges[index].startIndex,
                           simulator.segmentRanges[index - 1].endIndex)
        }
        XCTAssertEqual(simulator.range(of: .safetyStop)?.targetDepth, 5)
        XCTAssertNotNil(simulator.range(of: .descent))
        XCTAssertNil(simulator.range(of: .decoStop))
    }

    func testSimulatorProducesContinuousReadings() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        let readings = simulator.readings

        XCTAssertGreaterThan(readings.count, 1500)
        // 1 Hz örnekleme
        XCTAssertEqual(readings[0].elapsed, 0)
        XCTAssertEqual(readings[1].elapsed - readings[0].elapsed, 1, accuracy: 0.001)

        // Zaman artan, derinlik negatif olmayan
        for index in 1..<readings.count {
            XCTAssertGreaterThan(readings[index].elapsed, readings[index - 1].elapsed)
            XCTAssertGreaterThanOrEqual(readings[index].depth, 0)
        }
    }

    func testDescentReachesTargetDepthWithoutOvershoot() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        guard let descent = simulator.range(of: .descent) else { return XCTFail("iniş segmenti yok") }

        let descentReadings = descent.readings(in: simulator.readings)
        XCTAssertGreaterThanOrEqual(descentReadings.map(\.depth).max() ?? 0, 29)
        XCTAssertLessThanOrEqual(descentReadings.map(\.depth).max() ?? 0, 30.5)
        // Son metrelerde yumuşak yaklaşım
        XCTAssertEqual(descentReadings.map(\.depth).last ?? 0, 30, accuracy: 0.5)
        XCTAssertEqual(descentReadings.map(\.depth).first ?? 0, 0, accuracy: 1.5)
    }

    func testDescentRateRespectsScenarioLimit() {
        let simulator = DiveSimulator(scenario: .recreational30m)   // 15 m/dk iniş
        guard let descent = simulator.range(of: .descent) else { return XCTFail("iniş segmenti yok") }
        let descentReadings = descent.readings(in: simulator.readings)

        // 5 saniyelik ortalama ile ölç (ölçüm gürültüsünü eler)
        let window = 5
        var maxSpeed = 0.0
        var index = window
        while index < descentReadings.count {
            let dt = descentReadings[index].elapsed - descentReadings[index - window].elapsed
            if dt > 0 {
                maxSpeed = max(maxSpeed,
                               (descentReadings[index].depth - descentReadings[index - window].depth) / dt * 60)
            }
            index += window
        }
        XCTAssertLessThan(maxSpeed, 15.5, "15 m/dk iniş sınırı aşılmamalı")
        XCTAssertGreaterThan(maxSpeed, 11, "Senaryoda gerçek bir iniş olmalı")
    }

    func testSafeAscentStaysWithinLimit() {
        let simulator = DiveSimulator(scenario: .recreational30m)   // 9 m/dk çıkış
        var peak = 0.0
        for range in simulator.ranges(of: .ascent) {
            let slice = range.readings(in: simulator.readings)
            for index in 1..<slice.count {
                let dt = slice[index].elapsed - slice[index - 1].elapsed
                if dt > 0 {
                    let rate = (slice[index - 1].depth - slice[index].depth) / dt * 60
                    peak = max(peak, rate)
                }
            }
        }
        XCTAssertGreaterThan(peak, 5, "Gerçek bir çıkış olmalı")
        XCTAssertLessThan(peak, 10.5, "9 m/dk senaryosu 10 m/dk sınırını aşmamalı")
    }

    func testFastAscentScenarioViolatesLimit() {
        let simulator = DiveSimulator(scenario: .fastAscentViolation)   // 18 m/dk
        guard let ascent = simulator.ranges(of: .ascent).first else {
            return XCTFail("çıkış segmenti yok")
        }
        let slice = ascent.readings(in: simulator.readings)

        var peak = 0.0
        for index in 1..<slice.count {
            let dt = slice[index].elapsed - slice[index - 1].elapsed
            if dt > 0 {
                peak = max(peak, (slice[index - 1].depth - slice[index].depth) / dt * 60)
            }
        }
        XCTAssertGreaterThan(peak, 14, "18 m/dk senaryosu hızlı çıkış üretmeli")
        XCTAssertGreaterThan(peak, DiveSafetyLimits.maximumAscentRate)
    }

    func testSafetyStopSegmentHoldsDepth() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        guard let stop = simulator.range(of: .safetyStop) else { return XCTFail("dura�� segmenti yok") }
        let stopReadings = stop.readings(in: simulator.readings)

        XCTAssertEqual(stopReadings.count, 180, "3 dakikalık emniyet durağı")
        // İlk saniyeler yerleşme (yumuşak yaklaşım) — ondan sonra 5 m'de sabit
        for reading in stopReadings.dropFirst(30) {
            XCTAssertEqual(reading.depth, 5, accuracy: 0.2,
                           "Emniyet durağında derinlik 5 m civarında kalmalı")
        }
    }

    func testProfileReturnsToSurface() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        XCTAssertLessThanOrEqual(simulator.readings.last?.depth ?? 99, 0.5,
                                 "Profil yüzeye ulaşmalı")
    }

    // MARK: - Sıcaklık

    func testTemperatureProfileFollowsThermocline() {
        let simulator = DiveSimulator(scenario: .recreational30m)   // 26 yüzey / 20 dip / termoklin 14 m
        guard let descent = simulator.range(of: .descent) else { return XCTFail("yok") }
        let descentReadings = descent.readings(in: simulator.readings)
        let surface = descentReadings.first?.temperature ?? 0
        let mid = descentReadings[descentReadings.count / 2].temperature ?? 0
        let bottom = descentReadings.last?.temperature ?? 0

        XCTAssertGreaterThan(surface, mid)
        XCTAssertGreaterThan(mid, bottom)
        XCTAssertGreaterThanOrEqual(surface, 25.5)
        XCTAssertGreaterThanOrEqual(bottom, 19.5)
        XCTAssertLessThanOrEqual(bottom, 20.5)
    }

    func testTemperatureFunctionIsMonotonic() {
        var previous = DiveSimulator.temperature(at: 0, surface: 26, bottom: 19, thermocline: 12)
        for depth in stride(from: 0.5, through: 40, by: 0.5) {
            let value = DiveSimulator.temperature(at: depth, surface: 26, bottom: 19, thermocline: 12)
            XCTAssertLessThanOrEqual(value, previous + 1e-9, "\(depth) m'de sıcaklık artmamalı")
            previous = value
        }
    }

    // MARK: - Basınç

    func testAmbientPressureMatchesDepth() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        for reading in simulator.readings.prefix(300) {
            let expected = DivePhysics.ambientPressure(depthMeters: reading.depth)
            XCTAssertEqual(reading.ambientPressure, expected, accuracy: 1e-6)
        }
    }

    func testReadingsAreMarkedSimulated() {
        let simulator = DiveSimulator(scenario: .beginner)
        XCTAssertTrue(simulator.readings.allSatisfy(\.isSimulated))
        // İlk okuma yüzeydedir
        XCTAssertTrue(simulator.readings[0].isAtSurface)
        XCTAssertEqual(simulator.readings[0].temperature ?? 0,
                       simulator.scenario.surfaceTemperature, accuracy: 0.5)
    }

    // MARK: - Determinizm ve gürültü

    func testSameSeedProducesIdenticalProfile() {
        let first = DiveSimulator(scenario: .recreational30m)
        let second = DiveSimulator(scenario: .recreational30m)
        XCTAssertEqual(first.readings.count, second.readings.count)
        for (a, b) in zip(first.readings, second.readings) {
            XCTAssertEqual(a.depth, b.depth, accuracy: 1e-12)
        }
    }

    func testDifferentSeedProducesDifferentNoise() {
        var scenario = DiveScenario.recreational30m
        scenario.seed = 99
        let first = DiveSimulator(scenario: .recreational30m)
        let second = DiveSimulator(scenario: scenario)

        let differences = zip(first.readings, second.readings)
            .filter { abs($0.depth - $1.depth) > 1e-9 }
        XCTAssertFalse(differences.isEmpty, "Farklı tohum farklı gürültü üretmeli")
    }

    func testNoiseIsSmallAndRealistic() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        guard let hover = simulator.range(of: .hover) else { return XCTFail("dibte bekleme segmenti yok") }
        let bottomReadings = hover.readings(in: simulator.readings)
            .dropFirst(30).map(\.depth)   // ilk saniyeler yerleşme
        let minDepth = bottomReadings.min() ?? 0
        let maxDepth = bottomReadings.max() ?? 0
        XCTAssertLessThan(maxDepth - minDepth, 0.5, "Dalış filigranı abartılı olmamalı")
        XCTAssertGreaterThan(maxDepth - minDepth, 0.02, "Gerçekçi bir dalış salınımı olmalı")
    }

    // MARK: - Canlı erişim

    func testCursorBasedIteration() {
        var simulator = DiveSimulator(scenario: .beginner)
        XCTAssertEqual(simulator.cursor, 0)
        XCTAssertNotNil(simulator.next())
        XCTAssertEqual(simulator.cursor, 1)
        XCTAssertFalse(simulator.isFinished)

        while simulator.next() != nil {}
        XCTAssertTrue(simulator.isFinished)
        XCTAssertNil(simulator.next())

        simulator.reset()
        XCTAssertEqual(simulator.cursor, 0)
        XCTAssertNotNil(simulator.next())
    }

    func testApplyScenarioRegenerates() {
        var simulator = DiveSimulator(scenario: .beginner)
        let before = simulator.readings.count
        simulator.apply(scenario: .deep45m)
        XCTAssertNotEqual(simulator.readings.count, before)
        XCTAssertEqual(simulator.cursor, 0)
        XCTAssertEqual(DiveSimulator(scenario: .deep45m).readingCount, simulator.readings.count)
    }

    func testReadingLookupByElapsed() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        XCTAssertEqual(simulator.reading(atElapsed: 0)?.elapsed, 0)
        XCTAssertEqual(simulator.reading(atElapsed: 60)?.elapsed, 60)
        XCTAssertEqual(simulator.profileDuration,
                       Double(simulator.readings.count) * simulator.scenario.sampleInterval,
                       accuracy: 0.001)
        XCTAssertNil(simulator.reading(atElapsed: -5))
        XCTAssertNil(simulator.reading(atElapsed: 10_000_000))
    }

    func testFilterByTimeRange() {
        let simulator = DiveSimulator(scenario: .recreational30m)
        let slice = simulator.readings(from: 100, to: 200)
        XCTAssertEqual(slice.count, 101)
        XCTAssertTrue(slice.allSatisfy { $0.elapsed >= 100 && $0.elapsed <= 200 })
    }

    // MARK: - Adım yardımcıları

    func testStepDepthReachesTargetWithoutOvershoot() {
        var depth = 0.0
        let segment = DiveSegment(kind: .descent, targetDepth: 20, duration: 100)
        for step in 0..<100 {
            depth = DiveSimulator.stepDepth(current: depth, target: segment.targetDepth,
                                            segment: segment,
                                            progress: Double(step) / 100.0,
                                            stepDuration: 1)
            XCTAssertLessThanOrEqual(depth, 20)
        }
        XCTAssertEqual(depth, 20, accuracy: 0.6)
    }

    func testStepDepthStopsAtTargetWhenReached() {
        let segment = DiveSegment(kind: .hover, targetDepth: 10, duration: 60)
        XCTAssertEqual(DiveSimulator.stepDepth(current: 10, target: 10,
                                               segment: segment, progress: 0.5,
                                               stepDuration: 1), 10)
    }

    func testStepDepthRespectsRateLimit() {
        // 10 m/dk hız sınırı: saniyede en fazla 10/60 = 0.1667 m
        let segment = DiveSegment(kind: .ascent, targetDepth: 0, duration: 100,
                                  ascentRate: 10)
        var depth = 30.0
        var maxStep = 0.0
        for step in 0..<100 {
            let before = depth
            depth = DiveSimulator.stepDepth(current: depth, target: 0, segment: segment,
                                            progress: Double(step) / 100.0, stepDuration: 1)
            maxStep = max(maxStep, abs(before - depth))
        }
        XCTAssertLessThanOrEqual(maxStep, 10.0 / 60.0 + 1e-9,
                                 "Adım başına hız sınırı aşınmamalı")
    }

    func testSeededGeneratorIsDeterministicAndBounded() {
        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        for _ in 0..<100 {
            let value = first.next()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
            XCTAssertEqual(value, second.next())
        }
    }

    // MARK: - Senaryo kısayolları

    func testSegmentFactories() {
        let descent = DiveSegment.descent(to: 30, at: 15)
        XCTAssertEqual(descent.kind, .descent)
        XCTAssertEqual(descent.duration, 120, accuracy: 0.001)

        // Çıkışta süre otomatik hesaplanır (mesafeye göre)
        let ascent = DiveSegment.ascent(to: 0, at: 9)
        XCTAssertEqual(ascent.kind, .ascent)
        XCTAssertEqual(ascent.duration, 0, accuracy: 0.001)

        let hover = DiveSegment.hover(at: 18, for: 600)
        XCTAssertEqual(hover.duration, 600)

        let stop = DiveSegment.safetyStop()
        XCTAssertEqual(stop.kind, .safetyStop)
        XCTAssertEqual(stop.targetDepth, 3)
        XCTAssertEqual(stop.duration, 180)
    }
}