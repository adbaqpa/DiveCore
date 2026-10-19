import XCTest
@testable import DiveCore

/// Derinlik ↔ basınç dönüşümleri ve temel fizik sabitleri.
final class DivePhysicsTests: XCTestCase {

    func testSurfacePressureIsOneBar() {
        XCTAssertEqual(DivePhysics.ambientPressure(depthMeters: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(DivePhysics.surfacePressure, 1.0)
    }

    func testSaltWaterTenMetersPerBar() {
        // Deniz suyunda 10 m ≈ 1 bar
        XCTAssertEqual(DivePhysics.ambientPressure(depthMeters: 10, water: .salt), 2.0, accuracy: 1e-9)
        XCTAssertEqual(DivePhysics.ambientPressure(depthMeters: 30, water: .salt), 4.0, accuracy: 1e-9)
    }

    func testDepthPressureRoundTrip() {
        for depth in stride(from: 0.0, through: 100.0, by: 0.5) {
            let pressure = DivePhysics.ambientPressure(depthMeters: depth)
            XCTAssertEqual(DivePhysics.depthMeters(ambientPressure: pressure), depth, accuracy: 1e-9,
                           "Derinlik \(depth) için gidiş-dönüş bozuk")
        }
    }

    func testFreshWaterIsDenserThanSalt() {
        // Tatlı suda aynı basınç için daha derin olur
        let salt = DivePhysics.depthMeters(ambientPressure: 4.0, water: .salt)
        let fresh = DivePhysics.depthMeters(ambientPressure: 4.0, water: .fresh)
        XCTAssertEqual(salt, 30, accuracy: 1e-9)
        XCTAssertEqual(fresh, 30.99, accuracy: 0.01)
        XCTAssertGreaterThan(fresh, salt)
    }

    func testNegativeDepthNeverReturnsNegativePressure() {
        // Yüzeyin üstü (ör. dalış başlamadan 1 m "yukarı") → 1.0 bar
        XCTAssertEqual(DivePhysics.ambientPressure(depthMeters: -1), 1.0, accuracy: 1e-9)
    }

    func testAlveolarNitrogenIncludesWaterVaporCorrection() {
        // Havada: (1.0 - 0.0627) * 0.79 = 0.7404 bar
        let n2 = DivePhysics.alveolarNitrogenPressure(ambientPressure: 1.0, nitrogenFraction: 0.79)
        XCTAssertEqual(n2, 0.7404, accuracy: 1e-4)
    }

    func testAlveolarNitrogenScalesWithDepth() {
        // 30 m havada: (4.0 - 0.0627) * 0.79
        let n2 = DivePhysics.alveolarNitrogenPressure(ambientPressure: 4.0, nitrogenFraction: 0.79)
        XCTAssertEqual(n2, 3.1105, accuracy: 1e-3)
    }

    func testPartialPressureNeverNegative() {
        let pp = DivePhysics.partialPressure(ambientPressure: 1.0, fraction: 0.0)
        XCTAssertEqual(pp, 0.0)
    }

    func testPercentFractionConversions() {
        XCTAssertEqual(DivePhysics.fraction(fromPercent: 32.0), 0.32, accuracy: 1e-12)
        XCTAssertEqual(DivePhysics.percent(fromFraction: 0.32), 32.0, accuracy: 1e-12)
    }
}