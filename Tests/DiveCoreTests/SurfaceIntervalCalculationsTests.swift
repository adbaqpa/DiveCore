import XCTest
@testable import DiveCore

/// ADIM 8 — Uçuş yasağı (kabin basıncı), arka plan izleme ve tekrarlı dalış.
final class SurfaceIntervalCalculationsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcı

    /// 30 m/45 dk deko dalışından sonra kalan doku durumu.
    private func loadedTissues(minutes: Double = 45) -> TissueModel {
        let scenario = DiveScenario(name: "t", segments: [
            .descent(to: 30, at: 15), .hover(at: 30, for: minutes * 60)
        ])
        var engine = DecoEngine(gradientFactors: .conservative,
                                gases: [.air, .oxygen], gasCylinderIndex: 0)
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: .air)
        }
        // Yüzeye çıkış
        engine.update(toDepth: 0, duration: engine.timeToSurface(fromDepth: 30), gas: .oxygen)
        return engine.tissues
    }

    // MARK: - Kabin basıncı

    func testCabinPressures() {
        XCTAssertEqual(FlightAltitudeCalculator.cabinPressure(for: .seaLevel), 1.0, accuracy: 0.001)
        XCTAssertEqual(FlightAltitudeCalculator.cabinPressure(for: .standardFlight), 0.75, accuracy: 0.001)
        XCTAssertLessThan(FlightAltitudeCalculator.cabinPressure(for: .highAltitudeFlight), 0.75)
    }

    func testLowerCabinPressureIncreasesNoFlyTime() {
        let tissues = loadedTissues()
        let sea = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .seaLevel)
        let flight = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .standardFlight)
        let high = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .highAltitudeFlight)

        XCTAssertGreaterThan(flight, sea, "Düşük kabin basıncında doku daha yavaş çözülür")
        XCTAssertGreaterThan(high, flight)
        XCTAssertGreaterThan(sea, 3 * 3600, "30 m/45 dk dalıştan sonra en az birkaç saat")
    }

    func testNoFlyIsRoundedToQuarterHour() {
        let tissues = loadedTissues()
        let time = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .standardFlight)
        XCTAssertEqual(time.truncatingRemainder(dividingBy: 900), 0, accuracy: 1)
    }

    func testCleanTissuesHaveMinimalNoFly() {
        let clean = TissueModel(gradientFactors: .conservative)
        let time = FlightAltitudeCalculator.noFlyTime(tissues: clean)
        XCTAssertLessThanOrEqual(time, 75 * 60, "Temiz dokuda yalnızca emniyet payı")
        XCTAssertGreaterThanOrEqual(time, 60 * 60, "60 dakikalık güvenlik payı her zaman eklenir")
    }

    func testSafetyImprovementPercentage() {
        let tissues = loadedTissues()
        let extra = FlightAltitudeCalculator.additionalWaitPercent(
            from: .seaLevel, to: .standardFlight, tissues: tissues)
        XCTAssertGreaterThan(extra, 100, "Standart kabin profilinde bekleme süresi katlanır")
        XCTAssertGreaterThan(FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .standardFlight),
                             FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .seaLevel))
    }

    func testNoFlyEndDate() {
        let tissues = loadedTissues()
        let end = FlightAltitudeCalculator.noFlyEnd(tissues: tissues, diveEnd: base)
        XCTAssertGreaterThan(end, base)
        XCTAssertEqual(end.timeIntervalSince(base).truncatingRemainder(dividingBy: 900), 0, accuracy: 1)
    }

    func testGf99AtAmbientPressureDiffersFromSurface() {
        let tissues = loadedTissues()
        let surface = tissues.gf99(atDepth: 0)
        let cabin = tissues.gf99(atAmbientPressure: 0.75)
        XCTAssertGreaterThan(cabin, surface,
                             "Düşük basınçta aynı doku yükü daha yüksek GF gösterir")
    }

    func testStepAtAmbientPressureOffGassesSlower() {
        let loaded = loadedTissues()
        let beforeSea = loaded.gf99(atDepth: 0)
        let beforeCabin = loaded.gf99(atAmbientPressure: 0.75)

        var sea = loaded
        var cabin = loaded
        sea.step(atAmbientPressure: 1.0, duration: 1800, gas: .air)
        cabin.step(atAmbientPressure: 0.75, duration: 1800, gas: .air)

        // Kalan yük oranı: deniz seviyesinde daha fazlası çözülür
        let seaRatio = sea.gf99(atDepth: 0) / max(beforeSea, 0.001)
        let cabinRatio = cabin.gf99(atAmbientPressure: 0.75) / max(beforeCabin, 0.001)
        XCTAssertGreaterThan(cabinRatio, seaRatio,
                             "Düşük kabin basıncında aynı sürede daha az çözünme olur")
    }

    // MARK: - Arka plan izleme

    func testBackgroundPolicyIntervals() {
        let policy = BackgroundMonitoringPolicy.standard
        XCTAssertEqual(policy.maximumInterval, 900)
        XCTAssertEqual(policy.minimumInterval, 60)

        // Uzak gelecek: 15 dakikada bir
        let far = policy.nextCheckDate(now: base, remainingNoFly: 12 * 3600, remainingDesaturation: 12 * 3600)
        XCTAssertEqual(far?.timeIntervalSince(base), 900)

        // Son 15 dakika: sık kontrol
        let near = policy.nextCheckDate(now: base, remainingNoFly: 600, remainingDesaturation: 600)
        XCTAssertEqual(near?.timeIntervalSince(base), 60)

        // Son 1 saat: orta sıklık
        let mid = policy.nextCheckDate(now: base, remainingNoFly: 1800, remainingDesaturation: 1800)
        XCTAssertEqual(mid?.timeIntervalSince(base), 300)
    }

    func testBackgroundPolicyStopsWhenNoFlyCleared() {
        let policy = BackgroundMonitoringPolicy.standard
        XCTAssertNil(policy.nextCheckDate(now: base, remainingNoFly: 0, remainingDesaturation: 0))
        XCTAssertEqual(policy.expectedCheckCount(remainingNoFly: 0), 0)
    }

    func testBackgroundPolicyDuringDive() {
        let policy = BackgroundMonitoringPolicy.standard
        let next = policy.nextCheckDate(now: base, remainingNoFly: 0, remainingDesaturation: 0, isDiving: true)
        XCTAssertNotNil(next, "Dalış sırasında izleme durmaz")
        XCTAssertEqual(next?.timeIntervalSince(base), 60)
    }

    func testExpectedCheckCountIsBounded() {
        let policy = BackgroundMonitoringPolicy.standard
        let sixHours = policy.expectedCheckCount(remainingNoFly: 6 * 3600)
        XCTAssertGreaterThan(sixHours, 20)
        XCTAssertLessThanOrEqual(sixHours, policy.maximumChecks, "Pil dostu: bütçe aşılmaz")
        XCTAssertLessThan(sixHours, 60)
    }

    func testCheckBudgetStretchesIntervals() {
        let policy = BackgroundMonitoringPolicy.standard
        // Bütçe tükenmek üzereyken aralık uzar
        let generous = policy.checkInterval(remaining: 3600, usedChecks: 0)
        let scarce = policy.checkInterval(remaining: 3600, usedChecks: 55)
        XCTAssertGreaterThan(scarce, generous)
        XCTAssertLessThanOrEqual(scarce, policy.maximumInterval)
    }

    func testBudgetExhaustionSchedulesFinalCheck() {
        let policy = BackgroundMonitoringPolicy.standard
        let next = policy.nextCheckDate(now: base, remainingNoFly: 4 * 3600,
                                        remainingDesaturation: 4 * 3600,
                                        usedChecks: policy.maximumChecks)
        XCTAssertEqual(next?.timeIntervalSince(base), 4 * 3600,
                       "Bütçe bitince tek bir kapanış kontroli")
    }

    func testFrequentPolicyChecksMoreOften() {
        let standard = BackgroundMonitoringPolicy.standard
        let frequent = BackgroundMonitoringPolicy.frequent
        XCTAssertGreaterThan(frequent.expectedCheckCount(remainingNoFly: 12 * 3600),
                             standard.expectedCheckCount(remainingNoFly: 12 * 3600))
        XCTAssertLessThan(frequent.checkInterval(remaining: 12 * 3600),
                          standard.checkInterval(remaining: 12 * 3600))
    }

    // MARK: - SurfaceIntervalManager entegrasyonu

    @MainActor
    func testManagerExposesResidualTissuesAndNextCheck() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .decompressionDive).readings)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!

        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: log.endDate ?? base, log: log)

        XCTAssertGreaterThan(manager.residualTissues.leadingNitrogenPressure, 0.8)
        XCTAssertGreaterThan(manager.noFlyTime(cabin: .seaLevel), 0)
        XCTAssertNotNil(manager.predictedNoFlyEnd(cabin: .seaLevel))
        XCTAssertNotNil(manager.nextBackgroundCheck(at: log.endDate ?? base))
    }

    @MainActor
    func testCabinNoFlyIsLongerThanSeaLevel() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .decompressionDive).readings)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!

        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: log.endDate ?? base, log: log)
        XCTAssertGreaterThan(manager.noFlyTime(cabin: .standardFlight),
                             manager.noFlyTime(cabin: .seaLevel))
    }

    // MARK: - Tekrar dalış hesaplayıcısı

    func testRepetitiveDiveWithResidualLoading() {
        let tissues = loadedTissues()
        let result = RepetitiveDiveCalculator.calculate(
            tissues: tissues, targetDepth: 40, plannedDuration: 20 * 60)

        XCTAssertEqual(result.targetDepth, 40)
        XCTAssertLessThan(result.effectiveNDL, result.freshNDL,
                          "Artık yük NDL'yi kısaltmalı")
        XCTAssertGreaterThan(result.ndlLossPercent, 50)
        XCTAssertTrue(result.warnings.contains { $0.contains("artık") })
    }

    func testFreshDiveHasNoPenalty() {
        let clean = TissueModel(gradientFactors: .conservative)
        let result = RepetitiveDiveCalculator.calculate(
            tissues: clean, targetDepth: 30, plannedDuration: 15 * 60)

        XCTAssertEqual(result.effectiveNDL, result.freshNDL, accuracy: 1)
        XCTAssertEqual(result.ndlLossPercent, 0, accuracy: 0.5)
    }

    func testLongerSurfaceIntervalRestoresNdl() {
        let tissues = loadedTissues()
        var recovered = tissues
        recovered.step(atDepth: 0, duration: 6 * 3600, gas: .air)

        let immediate = RepetitiveDiveCalculator.calculate(
            tissues: tissues, targetDepth: 40, plannedDuration: 20 * 60)
        let later = RepetitiveDiveCalculator.calculate(
            tissues: recovered, targetDepth: 40, plannedDuration: 20 * 60)

        XCTAssertGreaterThan(later.effectiveNDL, immediate.effectiveNDL)
    }

    func testRepetitiveResultIncludesDecoPlanAndNoFly() {
        let result = RepetitiveDiveCalculator.calculate(
            tissues: loadedTissues(), targetDepth: 40, plannedDuration: 30 * 60)
        XCTAssertGreaterThan(result.plan.totalTime, 0)
        XCTAssertGreaterThan(result.noFlyTime, 0)
        XCTAssertTrue(result.suggestedGas.oxygenFraction >= 0.21)
    }

    func testSuggestedGasRespectsMod() {
        let result = RepetitiveDiveCalculator.calculate(
            tissues: TissueModel(), targetDepth: 30, plannedDuration: 20 * 60)
        XCTAssertGreaterThanOrEqual(
            result.suggestedGas.maximumOperatingDepth(maxPO2: 1.4), 29.5)
    }

    func testUnusableGasProducesWarning() {
        let result = RepetitiveDiveCalculator.calculate(
            tissues: TissueModel(), targetDepth: 45, plannedDuration: 20 * 60,
            gas: .nitrox(40) ?? .ean36)
        XCTAssertTrue(result.warnings.contains { $0.contains("kullanılamaz") })
    }

    func testDiveSequenceAccountsForPreviousDives() {
        let results = RepetitiveDiveCalculator.sequence(
            dives: [(depth: 30.0, duration: 20.0 * 60),
                    (depth: 30.0, duration: 20.0 * 60),
                    (depth: 30.0, duration: 20.0 * 60)],
            surfaceInterval: 90 * 60)

        XCTAssertEqual(results.count, 3)
        // İkinci ve üçüncü dalış artık yük nedeniyle daha kısa NDL görmeli
        XCTAssertLessThanOrEqual(results[1].effectiveNDL, results[0].effectiveNDL)
        XCTAssertLessThanOrEqual(results[2].effectiveNDL, results[1].effectiveNDL)
    }

    func testSequenceWithLongSurfaceIntervalRecovers() {
        let short = RepetitiveDiveCalculator.sequence(
            dives: [(depth: 30.0, duration: 20.0 * 60), (depth: 30.0, duration: 20.0 * 60)],
            surfaceInterval: 60 * 60)
        let long = RepetitiveDiveCalculator.sequence(
            dives: [(depth: 30.0, duration: 20.0 * 60), (depth: 30.0, duration: 20.0 * 60)],
            surfaceInterval: 8 * 3600)

        // NDL ikisi de taze değere ulaşmış olabilir; asıl fark uçuş yasağındadır
        XCTAssertGreaterThanOrEqual(long[1].effectiveNDL, short[1].effectiveNDL)
        XCTAssertLessThan(long[1].noFlyTime, short[1].noFlyTime)
    }

    // MARK: - Plan bitiş dokuları

    func testEndTissuesAreCleanerThanDiveEnd() {
        let tissues = loadedTissues()
        let result = RepetitiveDiveCalculator.calculate(
            tissues: tissues, targetDepth: 40, plannedDuration: 30 * 60)

        XCTAssertLessThan(result.endTissues.gf99(atDepth: 0),
                          tissues.gf99(atDepth: 0),
                          "Deko tamamlandığında yüzey GF99 düşer")
    }

    func testEndTissuesProduceSameNoFlyAsResult() {
        let result = RepetitiveDiveCalculator.calculate(
            tissues: loadedTissues(), targetDepth: 40, plannedDuration: 30 * 60)
        let recomputed = FlightAltitudeCalculator.noFlyTime(tissues: result.endTissues,
                                                            cabin: .seaLevel)
        XCTAssertEqual(recomputed, result.noFlyTime, accuracy: 60)
    }

    func testEndTissuesDoNotAffectNdlCalculation() {
        // Bitiş dokuları yalnızca çıkış/uyuş yasağı içindir; NDL girişte hesaplanır.
        let result = RepetitiveDiveCalculator.calculate(
            tissues: TissueModel(), targetDepth: 30, plannedDuration: 20 * 60)
        let again = RepetitiveDiveCalculator.calculate(
            tissues: result.endTissues, targetDepth: 30, plannedDuration: 20 * 60)
        XCTAssertGreaterThan(again.effectiveNDL, 0)
    }

    // MARK: - DecoEngine.restore

    func testRestoreReplacesTissues() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 30, duration: 1200)
        let loaded = engine.tissues

        var fresh = DecoEngine(gradientFactors: .conservative)
        fresh.restore(tissues: loaded)
        XCTAssertEqual(fresh.leadingTissuePressure, engine.leadingTissuePressure, accuracy: 0.001)
        XCTAssertEqual(fresh.tissues.nitrogenPressures, loaded.nitrogenPressures)
    }

    func testRestoreCanOverrideGradientFactors() {
        var engine = DecoEngine(gradientFactors: .default)
        engine.update(toDepth: 30, duration: 1200)
        let relaxed = engine.ceiling(atDepth: 0).depthMeters

        var tight = engine
        tight.restore(tissues: engine.tissues, gradientFactors: .technical)
        XCTAssertGreaterThan(tight.ceiling(atDepth: 0).depthMeters, relaxed)
    }

    // MARK: - NDL etkileşimi (regresyon)

    func testResidualLoadingNeverIncreasesNdl() {
        let tissues = loadedTissues()
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.restore(tissues: tissues)

        let fresh = DecoEngine(gradientFactors: .conservative)
        XCTAssertLessThanOrEqual(engine.noDecompressionLimit(atDepth: 25),
                                 fresh.noDecompressionLimit(atDepth: 25))
    }

    func testNoFlyTimeIsMonotonicInCabinAltitude() {
        let tissues = loadedTissues()
        let sea = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .seaLevel)
        let standard = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .standardFlight)
        let high = FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: .highAltitudeFlight)
        XCTAssertLessThan(sea, standard)
        XCTAssertLessThan(standard, high)
    }
}