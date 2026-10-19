import XCTest
@testable import DiveCore

/// Alarm politikası: dokunsal/görsel eşleme, cooldown, sessiz mod.
@MainActor
final class AlarmCoordinatorTests: XCTestCase {

    // MARK: - Yardımcı

    private func warning(_ kind: DiveWarning.Kind,
                         _ severity: DiveWarning.Severity,
                         at elapsed: TimeInterval = 100,
                         message: String = "test") -> DiveWarning {
        DiveWarning(kind: kind, severity: severity, message: message, raisedAtElapsed: elapsed)
    }

    // MARK: - Politika eşlemesi

    func testSeverityToFeedbackMapping() {
        let info = AlarmCoordinator.policy(for: .info, silent: false, fullScreen: true)
        XCTAssertEqual(info.0, .notification)
        XCTAssertEqual(info.1, .none)

        let caution = AlarmCoordinator.policy(for: .caution, silent: false, fullScreen: true)
        XCTAssertEqual(caution.1, .subtle)

        let warning = AlarmCoordinator.policy(for: .warning, silent: false, fullScreen: true)
        XCTAssertEqual(warning.0, .notification)
        XCTAssertEqual(warning.1, .prominent)

        let critical = AlarmCoordinator.policy(for: .critical, silent: false, fullScreen: true)
        XCTAssertEqual(critical.0, .critical)
        XCTAssertEqual(critical.1, .fullScreenAlert)
    }

    func testSilentModeDisablesHaptics() {
        for severity in [DiveWarning.Severity.info, .caution, .warning, .critical] {
            let (feedback, _) = AlarmCoordinator.policy(for: severity, silent: true, fullScreen: true)
            XCTAssertEqual(feedback, .none, "\(severity) sessiz modda titreşim üretmemeli")
        }
    }

    func testFullScreenCanBeDisabled() {
        let critical = AlarmCoordinator.policy(for: .critical, silent: false, fullScreen: false)
        XCTAssertEqual(critical.1, .prominent)
    }

    func testRepeatIntervalsShrinkWithSeverity() {
        // Ciddi alarm daha sık tekrarlanır
        XCTAssertEqual(AlarmCoordinator.repeatInterval(for: .info), 0)
        XCTAssertLessThan(AlarmCoordinator.repeatInterval(for: .critical),
                          AlarmCoordinator.repeatInterval(for: .warning))
        XCTAssertLessThan(AlarmCoordinator.repeatInterval(for: .warning),
                          AlarmCoordinator.repeatInterval(for: .caution))
    }

    func testKindMapping() {
        XCTAssertEqual(AlarmCoordinator.kind(for: .critical), AlarmKind.critical)
        XCTAssertEqual(AlarmCoordinator.kind(for: .info), AlarmKind.info)
    }

    // MARK: - Eylem üretimi

    func testFirstWarningAlwaysFires() {
        var coordinator = AlarmCoordinator(cooldown: 10)
        let actions = coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 100)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.kind, .critical)
        XCTAssertEqual(actions.first?.feedback, .critical)
        XCTAssertEqual(actions.first?.sourceWarning, DiveWarning.Kind.fastAscent)
    }

    func testCooldownPreventsImmediateRepeat() {
        var coordinator = AlarmCoordinator(cooldown: 10)
        XCTAssertEqual(coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 100).count, 1)
        XCTAssertEqual(coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 105).count, 0)
        XCTAssertEqual(coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 111).count, 1)
    }

    func testCooldownIsPerWarningKind() {
        var coordinator = AlarmCoordinator(cooldown: 100)
        coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 100)
        // Farklı tür hemen çalabilir
        let actions = coordinator.actions(for: [warning(.cnsLimit, .warning)], elapsed: 105)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.sourceWarning, DiveWarning.Kind.cnsLimit)
    }

    func testActionsAreOrderedBySeverity() {
        var coordinator = AlarmCoordinator(cooldown: 0)
        let actions = coordinator.actions(for: [
            warning(.gasSwitch, .info),
            warning(.cnsLimit, .warning),
            warning(.fastAscent, .critical)
        ], elapsed: 100)
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.map(\.kind), [.critical, .warning, .info])
    }

    func testCriticalStateIsTracked() {
        var coordinator = AlarmCoordinator()
        coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 100)
        XCTAssertTrue(coordinator.isCriticalActive)

        coordinator.actions(for: [], elapsed: 200)
        XCTAssertFalse(coordinator.isCriticalActive)
    }

    func testResetClearsHistory() {
        var coordinator = AlarmCoordinator(cooldown: 100)
        coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 100)
        coordinator.reset()
        XCTAssertEqual(coordinator.actions(for: [warning(.fastAscent, .critical)], elapsed: 110).count, 1)
    }

    func testNoWarningsNoActions() {
        var coordinator = AlarmCoordinator()
        XCTAssertTrue(coordinator.actions(for: [], elapsed: 100).isEmpty)
    }

    // MARK: - HapticEngine (sahte)

    func testRecordingHapticEngineCapturesActions() {
        let engine = RecordingHapticEngine()
        let action = AlarmAction(kind: .critical, feedback: .critical,
                                 visualLevel: .fullScreenAlert, message: "Hızlı çıkış!")

        engine.perform([action, action])
        engine.tapFeedback()
        engine.acknowledge()

        XCTAssertEqual(engine.performed.count, 2)
        XCTAssertEqual(engine.totalFeedbackCount, 2)
        XCTAssertEqual(engine.tapCount, 1)
        XCTAssertEqual(engine.acknowledgeCount, 1)

        engine.reset()
        XCTAssertTrue(engine.performed.isEmpty)
        XCTAssertEqual(engine.tapCount, 0)
    }

    func testSilentAlarmsAreNotCountedAsHapticFeedback() {
        let engine = RecordingHapticEngine()
        engine.perform([AlarmAction(kind: .info, feedback: .none,
                                    visualLevel: .none, message: "bilgi")])
        XCTAssertEqual(engine.totalFeedbackCount, 0)
        XCTAssertEqual(engine.performed.count, 1)
    }

    // MARK: - Kodlama

    func testAlarmActionCodableRoundTrip() throws {
        let action = AlarmAction(kind: .warning, feedback: .notification,
                                 visualLevel: .prominent, message: "CNS %80",
                                 repeatAfter: 15, sourceWarning: .cnsLimit)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AlarmAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }
}