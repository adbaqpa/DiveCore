import XCTest
@testable import DiveCore

/// Yüzey aralığı takibi: GF99 düşüşü, desatürasyon, uçuş yasağı.
final class SurfaceIntervalManagerTests: XCTestCase {

    private let end = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcı

    /// Belirli bir dalışın son dokularını üreten motor.
    private func engineAfter(depth: Double, minutes: Double, gas: GasMix = .air) -> DecoEngine {
        let scenario = DiveScenario(name: "t", segments: [
            .descent(to: depth, at: 15), .hover(at: depth, for: minutes * 60)
        ])
        var engine = DecoEngine(gradientFactors: .conservative, gases: [gas], gasCylinderIndex: 0)
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: gas)
        }
        return engine
    }

    private func managerAfterDive(depth: Double = 30, minutes: Double = 30,
                                  gas: GasMix = .air) -> SurfaceIntervalManager {
        var manager = SurfaceIntervalManager(resolution: 60)
        let engine = engineAfter(depth: depth, minutes: minutes, gas: gas)
        manager.recordDiveEnd(at: end, tissues: engine.tissues, gas: gas)
        return manager
    }

    // MARK: - Temel

    func testNoDiveHasEmptyStatus() {
        let manager = SurfaceIntervalManager()
        let status = manager.status(at: end)
        XCTAssertEqual(status.elapsed, 0)
        XCTAssertEqual(status.gf99, 0)
        XCTAssertTrue(status.isNoFlyCleared)
        XCTAssertTrue(status.recommendation.contains("Henüz"))
    }

    func testRecordingDiveSetsImmediateNoFly() {
        let manager = managerAfterDive()
        let status = manager.status(at: end)
        XCTAssertGreaterThan(status.gf99, 50)
        XCTAssertGreaterThan(status.noFlyRemaining, 0)
        XCTAssertFalse(status.isNoFlyCleared)
    }

    func testGf99DecreasesOverTime() {
        var manager = managerAfterDive()
        let start = manager.status(at: end).gf99
        manager.update(to: end.addingTimeInterval(4 * 3600))
        let later = manager.status(at: end.addingTimeInterval(4 * 3600))

        XCTAssertLessThan(later.gf99, start)
        XCTAssertGreaterThan(later.elapsed, 0)
    }

    func testElapsedIsMonotonic() {
        var manager = managerAfterDive()
        let one = manager.update(to: end.addingTimeInterval(1800))
        let two = manager.update(to: end.addingTimeInterval(7200))
        XCTAssertGreaterThan(two.elapsed, one.elapsed)
        XCTAssertEqual(two.elapsed, 7200, accuracy: 60)
    }

    func testUpdateIsIdempotent() {
        var manager = managerAfterDive()
        let first = manager.update(to: end.addingTimeInterval(3600))
        let second = manager.update(to: end.addingTimeInterval(3600))
        XCTAssertEqual(first.elapsed, second.elapsed, accuracy: 1)
        XCTAssertEqual(first.gf99, second.gf99, accuracy: 0.001)
    }

    func testUpdateBeforeEndIsClamped() {
        var manager = managerAfterDive()
        let status = manager.update(to: end.addingTimeInterval(-500))
        XCTAssertEqual(status.elapsed, 0)
    }

    // MARK: - Uçuş yasağı

    func testNoFlyClearsAfterSufficientInterval() {
        var manager = SurfaceIntervalManager(noFlyBufferMinutes: 60, resolution: 60)
        manager.recordDiveEnd(at: end, tissues: engineAfter(depth: 20, minutes: 20).tissues,
                              gas: .air)
        // Sığ dalışta kısa uçuş yasağı beklenir
        let status = manager.update(to: end.addingTimeInterval(12 * 3600))
        XCTAssertTrue(status.isNoFlyCleared)
        XCTAssertEqual(status.noFlyRemaining, 0)
    }

    func testDeepDiveHasLongerNoFly() {
        let shallow = managerAfterDive(depth: 18, minutes: 15)
        let deep = managerAfterDive(depth: 45, minutes: 60)
        XCTAssertGreaterThan(deep.status(at: end).noFlyRemaining,
                             shallow.status(at: end).noFlyRemaining)
    }

    func testNoFlyIsRoundedToFifteenMinutes() {
        let manager = managerAfterDive()
        let remaining = manager.status(at: end).noFlyRemaining
        XCTAssertEqual(remaining.truncatingRemainder(dividingBy: 900), 0, accuracy: 1)
    }

    func testDesaturationFinishesBeforeNoFly() {
        let manager = managerAfterDive()
        let status = manager.status(at: end)
        XCTAssertLessThanOrEqual(status.desaturationRemaining, status.noFlyRemaining)
    }

    func testRecommendationChangesWhenCleared() {
        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: end, tissues: engineAfter(depth: 15, minutes: 10).tissues,
                              gas: .air)
        let early = manager.status(at: end)
        XCTAssertTrue(early.recommendation.contains("GF"))

        let late = manager.update(to: end.addingTimeInterval(10 * 3600))
        XCTAssertTrue(late.isNoFlyCleared)
        XCTAssertTrue(late.recommendation.contains("temiz") || late.recommendation.contains("Serbest"))
    }

    // MARK: - Dalış sonu yükü

    @MainActor
    func testRecordFromLogEntry() {
        var manager = SurfaceIntervalManager(resolution: 60)
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: end)
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        let log = controller.end(at: end.addingTimeInterval(1800))!

        manager.recordDiveEnd(at: end.addingTimeInterval(1800), log: log)
        let status = manager.status(at: end.addingTimeInterval(1800))
        XCTAssertGreaterThan(status.gf99, 50, "Dokular yüklenmiş olmalı")
        XCTAssertGreaterThan(status.noFlyRemaining, 0)
    }

    func testDeeperDiveStartsWithHigherGf99() {
        let shallow = managerAfterDive(depth: 12, minutes: 10).status(at: end)
        let deep = managerAfterDive(depth: 40, minutes: 40).status(at: end)
        XCTAssertGreaterThan(deep.gf99, shallow.gf99)
    }

    // MARK: - Bakım

    func testResetClearsEverything() {
        var manager = managerAfterDive()
        manager.reset()
        let status = manager.status(at: end)
        XCTAssertNil(manager.lastDiveEnd)
        XCTAssertEqual(status.gf99, 0)
        XCTAssertTrue(status.isNoFlyCleared)
    }

    func testStatusFormatting() {
        let status = managerAfterDive().status(at: end.addingTimeInterval(5400))
        XCTAssertTrue(status.elapsedText.contains("1s"))
        XCTAssertTrue(status.gf99Text.hasPrefix("%"))
    }

    // MARK: - Kodlama

    func testStatusCodableRoundTrip() throws {
        let status = managerAfterDive().status(at: end)
        let data = try JSONEncoder().encode(status)
        XCTAssertEqual(try JSONDecoder().decode(SurfaceIntervalStatus.self, from: data), status)
    }

    // MARK: - Entegrasyon

    @MainActor
    func testControllerFlowFeedsSurfaceInterval() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: end)
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        let log = controller.end(at: end.addingTimeInterval(1800))!

        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: end.addingTimeInterval(1800), log: log)
        let status = manager.update(to: end.addingTimeInterval(1800 + 2 * 3600))

        XCTAssertGreaterThan(status.elapsed, 2 * 3600 - 60)
        XCTAssertLessThan(status.gf99, log.maxGF99)
    }
}