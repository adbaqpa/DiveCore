import XCTest
@testable import DiveCore

/// Oksijen riski değerlendirmesi: PO₂ / CNS / OTU seviyeleri ve alarm mesajı.
final class OxygenStatusTests: XCTestCase {

    // MARK: - PO₂

    func testPo2Levels() {
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.21).po2Level, .ok)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.25).po2Level, .ok)           // eşiğin altı
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.30).po2Level, .caution)     // %90 eşiğinin üstü
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.35).po2Level, .caution)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.45).po2Level, .critical)
    }

    func testPo2ThresholdBoundary() {
        // 1.4 bar azami → tam sınırda uyarı yok, üstünde kritik
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.40).po2Level, .caution)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.41).po2Level, .critical)
    }

    func testCustomMaxPo2() {
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.5, maxPO2: 1.6).po2Level, .caution)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 1.5, maxPO2: 1.3).po2Level, .critical)
    }

    // MARK: - CNS

    func testCnsLevels() {
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 10).cnsLevel, .ok)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 50).cnsLevel, .caution)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 80).cnsLevel, .warning)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 100).cnsLevel, .critical)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 250).cnsLevel, .critical)
    }

    func testCnsWarningThresholdIsConfigurable() {
        // Uyarı eşiği %60 → dikkat bandı 36-60, altı "temiz"
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 30,
                                             warningPercent: 60).cnsLevel, .ok)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, cnsPercent: 50,
                                             warningPercent: 40).cnsLevel, .warning)
    }

    // MARK: - OTU

    func testOtuLevelsUseDailyLimit() {
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, otuPercent: 30, dailyOTULimit: 80).otuLevel, .ok)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, otuPercent: 55, dailyOTULimit: 80).otuLevel, .caution)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, otuPercent: 85, dailyOTULimit: 80).otuLevel, .warning)
        XCTAssertEqual(OxygenStatus.evaluate(po2: 0.3, otuPercent: 120, dailyOTULimit: 80).otuLevel, .critical)
    }

    // MARK: - Birleşik

    func testOverallLevelTakesWorst() {
        let status = OxygenStatus.evaluate(po2: 1.3, cnsPercent: 90, otuPercent: 10)
        XCTAssertEqual(status.po2Level, .caution)
        XCTAssertEqual(status.cnsLevel, .warning)
        XCTAssertEqual(status.overallLevel, .warning)
        XCTAssertTrue(status.isAlarm)
    }

    func testNoAlarmWhenAllOk() {
        let status = OxygenStatus.evaluate(po2: 0.4, cnsPercent: 12, otuPercent: 20)
        XCTAssertEqual(status.overallLevel, .ok)
        XCTAssertFalse(status.isAlarm)
        XCTAssertNil(status.message)
    }

    func testMessagePrefersPo2ThenCnsThenOtu() {
        let po2 = OxygenStatus.evaluate(po2: 1.5, cnsPercent: 90, otuPercent: 90)
        XCTAssertTrue(po2.message?.contains("PO₂") ?? false)

        let cns = OxygenStatus.evaluate(po2: 1.0, cnsPercent: 90, otuPercent: 90)
        XCTAssertTrue(cns.message?.contains("CNS") ?? false)

        let otu = OxygenStatus.evaluate(po2: 1.0, cnsPercent: 10, otuPercent: 90)
        XCTAssertTrue(otu.message?.contains("OTU") ?? false)
    }

    func testCautionMessageOnly() {
        let status = OxygenStatus.evaluate(po2: 1.3, cnsPercent: 10, otuPercent: 10)
        XCTAssertEqual(status.overallLevel, .caution)
        XCTAssertFalse(status.isAlarm)
        XCTAssertNotNil(status.message)
    }

    func testLevelLabelsAndOrdering() {
        XCTAssertGreaterThan(OxygenStatus.Level.critical, .warning)
        XCTAssertGreaterThan(OxygenStatus.Level.warning, .caution)
        XCTAssertGreaterThan(OxygenStatus.Level.caution, .ok)
        XCTAssertEqual(OxygenStatus.Level.ok.label, "Güvenli")
        XCTAssertEqual(OxygenStatus.Level.critical.label, "Tehlikeli")
    }

    // MARK: - DiveState

    func testEvaluateFromState() {
        let state = DiveState(phase: .bottom, currentDepth: 30, maxDepth: 30,
                              gas: .oxygen, gases: [.oxygen], gasIndex: 0,
                              oxygenPartialPressure: 1.28, maximumOperatingDepth: 6,
                              cnsPercent: 50, otuUnits: 60, otuPercent: 55)
        let status = OxygenStatus.evaluate(state: state)
        XCTAssertEqual(status.po2, 1.28)
        XCTAssertEqual(status.po2Level, .caution)
        XCTAssertEqual(status.cnsLevel, .caution)   // %50 ≥ 48
        XCTAssertEqual(status.otuLevel, .caution)    // %55 ≥ 48
        XCTAssertEqual(status.overallLevel, .caution)
    }

    // MARK: - Kodlama

    func testOxygenStatusCodable() throws {
        let status = OxygenStatus.evaluate(po2: 1.1, cnsPercent: 40, otuPercent: 30)
        let data = try JSONEncoder().encode(status)
        XCTAssertEqual(try JSONDecoder().decode(OxygenStatus.self, from: data), status)
    }

    // MARK: - Oturum

    @MainActor
    func testControllerExposesOxygenStatus() {
        let controller = DiveSessionController(
            configuration: DiveConfiguration(gases: [.oxygen], maxPO2: 1.6))
        controller.start()
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "t", segments: [
            .descent(to: 5, at: 5), .hover(at: 5, for: 30 * 60.0)
        ])).readings)

        let status = controller.oxygenStatus
        XCTAssertGreaterThan(status.po2, 1.0)
        XCTAssertGreaterThan(status.cnsPercent, 10)
        XCTAssertNotEqual(status.overallLevel, .ok)
    }
}