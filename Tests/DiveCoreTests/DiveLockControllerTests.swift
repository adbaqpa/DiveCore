import XCTest
@testable import DiveCore

/// ADIM 7 — Su kilidi (dokunma kilidi + su atma döngüsü) ve Action Button.
@MainActor
final class DiveLockControllerTests: XCTestCase {

    // MARK: - Temel durum

    func testStartsUnlocked() {
        let controller = DiveLockController()
        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(controller.blocksTouch(on: .diveScreen))
    }

    func testDiveStartLocksTouch() {
        let controller = DiveLockController()
        controller.onDiveStarted()

        XCTAssertTrue(controller.isLocked)
        XCTAssertEqual(controller.phase, .diving)
        XCTAssertTrue(controller.phase.blocksTouch)
        XCTAssertTrue(controller.blocksTouch(on: .diveScreen))
        XCTAssertTrue(controller.blocksTouch(on: .banner))
    }

    func testAutoLockCanBeDisabled() {
        let controller = DiveLockController()
        controller.autoLockOnDiveStart = false
        controller.onDiveStarted()
        XCTAssertFalse(controller.isLocked, "Otomatik kilit kapalıyken dokunma açık kalmalı")
        XCTAssertEqual(controller.phase, .diving)
    }

    func testDiveEndStartsEjectionSequence() {
        let controller = DiveLockController()
        controller.onDiveStarted()
        let steps = controller.onDiveEnded()

        XCTAssertEqual(controller.phase, .ejecting)
        XCTAssertFalse(controller.isLocked, "Su atarken kullanıcı kolunu çevirebilmeli")
        XCTAssertFalse(steps.isEmpty)
        XCTAssertTrue(steps.allSatisfy { $0.delay > 0 })
    }

    func testEjectionCompletionUnlocks() {
        let controller = DiveLockController()
        controller.onDiveStarted()
        controller.onDiveEnded()
        controller.onEjectionCompleted()

        XCTAssertEqual(controller.phase, .unlocked)
        XCTAssertFalse(controller.isLocked)
    }

    func testManualUnlockAndLock() {
        let controller = DiveLockController()
        controller.onDiveStarted()
        controller.unlock()
        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(controller.phase, .unlocked)

        controller.lock()
        XCTAssertTrue(controller.isLocked)
    }

    func testReset() {
        let controller = DiveLockController()
        controller.onDiveStarted()
        controller.registerPress()
        controller.reset()

        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.pressCount, 0)
    }

    // MARK: - Dokunma politikası

    func testOnlyConfiguredSurfacesAreBlocked() {
        let controller = DiveLockController()
        controller.onDiveStarted()

        XCTAssertTrue(controller.blocksTouch(on: .diveScreen))
        XCTAssertTrue(controller.blocksTouch(on: .banner))
        XCTAssertFalse(controller.blocksTouch(on: .compass),
                       "Varsayılan olarak pusola kilitlenmez")
        XCTAssertFalse(controller.blocksTouch(on: .emergencyMenu))
    }

    func testEmergencyMenuAlwaysAccessible() {
        let controller = DiveLockController()
        controller.onDiveStarted()
        XCTAssertTrue(controller.allowsEmergencyMenu,
                      "Acil durum menüsü su kilidinde bile erişilebilir olmalı")
    }

    func testSurfacesCanBeConfigured() {
        let controller = DiveLockController()
        controller.lockableSurfaces = [.diveScreen]
        controller.onDiveStarted()

        XCTAssertTrue(controller.blocksTouch(on: .diveScreen))
        XCTAssertFalse(controller.blocksTouch(on: .compass))
    }

    func testUnlockedStateDoesNotBlock() {
        let controller = DiveLockController()
        controller.lockableSurfaces = [.emergencyMenu]
        controller.onDiveStarted()
        controller.unlock()
        XCTAssertFalse(controller.blocksTouch(on: .emergencyMenu))
    }

    // MARK: - Action Button

    func testSinglePressStartsDiveOnSurface() {
        let controller = DiveLockController()
        XCTAssertEqual(controller.action(for: .single, isDiving: false, hasCriticalAlarm: false),
                       .startDive)
    }

    func testSinglePressPlacesMarkerWhileDiving() {
        let controller = DiveLockController()
        XCTAssertEqual(controller.action(for: .single, isDiving: true, hasCriticalAlarm: false),
                       .placeMarker)
    }

    func testSinglePressAcknowledgesCriticalAlarm() {
        let controller = DiveLockController()
        XCTAssertEqual(controller.action(for: .single, isDiving: true, hasCriticalAlarm: true),
                       .acknowledgeAlarm)
    }

    func testLongPressOpensEmergencyMenuWhileDiving() {
        let controller = DiveLockController()
        XCTAssertEqual(controller.action(for: .longPress, isDiving: true, hasCriticalAlarm: false),
                       .openEmergencyMenu)
        XCTAssertEqual(controller.action(for: .longPress, isDiving: true, hasCriticalAlarm: true),
                       .openEmergencyMenu,
                       "Acil durum, alarm bastan daha öncelikli")
    }

    func testLongPressOnSurfaceStartsDive() {
        let controller = DiveLockController()
        XCTAssertEqual(controller.action(for: .longPress, isDiving: false, hasCriticalAlarm: false),
                       .startDive)
    }

    func testActionLabelsAndSymbols() {
        XCTAssertEqual(DiveLockController.ButtonAction.placeMarker.label, "İşaret Koy")
        XCTAssertEqual(DiveLockController.ButtonAction.openEmergencyMenu.label, "Acil Durum")
        XCTAssertEqual(DiveLockController.ButtonAction.startSafetyStop.label, "Emniyet Durağı")
        XCTAssertEqual(DiveLockController.ButtonAction.ascentAssist.label, "Çıkış Yardımı")
        XCTAssertTrue(DiveLockController.ButtonAction.endDive.symbolName.contains("stop"))
    }

    func testEmergencyMenuContents() {
        let controller = DiveLockController()
        let guidance = AscentAdvisor().evaluate(DiveState(
            phase: .ascending, currentDepth: 10, maxDepth: 40, diveTime: 2400,
            ascentRate: 2, ceilingDepth: 6, nextStopDepth: 6))

        let actions = controller.emergencyMenu(for: guidance)
        XCTAssertEqual(actions.first, .startSafetyStop)
        XCTAssertTrue(actions.contains(.ascentAssist))
        XCTAssertEqual(actions.last, .endDive)
    }

    func testEmergencyMenuPrioritisesCeilingViolation() {
        let controller = DiveLockController()
        let guidance = AscentAdvisor().evaluate(DiveState(
            phase: .ascending, currentDepth: 4, maxDepth: 40, diveTime: 2400,
            ascentRate: 2, ceilingDepth: 6, nextStopDepth: 6))
        XCTAssertTrue(guidance.isAboveCeiling)

        let actions = controller.emergencyMenu(for: guidance)
        XCTAssertEqual(actions.first, .openEmergencyMenu)
    }

    // MARK: - Su atma döngüsü

    func testStandardEjectionSequence() {
        let controller = DiveLockController()
        let steps = DiveLockController.EjectionStep.standard
        XCTAssertEqual(steps.count, 4)
        XCTAssertGreaterThan(steps.reduce(0) { $0 + $1.delay }, 3.0)
        XCTAssertTrue(steps.allSatisfy { !$0.name.isEmpty })
        XCTAssertTrue(steps.contains { $0.sound == .chirp })
    }

    func testEjectionSequenceIsConfigurable() {
        let controller = DiveLockController()
        controller.ejectionSequence = [DiveLockController.EjectionStep(name: "Tek", delay: 0.5, sound: .click)]
        XCTAssertEqual(controller.onDiveEnded().count, 1)
    }

    func testEjectionGuidanceText() {
        XCTAssertTrue(DiveLockController.ejectionGuidance.contains("çevir"))
    }

    // MARK: - Yönlendirme metinleri

    func testWaterLockGuidanceDependsOnSystemLock() {
        let controller = DiveLockController()
        XCTAssertTrue(controller.waterLockGuidance.contains("Control Center"))
        controller.isSystemWaterLockEnabled = true
        XCTAssertTrue(controller.waterLockGuidance.contains("etkin"))
    }

    // MARK: - Bildirimler

    func testChangeNotifications() {
        let controller = DiveLockController()
        var count = 0
        controller.onChange = { _ in count += 1 }

        controller.onDiveStarted()
        controller.onDiveEnded()
        controller.onEjectionCompleted()
        controller.registerPress()
        XCTAssertGreaterThanOrEqual(count, 4)
    }

    func testPressCounter() {
        let controller = DiveLockController()
        controller.registerPress()
        controller.registerPress()
        XCTAssertEqual(controller.pressCount, 2)
    }

    // MARK: - Entegrasyon

    @MainActor
    func testLockCycleWithRealSession() {
        let controller = DiveLockController()
        let session = DiveSessionController(configuration: .recreational)
        session.start()
        session.ingest(DiveSimulator(scenario: .recreational30m).readings)
        _ = session.end(at: Date(timeIntervalSince1970: 2000))

        controller.onDiveStarted()
        XCTAssertTrue(controller.blocksTouch(on: .diveScreen))

        let steps = controller.onDiveEnded()
        XCTAssertFalse(steps.isEmpty)
        controller.onEjectionCompleted()
        XCTAssertFalse(controller.blocksTouch(on: .diveScreen))
    }

    @MainActor
    func testActionButtonFollowsSessionState() {
        let lock = DiveLockController()
        let session = DiveSessionController(configuration: .recreational)

        XCTAssertEqual(lock.action(for: .single, isDiving: session.isRunning,
                                   hasCriticalAlarm: false), .startDive)

        session.start()
        XCTAssertEqual(lock.action(for: .single, isDiving: session.isRunning,
                                   hasCriticalAlarm: false), .placeMarker)

        let hasCritical = session.state.warnings.contains { $0.severity == .critical }
        XCTAssertEqual(lock.action(for: .single, isDiving: true, hasCriticalAlarm: hasCritical),
                       hasCritical ? .acknowledgeAlarm : .placeMarker)
    }
}