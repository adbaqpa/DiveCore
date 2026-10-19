import XCTest
@testable import DiveCore

/// ADIM 8 — sunum katmanı (tekrar dalış ve uçuş yasağı ekranı).
final class RepetitiveDiveDisplayTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func loadedTissues() -> TissueModel {
        let scenario = DiveScenario(name: "t", segments: [
            .descent(to: 30, at: 15), .hover(at: 30, for: 45.0 * 60)
        ])
        var engine = DecoEngine(gradientFactors: .conservative,
                                gases: [.air, .oxygen], gasCylinderIndex: 0)
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: .air)
        }
        engine.update(toDepth: 0, duration: engine.timeToSurface(fromDepth: 30), gas: .oxygen)
        return engine.tissues
    }

    private func makeResult(depth: Double = 40, minutes: Double = 25,
                            tissues: TissueModel? = nil) -> RepetitiveDiveCalculator.Result {
        RepetitiveDiveCalculator.calculate(
            tissues: tissues ?? loadedTissues(),
            targetDepth: depth, plannedDuration: minutes * 60.0)
    }

    // MARK: - Tekrar dalış ekranı

    func testDisplayFormatsInputsAndNdlComparison() {
        let display = RepetitiveDiveDisplay(result: makeResult(),
                                            cabinNoFly: 8.0 * 3600,
                                            cabinTitle: "Standart uçuş (8000 ft)")
        XCTAssertEqual(display.targetDepthText, "40 m")
        XCTAssertEqual(display.plannedDurationText, "25:00")
        XCTAssertFalse(display.freshNDLText.isEmpty)
        XCTAssertTrue(display.showsResidualPenalty)
        XCTAssertTrue(display.lossPercent > 0)
    }

    func testDisplayShowsNoPenaltyForFreshDives() {
        let display = RepetitiveDiveDisplay(
            result: makeResult(depth: 20, minutes: 10, tissues: TissueModel()),
            cabinNoFly: 3600, cabinTitle: "Deniz seviyesi")
        XCTAssertFalse(display.showsResidualPenalty)
        XCTAssertEqual(display.lossText, "Etkisi yok")
    }

    func testDisplayShowsNoNdlWhenObligationExists() {
        let display = RepetitiveDiveDisplay(result: makeResult(),
                                            cabinNoFly: 3600, cabinTitle: "Deniz seviyesi")
        XCTAssertEqual(display.effectiveNDLText, "Yok")
        XCTAssertTrue(display.hasDecoRows)
    }

    func testDisplayDecoRowsCarryGasAndSafetyFlag() {
        let display = RepetitiveDiveDisplay(result: makeResult(),
                                            cabinNoFly: 3600, cabinTitle: "Deniz seviyesi")
        for row in display.decoRows {
            XCTAssertFalse(row.depthText.isEmpty)
            XCTAssertFalse(row.durationText.isEmpty)
            XCTAssertFalse(row.gasLabel.isEmpty)
            XCTAssertFalse(row.id.isEmpty)
        }
        // Duraklar derinlik sırasına göre (yüzeye yaklaşarak) gelmelidir
        let depths = display.decoRows.compactMap { Double($0.depthText.split(separator: " ").first ?? "") }
        XCTAssertEqual(depths, depths.sorted(by: >))
    }

    func testDisplayIncludesCabinNoFly() {
        let display = RepetitiveDiveDisplay(result: makeResult(),
                                            cabinNoFly: 20.0 * 3600,
                                            cabinTitle: "Standart uçuş (8000 ft)")
        XCTAssertTrue(display.noFlyCabinText.contains("Standart uçuş"))
        XCTAssertTrue(display.noFlyCabinText != display.noFlyText)
    }

    func testDisplayGasSuggestionIncludesMod() {
        let display = RepetitiveDiveDisplay(result: makeResult(depth: 30, tissues: TissueModel()),
                                            cabinNoFly: 3600, cabinTitle: "Deniz seviyesi")
        XCTAssertTrue(display.gasLabel.contains("EAN") || display.gasLabel.contains("Hava"))
        XCTAssertTrue(display.gasModText.contains("MOD"))
    }

    func testDisplayPassesWarningsThrough() {
        let result = makeResult()
        let display = RepetitiveDiveDisplay(result: result,
                                            cabinNoFly: 3600, cabinTitle: "Deniz seviyesi")
        XCTAssertEqual(display.warnings, result.warnings)
        XCTAssertFalse(display.warnings.isEmpty)
    }

    func testDisplayIsIdentifiableAndCodable() throws {
        let display = RepetitiveDiveDisplay(result: makeResult(),
                                            cabinNoFly: 3600, cabinTitle: "Deniz seviyesi")
        XCTAssertFalse(display.id.isEmpty)
        let data = try JSONEncoder().encode(display)
        let decoded = try JSONDecoder().decode(RepetitiveDiveDisplay.self, from: data)
        XCTAssertEqual(decoded, display)
    }

    // MARK: - Uçuş yasağı ekranı

    private func makeStatus(gf99: Double, noFly: TimeInterval,
                            cleared: Bool = false) -> SurfaceIntervalStatus {
        SurfaceIntervalStatus(elapsed: 2.0 * 3600, gf99: gf99,
                              desaturationRemaining: max(0, noFly - 1800),
                              noFlyRemaining: noFly,
                              isNoFlyCleared: cleared,
                              recommendation: "Test")
    }

    func testNoFlyDisplayActiveState() {
        let next = base.addingTimeInterval(300)
        let display = NoFlyDisplay(status: makeStatus(gf99: 90, noFly: 4.0 * 3600),
                                   cabin: .standardFlight,
                                   cabinRemaining: 16 * 3600,
                                   nextCheck: next, now: base)
        XCTAssertEqual(display.title, "Uçuş yasağı")
        XCTAssertEqual(display.countdown, "4s 0dk")
        XCTAssertTrue(display.isActive)
        XCTAssertEqual(display.colorRole, .caution)
        XCTAssertEqual(display.cabinTitle, FlightAltitudeCalculator.CabinProfile.standardFlight.title)
        XCTAssertEqual(display.nextCheckText, "Sonraki kontrol: 05:00")
    }

    func testNoFlyDisplayClearedState() {
        let display = NoFlyDisplay(status: makeStatus(gf99: 5, noFly: 0, cleared: true),
                                   cabin: .seaLevel, cabinRemaining: 0,
                                   nextCheck: nil, now: base)
        XCTAssertEqual(display.title, "Uçuş serbest")
        XCTAssertEqual(display.countdown, "2s 0dk", "Serbestken geçen yüzey süresi gösterilir")
        XCTAssertFalse(display.isActive)
        XCTAssertEqual(display.colorRole, .safe)
        XCTAssertNil(display.nextCheckText)
    }

    func testNoFlyDisplayProgressIsClamped() {
        let low = NoFlyDisplay(status: makeStatus(gf99: 10, noFly: 600),
                               cabin: .seaLevel, cabinRemaining: 600,
                               nextCheck: nil, now: base)
        let high = NoFlyDisplay(status: makeStatus(gf99: 300, noFly: 20 * 3600),
                                cabin: .seaLevel, cabinRemaining: 20.0 * 3600,
                                nextCheck: nil, now: base)
        // İlerleme, kalan gaz yükünün (GF99/120) oranıdır: yüksek GF99
        // tam dolu, düşük GF99 neredeyse boş çubuk.
        XCTAssertEqual(high.progress, 1, "GF99 %120 ve üzeri tam dolu")
        XCTAssertLessThan(low.progress, high.progress)
        XCTAssertGreaterThanOrEqual(low.progress, 0)
        XCTAssertLessThanOrEqual(low.progress, 1)
    }

    // MARK: - Sunum katmanı <-> hesap tutarlılığı

    @MainActor
    func testDisplayMatchesCalculatorOutput() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .decompressionDive).readings)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!

        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: log.endDate ?? base, log: log)

        let result = makeResult(depth: 40, minutes: 25, tissues: manager.residualTissues)
        let cabinNoFly = FlightAltitudeCalculator.noFlyTime(tissues: manager.residualTissues,
                                                            cabin: .standardFlight)
        let display = RepetitiveDiveDisplay(result: result,
                                            cabinNoFly: cabinNoFly,
                                            cabinTitle: FlightAltitudeCalculator.CabinProfile.standardFlight.title)
        XCTAssertEqual(display.noFlyText, DurationFormatter.hoursMinutes(result.noFlyTime))
        XCTAssertEqual(display.effectiveNDLText,
                       result.effectiveNDL > 0 ? DurationFormatter.clock(result.effectiveNDL) : "Yok")

        let status = manager.status(at: (log.endDate ?? base).addingTimeInterval(3600))
        let noFly = NoFlyDisplay(status: status, cabin: .standardFlight,
                                 cabinRemaining: cabinNoFly, nextCheck: nil, now: base)
        XCTAssertEqual(noFly.countdown, DurationFormatter.hoursMinutes(status.noFlyRemaining))
    }
}