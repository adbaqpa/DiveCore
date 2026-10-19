import XCTest
@testable import DiveCore

/// Uçtan uca dalış oturumu: sensör okuması → dekompresyon motoru → `DiveState`.
@MainActor
final class DiveSessionControllerTests: XCTestCase {

    // MARK: - Yardımcılar

    private func makeController(
        gradientFactors: GradientFactors = .conservative,
        gases: [GasMix] = [.air],
        startGas: Int = 0,
        haptic: HapticEngine? = nil
    ) -> DiveSessionController {
        DiveSessionController(
            configuration: DiveConfiguration(gradientFactors: gradientFactors,
                                             gases: gases,
                                             startGasIndex: startGas),
            haptic: haptic)
    }

    /// Simülatör okumalarını denetleyiciye besler.
    @discardableResult
    private func feed(_ controller: DiveSessionController,
                      _ readings: [DepthReading]) -> DiveState {
        controller.ingest(readings)
        return controller.state
    }

    // MARK: - Yaşam döngüsü

    func testInitialStateIsPreDive() {
        let controller = makeController()
        XCTAssertEqual(controller.state.phase, .preDive)
        XCTAssertFalse(controller.isRunning)
        XCTAssertTrue(controller.samples.isEmpty)
    }

    func testStartResetsState() {
        let controller = makeController()
        controller.start(at: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(controller.state.phase, .preDive)
        XCTAssertEqual(controller.state.startDate, Date(timeIntervalSince1970: 1000))
    }

    func testIngestWithoutStartIsIgnored() {
        let controller = makeController()
        let reading = DepthReading(depth: 10, timestamp: Date(), elapsed: 1)
        controller.ingest(reading)
        XCTAssertEqual(controller.state.currentDepth, 0)
        XCTAssertTrue(controller.samples.isEmpty)
    }

    func testStateChangeCallbackFires() {
        let controller = makeController()
        var updates = 0
        controller.onStateChange = { _ in updates += 1 }
        controller.start()
        feed(controller, [DepthReading(depth: 5, timestamp: Date(), elapsed: 1)])
        XCTAssertGreaterThan(updates, 1)
    }

    func testCallbackDeliversLiveState() {
        let controller = makeController()
        var lastDepth: Double = 0
        controller.onStateChange = { lastDepth = $0.currentDepth }
        controller.start()
        feed(controller, [DepthReading(depth: 12, timestamp: Date(), elapsed: 1)])
        XCTAssertEqual(lastDepth, 12)
    }

    // MARK: - Temel takip

    func testDepthAndDurationAreTracked() {
        let controller = makeController()
        controller.start()
        let simulator = DiveSimulator(scenario: .beginner)

        let fed = simulator.readings(from: 0, to: 600)
        feed(controller, fed)
        let state = controller.state
        XCTAssertEqual(state.currentDepth, fed.last!.depth, accuracy: 0.01)
        XCTAssertEqual(state.diveTime, 600, accuracy: 1)
        XCTAssertGreaterThan(state.maxDepth, 11)
    }

    func testMaxDepthIsTracked() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 1500))
        XCTAssertGreaterThan(controller.state.maxDepth, 29)
        XCTAssertLessThanOrEqual(controller.state.maxDepth, 30.5)
    }

    func testAverageDepthIsComputed() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 1800))

        let average = controller.state.averageDepth
        XCTAssertGreaterThan(average, 10)
        XCTAssertLessThan(average, controller.state.maxDepth)
    }

    func testTemperatureFollowsSensor() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 600))
        // Dipte sıcaklık düşmüş olmalı
        XCTAssertLessThan(controller.state.waterTemperature, controller.state.surfaceTemperature)
    }

    func testAscentRateIsReported() {
        let controller = makeController()
        controller.start()
        let readings = DiveSimulator(scenario: .recreational30m).readings
        // Dip sonrası çıkışa kadar besle
        let ascentStart = readings.firstIndex { $0.depth > 29.5 } ?? 0
        feed(controller, Array(readings[ascentStart...]))
        XCTAssertGreaterThan(controller.ascentRate, 0.5)
        XCTAssertNotEqual(controller.state.ascentRateStatus, .descending)
    }

    func testNdlIsComputedWhileDescending() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 90))
        // 30 m'de henüz deko yükümlülüğü olmamalı, NDL pozitif olmalı
        XCTAssertGreaterThan(controller.state.noDecompressionLimit, 0)
        XCTAssertEqual(controller.state.ceilingDepth, 0)
    }

    func testDecoObligationAppearsOnLongDive() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 1400))
        // 20+ dakika 30 m → tavan oluşmalı
        XCTAssertGreaterThan(controller.state.ceilingDepth, 0)
        XCTAssertEqual(controller.state.noDecompressionLimit, 0)
    }

    // MARK: - Fazlar

    func testPhaseTransitions() {
        let controller = makeController()
        controller.start()

        let readings = DiveSimulator(scenario: .recreational30m).readings
        var phases: [DivePhase] = []
        var lastPhase: DivePhase?

        controller.onStateChange = { state in
            if state.phase != lastPhase {
                phases.append(state.phase)
                lastPhase = state.phase
            }
        }
        controller.ingest(readings)

        XCTAssertEqual(phases.first, .preDive)
        XCTAssertTrue(phases.contains(.descending))
        XCTAssertTrue(phases.contains(.bottom))
        XCTAssertTrue(phases.contains(.safetyStop))
        XCTAssertTrue(phases.contains(.surfaced))
    }

    func testSafetyStopPhaseIsEntered() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings)
        // Emniyet durağı sırasında en az bir kez safetyStop fazı görülmeli
        XCTAssertTrue(controller.markers.contains { $0.kind == .safetyStopStart })
    }

    // MARK: - Emniyet durağı

    func testSafetyStopAccumulatesAtFiveMeters() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings)

        XCTAssertTrue(controller.state.safetyStop.accumulated > 120,
                      "3 dakikalık emniyet durağı birikmiş olmalı")
        XCTAssertTrue(controller.markers.contains { $0.kind == .safetyStopComplete })
    }

    func testSafetyStopAbandonedWhenAscendedThrough() {
        let controller = makeController()
        controller.start()
        // 5 m bölgesinden hızlıca geçip yüzeye çık (durağı beklemeden)
        feed(controller, DiveSimulator(scenario: .safetyStopSkipped).readings)

        XCTAssertTrue(controller.state.safetyStop.wasAbandoned,
                      "Durağı tamamlamadan çıkılırsa işaretlenmeli")
        XCTAssertFalse(controller.isSafetyStopComplete)
        XCTAssertLessThan(controller.state.safetyStop.accumulated,
                          DiveSafetyLimits.safetyStopDuration)
        XCTAssertTrue(controller.state.warnings.contains { $0.kind == .safetyStopSkipped })
    }

    func testSafetyStopProgressAndCompletion() {
        let controller = makeController()
        controller.start()

        // 5 m'ye in, 3 dakika bekle, yüzeye çık
        feed(controller, DiveSimulator(scenario: DiveScenario(name: "test", segments: [
            .descent(to: 8, at: 10),
            .hover(at: 5, for: 200.0),
            .ascent(to: 0, at: 9)
        ])).readings)

        XCTAssertTrue(controller.isSafetyStopComplete)
        XCTAssertFalse(controller.state.safetyStop.wasAbandoned)
        XCTAssertEqual(controller.state.safetyStop.accumulated, 180, accuracy: 2)
    }

    // MARK: - Hızlı çıkış alarmı

    func testFastAscentTriggersCriticalAlarm() {
        let haptic = RecordingHapticEngine()
        let controller = makeController(haptic: haptic)
        controller.start()

        var alarmKinds: [AlarmKind] = []
        controller.onAlarms = { actions in alarmKinds.append(contentsOf: actions.map(\.kind)) }

        feed(controller, DiveSimulator(scenario: .fastAscentViolation).readings)

        XCTAssertTrue(alarmKinds.contains(.critical), "Hızlı çıkış kritik alarm üretmeli")
        XCTAssertGreaterThan(haptic.totalFeedbackCount, 0, "Titreşim tetiklenmeli")
    }

    func testFastAscentProducesFeedbackAndVisualAlert() {
        let haptic = RecordingHapticEngine()
        let controller = makeController(haptic: haptic)
        controller.start()
        feed(controller, DiveSimulator(scenario: .fastAscentViolation).readings)

        XCTAssertTrue(haptic.performed.contains { $0.feedback == .critical })
        XCTAssertTrue(haptic.performed.contains { $0.visualLevel == .fullScreenAlert })
    }

    func testSafeAscentDoesNotTriggerFastAscentAlarm() {
        let haptic = RecordingHapticEngine()
        let controller = makeController(haptic: haptic)
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings)

        XCTAssertFalse(haptic.performed.contains { $0.sourceWarning == .fastAscent },
                       "Güvenli çıkışta hız alarmı olmamalı")
    }

    func testFastAscentWarningAppearsInState() {
        let controller = makeController()
        controller.start()

        // Hızlı çıkış sırasında durumda uyarı bulunmalı
        var sawFastAscent = false
        controller.onStateChange = { state in
            if state.warnings.contains(where: { $0.kind == .fastAscent }) { sawFastAscent = true }
        }
        controller.ingest(DiveSimulator(scenario: .fastAscentViolation).readings)
        XCTAssertTrue(sawFastAscent)
    }

    // MARK: - Diğer uyarılar

    func testNdlReachedWarning() {
        let controller = makeController()
        controller.start()
        var sawNDL = false
        controller.onStateChange = { state in
            if state.warnings.contains(where: { $0.kind == .noDecoLimitReached }) { sawNDL = true }
        }
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        XCTAssertTrue(sawNDL, "NDL dolduğunda uyarılmalı")
    }

    func testCeilingViolationWarning() {
        let controller = makeController()
        controller.start()

        var sawViolation = false
        controller.onStateChange = { state in
            if state.warnings.contains(where: { $0.kind == .ceilingViolation }) { sawViolation = true }
        }
        // 45 m'de 50 dakika → büyük tavan; sonra hızlıca yüzeye çık
        let readings = DiveSimulator(scenario: DiveScenario(name: "test", segments: [
            .descent(to: 45, at: 15),
            .hover(at: 45, for: 50 * 60.0),
            .ascent(to: 0, at: 20)
        ])).readings
        controller.ingest(readings)
        XCTAssertTrue(sawViolation, "Tavanın üstüne çıkılınca kritik uyarı verilmeli")
    }

    func testModViolationWarning() {
        // EAN36'ın MOD'u ~40 m; 45 m'de dalış yapılırsa aşılır
        let controller = DiveSessionController(
            configuration: DiveConfiguration(gases: [.ean36], maxPO2: 1.4))
        controller.start()

        var sawExceeded = false
        controller.onStateChange = { state in
            if state.warnings.contains(where: { $0.kind == .depthExceeded }) { sawExceeded = true }
        }
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "test", segments: [
            .descent(to: 45, at: 15), .hover(at: 45, for: 300.0)
        ])).readings)
        XCTAssertTrue(sawExceeded)
    }

    func testOxygenWarningOnDeepNitroxDive() {
        let controller = DiveSessionController(
            configuration: DiveConfiguration(gases: [.ean36], maxPO2: 1.4))
        controller.start()

        var sawOxygen = false
        controller.onStateChange = { state in
            if state.warnings.contains(where: { $0.kind == .oxygenWarning }) { sawOxygen = true }
        }
        // EAN36'ın MOD'u 40 m; 39 m'de PO2 = 1.38 → sınıra yakın uyarı
        controller.ingest(DiveSimulator(scenario: DiveScenario(name: "test", segments: [
            .descent(to: 39, at: 12), .hover(at: 39, for: 300.0)
        ])).readings)
        XCTAssertTrue(sawOxygen)
    }

    func testCnsWarningOnLongDeepDive() {
        let controller = DiveSessionController(
            configuration: DiveConfiguration(gases: [.oxygen], maxPO2: 1.6))
        controller.start()

        var sawCNS = false
        controller.onStateChange = { state in
            if state.warnings.contains(where: { $0.kind == .cnsLimit }) { sawCNS = true }
        }
        // 6 m'de saf O2, 4 saat → CNS %100+
        var readings: [DepthReading] = []
        for step in 0...240 {
            readings.append(DepthReading(depth: 6,
                                         timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(step) * 60),
                                         elapsed: Double(step) * 60,
                                         temperature: 20, isSimulated: true))
        }
        controller.ingest(readings)
        XCTAssertTrue(sawCNS)
    }

    // MARK: - Gaz değişimi

    func testGasSwitchUpdatesState() {
        let controller = makeController(gases: [.air, .ean32], startGas: 0)
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 600))

        controller.switchGas(to: 1)
        XCTAssertEqual(controller.state.gas, .ean32)
        XCTAssertEqual(controller.state.gasIndex, 1)
        XCTAssertTrue(controller.markers.contains { $0.kind == .gasChange })

        // Yeni gazla MOD düşer
        XCTAssertLessThan(controller.state.maximumOperatingDepth,
                          DiveSimulationConstants.airMOD)
    }

    func testInvalidGasIndexIsIgnored() {
        let controller = makeController(gases: [.air])
        controller.start()
        controller.switchGas(to: 9)
        XCTAssertEqual(controller.state.gas, .air)
    }

    func testGasSwitchReducesNitrogenLoading() {
        // Aynı noktada (dipte) karşılaştırma yapılır
        let bottomProfile = DiveSimulator(scenario: DiveScenario(name: "test", segments: [
            .descent(to: 30, at: 15), .hover(at: 30, for: 20 * 60.0)
        ])).readings

        let air = makeController(gases: [.air])
        air.start()
        feed(air, bottomProfile)

        let nitrox = makeController(gases: [.ean32])
        nitrox.start()
        feed(nitrox, bottomProfile)

        XCTAssertLessThan(nitrox.state.ceilingDepth, air.state.ceilingDepth,
                          "EAN32 daha az N2 yüklemeli")
        XCTAssertLessThan(nitrox.state.gf99, air.state.gf99)
        // Buna karşılık EAN32'de O2 daha fazladır: CNS *yüksektir*
        XCTAssertGreaterThan(nitrox.state.cnsPercent, air.state.cnsPercent,
                             "EAN32'de oksijen toksisitesi daha yüksek olmalı")
    }

    // MARK: - İşaretler

    func testMarkerIsRecorded() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .beginner).readings(from: 0, to: 60))

        controller.addMarker(label: "Balık gördüm")
        let marker = controller.markers.last
        XCTAssertEqual(marker?.kind, .marker)
        XCTAssertEqual(marker?.label, "Balık gördüm")
        XCTAssertEqual(marker?.depth ?? 0, controller.state.currentDepth, accuracy: 0.5)
    }

    // MARK: - Profil kaydı

    func testSamplesAreRecordedAtConfiguredInterval() {
        let controller = DiveSessionController(
            configuration: DiveConfiguration(profileSampleInterval: 10))
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 600))

        // 600 sn / 10 sn = 61 örnek
        XCTAssertEqual(controller.samples.count, 61)
        XCTAssertEqual(controller.samples.first?.elapsed, 0)
    }

    func testSamplesContainDecoInformation() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .recreational30m).readings(from: 0, to: 1500))

        XCTAssertTrue(controller.samples.contains { $0.ceiling > 0 }, "Deko anı kaydedilmeli")
        XCTAssertTrue(controller.samples.contains { $0.gf99 > 50 })
        XCTAssertTrue(controller.samples.allSatisfy { $0.depth >= 0 })
    }

    // MARK: - Dalış sonu

    func testEndProducesLogEntry() {
        let controller = makeController()
        controller.start(at: Date(timeIntervalSince1970: 1_700_000_000))
        feed(controller, DiveSimulator(scenario: .recreational30m).readings)

        let log = controller.end(at: Date(timeIntervalSince1970: 1_700_000_000 + 1800))
        XCTAssertNotNil(log)
        XCTAssertEqual(log?.maxDepth ?? 0, controller.state.maxDepth, accuracy: 0.5)
        XCTAssertGreaterThan(log?.totalDiveTime ?? 0, 25 * 60)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.state.phase, .ended)
        XCTAssertTrue(log?.safetyStopCompleted ?? false)
        XCTAssertGreaterThan(log?.noFlyTime ?? 0, 0)
        XCTAssertTrue(controller.markers.contains { $0.kind == .end })
    }

    func testEndWithoutStartReturnsNil() {
        XCTAssertNil(makeController().end())
    }

    func testLogEntryMaxGF99AndPo2AreTracked() {
        let controller = DiveSessionController(configuration: DiveConfiguration(gases: [.ean32]))
        controller.start(at: Date(timeIntervalSince1970: 1_700_000_000))
        feed(controller, DiveSimulator(scenario: .recreational30m).readings)
        let log = controller.end(at: Date(timeIntervalSince1970: 1_700_000_000 + 1800))

        XCTAssertGreaterThan(log?.maxGF99 ?? 0, 50)
        XCTAssertGreaterThan(log?.maxPO2 ?? 0, 1.0)
        XCTAssertGreaterThan(log?.cnsPercent ?? 0, 0)
    }

    func testCancellationKeepsNoLog() {
        let controller = makeController()
        controller.start()
        feed(controller, DiveSimulator(scenario: .beginner).readings(from: 0, to: 300))
        controller.cancel()
        XCTAssertNil(controller.end())
        XCTAssertFalse(controller.isRunning)
    }

    // MARK: - Yön bilgisi

    func testHeadingUpdate() {
        let controller = makeController()
        controller.start()
        controller.updateHeading(127.5)
        XCTAssertEqual(controller.state.heading ?? 0, 127.5, accuracy: 0.001)
    }

    // MARK: - Deterministik

    func testSameProfileProducesIdenticalState() {
        let first = makeController(gradientFactors: .moderate)
        first.start(at: Date(timeIntervalSince1970: 0))
        first.ingest(DiveSimulator(scenario: .recreational30m).readings)

        let second = makeController(gradientFactors: .moderate)
        second.start(at: Date(timeIntervalSince1970: 0))
        second.ingest(DiveSimulator(scenario: .recreational30m).readings)

        XCTAssertEqual(first.state.ceilingDepth, second.state.ceilingDepth, accuracy: 1e-9)
        XCTAssertEqual(first.state.gf99, second.state.gf99, accuracy: 1e-9)
        XCTAssertEqual(first.state.noFlyTime, second.state.noFlyTime)
        XCTAssertEqual(first.samples.count, second.samples.count)
    }

    func testGradientFactorsAffectLiveState() {
        // Sığ dalış: NDL her iki ayarda da pozitif kalır
        let profile = DiveSimulator(scenario: DiveScenario(name: "test", segments: [
            .descent(to: 18, at: 12), .hover(at: 18, for: 90.0)
        ])).readings

        let loose = makeController(gradientFactors: .default)
        loose.start()
        feed(loose, profile)

        let tight = makeController(gradientFactors: GradientFactors(low: 30, high: 70))
        tight.start()
        feed(tight, profile)

        XCTAssertGreaterThan(loose.state.noDecompressionLimit, 0)
        XCTAssertGreaterThan(tight.state.noDecompressionLimit, 0)
        XCTAssertLessThan(tight.state.noDecompressionLimit, loose.state.noDecompressionLimit,
                          "Daha düşük GF daha kısa NDL vermeli")
        // Düşük GF çok daha muhafazakârdır, ama sıfıra düşmez
        XCTAssertGreaterThan(tight.state.noDecompressionLimit,
                             loose.state.noDecompressionLimit * 0.02)
    }
}

// MARK: - Yardımcı sabitler

enum DiveSimulationConstants {
    /// Havada MOD (PO2 1.4) — referans değer
    static let airMOD = DiveSimulationConstants.computeAirMOD()

    private static func computeAirMOD() -> Double {
        GasMix.air.maximumOperatingDepth(maxPO2: 1.4)
    }
}