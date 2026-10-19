import XCTest
@testable import DiveCore

/// `DepthReading` ve sensör arayüzü (mock dahil).
@MainActor
final class DepthSensorTests: XCTestCase {

    // MARK: - DepthReading

    func testAmbientPressureIsDerivedFromDepth() {
        let reading = DepthReading(depth: 30, timestamp: Date(), elapsed: 0)
        XCTAssertEqual(reading.ambientPressure, 4.0, accuracy: 1e-9)
    }

    func testExplicitPressureOverridesDerivedValue() {
        let reading = DepthReading(depth: 30, ambientPressure: 4.2,
                                   timestamp: Date(), elapsed: 0)
        XCTAssertEqual(reading.ambientPressure, 4.2)
    }

    func testFreshWaterConversion() {
        let reading = DepthReading(depth: 30, timestamp: Date(), elapsed: 0, water: .fresh)
        XCTAssertEqual(reading.ambientPressure, 1 + 30 / 10.33, accuracy: 1e-9)
    }

    func testSurfaceAndUnderwaterFlags() {
        XCTAssertTrue(DepthReading(depth: 0, timestamp: Date(), elapsed: 0).isAtSurface)
        XCTAssertTrue(DepthReading(depth: 0.2, timestamp: Date(), elapsed: 0).isAtSurface)
        XCTAssertFalse(DepthReading(depth: 0.4, timestamp: Date(), elapsed: 0).isAtSurface)
        XCTAssertTrue(DepthReading(depth: 12, timestamp: Date(), elapsed: 0).isUnderwater)
    }

    func testPressureDelta() {
        let reading = DepthReading(depth: 30, timestamp: Date(), elapsed: 0)
        XCTAssertEqual(reading.pressureDelta, 3.0, accuracy: 1e-9)
    }

    func testVerticalSpeedBetweenReadings() {
        let first = DepthReading(depth: 10, timestamp: Date(timeIntervalSince1970: 0), elapsed: 0)
        let second = DepthReading(depth: 12, timestamp: Date(timeIntervalSince1970: 30), elapsed: 30)
        // 2 m derinlik artışı / 30 sn = 4 m/dk AŞAĞI (negatif)
        XCTAssertEqual(second.verticalSpeed(since: first), -4.0, accuracy: 1e-9)
        // Yukarı giderken pozitif: 10 m -> 8 m / 30 sn = 4 m/dk
        let third = DepthReading(depth: 8, timestamp: Date(timeIntervalSince1970: 60), elapsed: 60)
        XCTAssertEqual(third.verticalSpeed(since: second), 8.0, accuracy: 1e-9)
        XCTAssertEqual(second.depthChange(since: first), 2.0)
    }

    func testVerticalSpeedIsZeroForSameTimestamp() {
        let first = DepthReading(depth: 10, timestamp: Date(), elapsed: 0)
        let second = DepthReading(depth: 15, timestamp: Date(), elapsed: 0)
        XCTAssertEqual(second.verticalSpeed(since: first), 0)
    }

    func testReadingCodableRoundTrip() throws {
        let reading = DepthReading(depth: 18.5, timestamp: Date(timeIntervalSince1970: 1000),
                                   elapsed: 600, temperature: 19.5, isSimulated: true)
        let data = try JSONEncoder().encode(reading)
        let decoded = try JSONDecoder().decode(DepthReading.self, from: data)
        XCTAssertEqual(decoded.depth, reading.depth)
        XCTAssertEqual(decoded.elapsed, reading.elapsed)
        XCTAssertEqual(decoded.temperature ?? 0, reading.temperature ?? 0)
        XCTAssertTrue(decoded.isSimulated)
    }

    func testSampleRateHelpers() {
        XCTAssertEqual(DepthSampleRate.interval(for: DepthSampleRate.live), 1.0)
        XCTAssertEqual(DepthSampleRate.interval(for: DepthSampleRate.high), 0.25)
        XCTAssertEqual(DepthSampleRate.interval(for: 0), 1.0)
    }

    // MARK: - MockDepthSensor

    func testMockSensorDeliversQueuedReadings() {
        let sensor = MockDepthSensor()
        var received: [Double] = []
        sensor.onReading = { received.append($0.depth) }

        try? sensor.start()
        XCTAssertTrue(sensor.isRunning)

        sensor.enqueue([DepthReading(depth: 1, timestamp: Date(), elapsed: 1),
                        DepthReading(depth: 2, timestamp: Date(), elapsed: 2)])
        sensor.deliverAll()

        XCTAssertEqual(received, [1, 2])
        XCTAssertFalse(sensor.deliverNext())
    }

    func testMockSensorStopsDeliveringAfterStop() {
        let sensor = MockDepthSensor()
        var count = 0
        sensor.onReading = { _ in count += 1 }

        try? sensor.start()
        sensor.enqueue([DepthReading(depth: 5, timestamp: Date(), elapsed: 1)])
        sensor.deliverAll()
        XCTAssertEqual(count, 1)

        sensor.stop()
        XCTAssertFalse(sensor.isRunning)
        sensor.deliverAll()
        XCTAssertEqual(count, 1)
    }

    func testMockSensorIsIdempotentOnStart() throws {
        let sensor = MockDepthSensor()
        try sensor.start()
        try sensor.start()
        XCTAssertEqual(sensor.startCount, 1)
    }

    func testMockSensorReportsErrors() {
        let sensor = MockDepthSensor()
        var error: DepthSensorError?
        sensor.onError = { error = $0 }
        sensor.fail(.permissionDenied)
        XCTAssertEqual(error, .permissionDenied)
    }

    func testMockSensorGenerator() throws {
        var counter = 0
        let sensor = MockDepthSensor(generator: {
            counter += 1
            return DepthReading(depth: Double(counter), timestamp: Date(), elapsed: Double(counter))
        })
        var depths: [Double] = []
        sensor.onReading = { depths.append($0.depth) }

        try sensor.start()
        sensor.tick()
        sensor.tick()

        XCTAssertEqual(depths, [1, 2])
    }

    /// Simülatör + mock sensör + oturum denetleyicisi birleşimi:
    /// gerçek zamanlı taklit akışı.
    func testSimulatorDrivesLiveSession() throws {
        var simulator = DiveSimulator(scenario: .beginner)
        let sensor = MockDepthSensor(generator: { simulator.next() })
        let controller = DiveSessionController(configuration: .recreational)

        sensor.onReading = { controller.ingest($0) }
        try sensor.start()
        controller.start(at: simulator.startDate)

        // 120 saniyelik canlı akış
        for _ in 0..<120 { sensor.tick() }

        XCTAssertEqual(controller.state.diveTime, 120, accuracy: 1)
        XCTAssertGreaterThan(controller.state.currentDepth, 1)
    }
}