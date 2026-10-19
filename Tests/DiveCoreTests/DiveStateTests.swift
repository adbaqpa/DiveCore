import XCTest
@testable import DiveCore

/// `DiveState` formatlama, emniyet durağı ve uyarı davranışı.
final class DiveStateTests: XCTestCase {

    // MARK: - Faz

    func testPhases() {
        XCTAssertFalse(DivePhase.preDive.isDiving)
        XCTAssertFalse(DivePhase.surfaced.isDiving)
        XCTAssertFalse(DivePhase.ended.isDiving)
        for phase in [DivePhase.descending, .bottom, .ascending, .decoStop, .safetyStop] {
            XCTAssertTrue(phase.isDiving, "\(phase) dalış sürüyor olmalı")
        }
        XCTAssertEqual(DivePhase.decoStop.displayName, "Deko Durağı")
    }

    // MARK: - Çıkış hızı durumu

    func testAscentRateStatusThresholds() {
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 5, depth: 20), .safe)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 7.5, depth: 20), .caution)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 12, depth: 20), .danger)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: -5, depth: 20), .descending)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 12, depth: 0), .surface)
    }

    func testAscentRateStatusBoundaries() {
        // Tam sınırlar: 10 m/dk üstü tehlikeli, 7 m/dk üstü dikkat
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 10.0, depth: 5), .caution)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 10.01, depth: 5), .danger)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 7.0, depth: 5), .safe)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 7.01, depth: 5), .caution)
    }

    func testSurfaceDivesNeverShowAscentAlarm() {
        // Yüzeydeyken yüksek hız okuması alarm üretmemeli
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 30, depth: 0.1), .surface)
    }

    // MARK: - Emniyet durağı

    func testSafetyStopProgress() {
        var stop = SafetyStopState()
        XCTAssertEqual(stop.requiredDuration, 180)
        XCTAssertEqual(stop.remaining, 180)
        XCTAssertEqual(stop.progress, 0)

        stop.accumulated = 90
        XCTAssertEqual(stop.remaining, 90)
        XCTAssertEqual(stop.progress, 0.5, accuracy: 1e-9)
        XCTAssertFalse(stop.isComplete)

        stop.accumulated = 180
        XCTAssertTrue(stop.isComplete)
        XCTAssertEqual(stop.progress, 1.0)
        XCTAssertEqual(stop.remaining, 0)
    }

    func testSafetyStopRemainingFormatted() {
        var stop = SafetyStopState()
        stop.accumulated = 60
        XCTAssertEqual(stop.remainingFormatted, "02:00")
    }

    func testSafetyStopAbandonment() {
        var stop = SafetyStopState(requiredDepth: 5)
        stop.isActive = true
        stop.wasAbandoned = true
        XCTAssertTrue(stop.wasAbandoned)
        XCTAssertEqual(stop.requiredDepth, 5)
    }

    // MARK: - Uyarılar

    func testMostCriticalWarning() {
        let state = DiveState(warnings: [
            DiveWarning(kind: .gasSwitch, severity: .info, message: "EAN32", raisedAtElapsed: 10),
            DiveWarning(kind: .fastAscent, severity: .critical, message: "Çok hızlı çıkıyorsunuz", raisedAtElapsed: 20),
            DiveWarning(kind: .cnsLimit, severity: .warning, message: "CNS %80", raisedAtElapsed: 30)
        ])
        XCTAssertEqual(state.mostCriticalWarning?.kind, .fastAscent)
    }

    func testNoWarningsReturnsNil() {
        XCTAssertNil(DiveState().mostCriticalWarning)
    }

    func testSeverityOrdering() {
        XCTAssertLessThan(DiveWarning.Severity.info, DiveWarning.Severity.critical)
        XCTAssertEqual(DiveWarning.Severity.critical.displayName, "Kritik")
    }

    // MARK: - Türetilmiş durumlar

    func testDecoObligationFlag() {
        let free = DiveState(ceilingDepth: 0)
        let deco = DiveState(ceilingDepth: 4.2)

        XCTAssertFalse(free.requiresDecompression)
        XCTAssertTrue(deco.requiresDecompression)
        XCTAssertEqual(deco.ceilingFormatted, "4.2")
        XCTAssertEqual(free.ceilingFormatted, "—")
    }

    func testComputedAscentRateStatusIgnoresStoredValue() {
        let state = DiveState(currentDepth: 20, ascentRate: 15, ascentRateStatus: .safe)
        XCTAssertEqual(state.computedAscentRateStatus, .danger)
    }

    // MARK: - Formatlama

    func testDurationFormatterClock() {
        XCTAssertEqual(DurationFormatter.clock(0), "00:00")
        XCTAssertEqual(DurationFormatter.clock(59), "00:59")
        XCTAssertEqual(DurationFormatter.clock(90), "01:30")
        XCTAssertEqual(DurationFormatter.clock(3600), "1:00:00")
        XCTAssertEqual(DurationFormatter.clock(3661), "1:01:01")
        XCTAssertEqual(DurationFormatter.clock(-5), "00:00")
    }

    func testDurationFormatterHoursMinutes() {
        XCTAssertEqual(DurationFormatter.hoursMinutes(45 * 60), "45dk")
        XCTAssertEqual(DurationFormatter.hoursMinutes(3 * 3600 + 25 * 60), "3s 25dk")
        XCTAssertEqual(DurationFormatter.hoursMinutes(30), "30s")
    }

    func testStateFormatting() {
        let state = DiveState(
            currentDepth: 24.63, maxDepth: 30.2, diveTime: 1471,
            waterTemperature: 18.4,
            noDecompressionLimit: 760, ceilingDepth: 0, timeToSurface: 224,
            gf99: 61, cnsPercent: 34.2, noFlyTime: 3.0 * 3600 + 25 * 60
        )

        XCTAssertEqual(state.depthFormatted, "24.6")
        XCTAssertEqual(state.maxDepthFormatted, "30.2")
        XCTAssertEqual(state.diveTimeFormatted, "24:31")
        XCTAssertEqual(state.temperatureFormatted, "18.4°C")
        XCTAssertEqual(state.cnsFormatted, "34%")
        XCTAssertEqual(state.gf99Formatted, "61")
        XCTAssertEqual(state.ndlFormatted, "12:40")
        XCTAssertEqual(state.ttsFormatted, "03:44")
        XCTAssertEqual(state.noFlyFormatted, "3s 25dk")
    }

    func testNdlFormattedIsDashWhenNoNdl() {
        XCTAssertEqual(DiveState(noDecompressionLimit: 0).ndlFormatted, "—")
    }

    // MARK: - Codable

    func testDiveStateCodableRoundTrip() throws {
        let state = DiveState(
            phase: .decoStop,
            currentDepth: 12.5, maxDepth: 38.0,
            diveTime: 2400, waterTemperature: 17.2,
            gas: .ean36, gases: [.air, .ean36], gasIndex: 1,
            ceilingDepth: 3.0, nextStopDepth: 3.0,
            gradientFactors: .conservative,
            cnsPercent: 22, otuUnits: 18.4, otuPercent: 23,
            safetyStop: SafetyStopState(accumulated: 120, isActive: true),
            ascentRateStatus: .safe,
            warnings: [DiveWarning(kind: .noDecoLimitReached, severity: .warning,
                                   message: "NDL doldu", raisedAtElapsed: 1200)],
            noFlyTime: 14_400
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DiveState.self, from: data)

        XCTAssertEqual(decoded.phase, DivePhase.decoStop)
        XCTAssertEqual(decoded.currentDepth, state.currentDepth)
        XCTAssertEqual(decoded.gas, GasMix.ean36)
        XCTAssertEqual(decoded.gases.count, 2)
        XCTAssertEqual(decoded.gradientFactors, GradientFactors.conservative)
        XCTAssertEqual(decoded.safetyStop, state.safetyStop)
        XCTAssertEqual(decoded.warnings.count, 1)
        XCTAssertEqual(decoded.noFlyTime, 14_400)
    }

    func testDefaultStateIsSane() {
        let state = DiveState()
        XCTAssertEqual(state.phase, .preDive)
        XCTAssertEqual(state.currentDepth, 0)
        XCTAssertEqual(state.ambientPressure, 1.0)
        XCTAssertEqual(state.gas, .air)
        XCTAssertEqual(state.gases.count, 1)
        XCTAssertFalse(state.isDiving)
        XCTAssertFalse(state.hasDecoObligation)
    }
}