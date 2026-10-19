import XCTest
@testable import DiveCore

/// Gaz karışımı modeli ve MOD/PO2 hesapları.
final class GasMixTests: XCTestCase {

    // MARK: Yapı

    func testNitrogenIsRemainingFraction() {
        let ean32 = GasMix(oxygenFraction: 0.32)
        XCTAssertEqual(ean32.nitrogenFraction, 0.68, accuracy: 1e-12)
        XCTAssertEqual(ean32.oxygenFraction + ean32.nitrogenFraction, 1.0, accuracy: 1e-12)
    }

    func testPercentInitializerConvertsToFraction() {
        let gas = GasMix(oxygenPercent: 36)
        XCTAssertEqual(gas.oxygenFraction, 0.36, accuracy: 1e-12)
        XCTAssertEqual(gas.label, "EAN36")
    }

    func testOxygenIsClampedToSafeRange() {
        // %100'den fazla O2 kabul edilmez
        let gas = GasMix(oxygenPercent: 120)
        XCTAssertEqual(gas.oxygenFraction, 1.0, accuracy: 1e-12)

        // %21'in altı (hipoksi) kabul edilmez
        let hypoxic = GasMix(oxygenPercent: 10)
        XCTAssertEqual(hypoxic.oxygenFraction, 0.21, accuracy: 1e-12)
    }

    func testHeliumCannotOverflowRemainder() {
        let gas = GasMix(oxygenFraction: 0.21, heliumFraction: 0.9)
        XCTAssertEqual(gas.heliumFraction, 0.79, accuracy: 1e-12)
        XCTAssertEqual(gas.oxygenFraction + gas.heliumFraction + gas.nitrogenFraction, 1.0, accuracy: 1e-12)
    }

    func testLabelParsing() {
        XCTAssertEqual(GasMix(label: "EAN32")?.oxygenFraction ?? 0, 0.32, accuracy: 1e-12)
        XCTAssertEqual(GasMix(label: "ean36")?.oxygenFraction ?? 0, 0.36, accuracy: 1e-12)
        XCTAssertNil(GasMix(label: "Air"))
        XCTAssertNil(GasMix(label: "EAN15"))   // minimum %21 altı reddedilir
    }

    func testCommonGasLabels() {
        XCTAssertEqual(GasMix.air.label, "Air")
        XCTAssertEqual(GasMix.ean32.label, "EAN32")
        XCTAssertEqual(GasMix.oxygen.label, "O₂")
        XCTAssertEqual(GasMix(oxygenFraction: 0.18 + 0.13, heliumFraction: 0.69).label, "O31/He69")
    }

    // MARK: PO2 / MOD

    func testOxygenPartialPressureAtDepth() {
        // Havada 30 m'de PO2 = (4.0 - 0.0627) * 0.21 = 0.8267
        let po2 = GasMix.air.oxygenPartialPressure(atDepth: 30)
        XCTAssertEqual(po2, 0.8267, accuracy: 1e-3)
    }

    func testMaximumOperatingDepthForAir() {
        // Havada MOD (PO2 1.4) = ((0.0627 + 1.4/0.21) - 1) * 10 = 57.3 m
        let mod = GasMix.air.maximumOperatingDepth()
        XCTAssertEqual(mod, 57.3, accuracy: 0.2)
    }

    func testNitroxHasShallowerModThanAir() {
        let air = GasMix.air.maximumOperatingDepth()
        let ean36 = GasMix.ean36.maximumOperatingDepth()
        let o2 = GasMix.oxygen.maximumOperatingDepth()

        XCTAssertLessThan(ean36, air)
        XCTAssertLessThan(o2, ean36)
        XCTAssertEqual(o2, 4.6, accuracy: 0.1) // saf O2 için PO2 1.4 sınırında ~4.6 m
    }

    func testModMatchesItsOwnPo2() {
        // Tanım gereği MOD derinliğinde PO2 tam olarak maxPO2 olmalı
        for gas in [GasMix.air, .ean32, .ean36, .oxygen] {
            let mod = gas.maximumOperatingDepth()
            let po2 = gas.oxygenPartialPressure(atDepth: mod)
            XCTAssertEqual(po2, 1.4, accuracy: 1e-6, "\(gas.label) MOD doğrulaması")
        }
    }

    func testCodableRoundTrip() throws {
        let gas = GasMix.ean36
        let data = try JSONEncoder().encode(gas)
        let decoded = try JSONDecoder().decode(GasMix.self, from: data)
        XCTAssertEqual(decoded, gas)
    }
}