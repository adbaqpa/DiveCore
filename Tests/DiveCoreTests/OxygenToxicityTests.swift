import XCTest
@testable import DiveCore

/// CNS ve OTU hesapları.
final class OxygenToxicityTests: XCTestCase {

    // MARK: CNS tablosu

    func testCnsLimitsFollowNoaaTable() {
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 0.55), 720)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 0.65), 570)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 0.75), 450)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 0.95), 300)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 1.05), 240)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 1.25), 180)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 1.45), 120)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 1.55), 45)
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 1.61), 1)
    }

    func testCnsLimitBelowHalfBarIsNotAccumulated() {
        XCTAssertEqual(OxygenToxicity.cnsLimitMinutes(po2: 0.4), 720)

        var tox = OxygenToxicity()
        tox.accumulate(po2: 0.4, duration: 3600)
        XCTAssertEqual(tox.cnsPercent, 0)
    }

    func testCnsAccumulatesLinearlyWithinLimit() {
        var tox = OxygenToxicity()
        // PO2 1.0 bar altında tek doz limiti 240 dk
        tox.accumulate(po2: 1.0, duration: 60)
        XCTAssertEqual(tox.cnsPercent, 100.0 / 240, accuracy: 1e-9)

        tox.accumulate(po2: 1.0, duration: 60 * 239)
        XCTAssertEqual(tox.cnsPercent, 100, accuracy: 0.001)
    }

    func testHigherPo2AccumulatesFaster() {
        var low = OxygenToxicity()
        var high = OxygenToxicity()
        low.accumulate(po2: 0.9, duration: 600)
        high.accumulate(po2: 1.3, duration: 600)
        XCTAssertGreaterThan(high.cnsPercent, low.cnsPercent)
    }

    func testCnsWarningAtEightyPercent() {
        var tox = OxygenToxicity()
        tox.accumulate(po2: 1.0, duration: 60 * 192)   // %80
        XCTAssertEqual(tox.cnsPercent, 80, accuracy: 0.01)
        XCTAssertEqual(tox.warningLevel(currentPO2: 1.0), .danger)
    }

    // MARK: OTU

    func testOtuIsZeroBelowHalfBar() {
        XCTAssertEqual(OxygenToxicity.otuPerMinute(po2: 0.4), 0)
        XCTAssertEqual(OxygenToxicity.otuPerMinute(po2: 0.5), 0)
    }

    func testOtuFormulaMatchesNoaa() {
        // PO2 1.6 bar -> 0.5 / (1.1)^0.83 = 0.4620 OTU/dk
        let rate = OxygenToxicity.otuPerMinute(po2: 1.6)
        XCTAssertEqual(rate, 0.4620, accuracy: 0.002)

        // PO2 1.0 bar -> 0.5 / (0.5)^0.83 = 0.8888 OTU/dk
        XCTAssertEqual(OxygenToxicity.otuPerMinute(po2: 1.0), 0.8888, accuracy: 0.002)
    }

    func testOtuAccumulatesLinearly() {
        var tox = OxygenToxicity()
        let rate = OxygenToxicity.otuPerMinute(po2: 1.6)
        tox.accumulate(po2: 1.6, duration: 60 * 10)
        XCTAssertEqual(tox.otuUnits, rate * 10, accuracy: 1e-9)
    }

    func testOtuPercentOfDailyLimit() {
        var tox = OxygenToxicity(dailyOTULimit: 80)
        // 80 OTU = günlük limitin %100'ü
        let minutes = 80 / OxygenToxicity.otuPerMinute(po2: 1.6)
        tox.accumulate(po2: 1.6, duration: minutes * 60)
        XCTAssertEqual(tox.otuUnits, 80, accuracy: 0.01)
        XCTAssertEqual(tox.otuPercent, 100, accuracy: 0.05)
    }

    func testCustomDailyLimitScalesPercent() {
        var tox = OxygenToxicity(dailyOTULimit: 40)
        let minutes = 40 / OxygenToxicity.otuPerMinute(po2: 1.6)
        tox.accumulate(po2: 1.6, duration: minutes * 60)
        XCTAssertEqual(tox.otuPercent, 100, accuracy: 0.1)
    }

    // MARK: Uyarı seviyeleri ve sıfırlama

    func testWarningLevels() {
        var tox = OxygenToxicity()
        XCTAssertEqual(tox.warningLevel(currentPO2: 0.32), .none)

        tox.accumulate(po2: 1.35, duration: 60 * 5)   // PO2 = 1.4 sınırına yakın
        // Birikimler düşük ama PO2 limitin %90'ının üzerinde -> dikkat
        XCTAssertEqual(tox.warningLevel(currentPO2: 1.35), .caution)
    }

    func testPo2AboveMaxIsDanger() {
        var tox = OxygenToxicity()
        tox.accumulate(po2: 1.5, duration: 60)
        XCTAssertEqual(tox.warningLevel(currentPO2: 1.5), .danger)
        XCTAssertTrue(tox.didExceedLimits)
    }

    func testResetClearsAccumulators() {
        var tox = OxygenToxicity()
        tox.accumulate(po2: 1.3, duration: 600)
        tox.reset()
        XCTAssertEqual(tox.cnsPercent, 0)
        XCTAssertEqual(tox.otuUnits, 0)
        XCTAssertFalse(tox.didExceedLimits)
    }

    func testZeroDurationDoesNotAccumulate() {
        var tox = OxygenToxicity()
        tox.accumulate(po2: 1.4, duration: 0)
        XCTAssertEqual(tox.cnsPercent, 0)
        XCTAssertEqual(tox.otuUnits, 0)
    }

    func testTypicalNitroxDiveProducesRealisticCns() {
        // 30 m'de EAN32: PO2 = 1.26 bar, tek doz limiti 180 dk -> 45 dk = %25
        var tox = OxygenToxicity()
        tox.accumulate(po2: 1.26, duration: 45 * 60)
        XCTAssertEqual(tox.cnsPercent, 25, accuracy: 0.5)
    }
}