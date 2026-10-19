import XCTest
@testable import DiveCore

/// Sunum katmanı: ekranda ne gösterileceğinin kararı (AOD dâhil).
final class DiveDisplayTests: XCTestCase {

    // MARK: - Yardımcı

    private func makeState(depth: Double = 0,
                           maxDepth: Double = 0,
                           diveTime: TimeInterval = 0,
                           phase: DivePhase = .bottom,
                           warnings: [DiveWarning] = [],
                           ndl: TimeInterval = 0,
                           ceiling: Double = 0,
                           nextStop: Double? = nil,
                           ascentRate: Double = 0,
                           heading: Double? = nil,
                           temperature: Double = 20,
                           gf99: Double = 85) -> DiveState {
        DiveState(
            phase: phase,
            currentDepth: depth, maxDepth: maxDepth,
            diveTime: diveTime, waterTemperature: temperature,
            ascentRate: ascentRate, heading: heading,
            gas: .ean32, gases: [.air, .ean32], gasIndex: 1,
            oxygenPartialPressure: 1.26, maximumOperatingDepth: 33,
            noDecompressionLimit: ndl, ceilingDepth: ceiling,
            nextStopDepth: nextStop, timeToSurface: 420,
            gf99: gf99, gradientFactors: .conservative,
            cnsPercent: 24, otuUnits: 18, otuPercent: 22,
            safetyStop: SafetyStopState(), ascentRateStatus: .safe,
            warnings: warnings,
            desaturationRemaining: 5400, noFlyTime: 7200)
    }

    // MARK: - Ekran modu

    func testScreenModeMapping() {
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .preDive)), .preDive)
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .surfaced)), .surfaced)
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .ended)), .summary)
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .safetyStop)), .safetyStop)
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .decoStop)), .decoObligation)
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .bottom)), .diving)
        // Tavan varsa dalış modu bile deko moduna geçer
        XCTAssertEqual(DiveDisplayBuilder.screenMode(for: makeState(phase: .bottom, ceiling: 3)),
                       .decoObligation)
    }

    // MARK: - Temel metinler

    func testCoreReadouts() {
        let state = makeState(depth: 24.63, maxDepth: 30.2, diveTime: 1471,
                              ndl: 760, temperature: 18.4)
        let display = DiveDisplayBuilder.build(from: state)

        XCTAssertEqual(display.depthText, "24.6")
        XCTAssertEqual(display.depthUnit, "m")
        XCTAssertEqual(display.maxDepthText, "30.2")
        XCTAssertEqual(display.diveTimeText, "24:31")
        XCTAssertEqual(display.ndlText, "12:40")
        XCTAssertTrue(display.hasNdl)
        XCTAssertEqual(display.temperatureText, "18°C")
        XCTAssertEqual(display.gasLabel, "EAN32")
        XCTAssertEqual(display.phaseText, "Dipte")
    }

    func testNdlDashWhenNoNdl() {
        let display = DiveDisplayBuilder.build(from: makeState(ndl: 0, ceiling: 3))
        XCTAssertFalse(display.hasNdl)
        XCTAssertEqual(display.ndlText, "—")
    }

    // MARK: - Dekompresyon göstergesi

    func testDecoIndicatorWithoutObligation() {
        let deco = DecoIndicator(state: makeState(ndl: 600))
        XCTAssertFalse(deco.hasObligation)
        XCTAssertEqual(deco.ceilingText, "—")
        XCTAssertEqual(deco.nextStopText, "—")
        XCTAssertEqual(deco.ttsText, "07:00")
    }

    func testDecoIndicatorWithObligation() {
        let deco = DecoIndicator(state: makeState(ceiling: 3.2, nextStop: 3, gf99: 112))
        XCTAssertTrue(deco.hasObligation)
        XCTAssertEqual(deco.ceilingText, "3.2")
        XCTAssertEqual(deco.nextStopText, "3 m")
        XCTAssertEqual(deco.gf99, 112)
        XCTAssertEqual(deco.gf99Text, "112%")
    }

    func testNdlColorEscalates() {
        let safe = DiveDisplayBuilder.build(from: makeState(ndl: 1200))
        XCTAssertEqual(safe.ndlColorRole, .safe)

        let caution = DiveDisplayBuilder.build(from: makeState(ndl: 280))
        XCTAssertEqual(caution.ndlColorRole, .caution)

        let danger = DiveDisplayBuilder.build(from: makeState(ndl: 90))
        XCTAssertEqual(danger.ndlColorRole, .danger)

        let deco = DiveDisplayBuilder.build(from: makeState(ceiling: 3))
        XCTAssertEqual(deco.ndlColorRole, .deco)
    }

    func testCeilingViolationOverridesColor() {
        let state = makeState(warnings: [
            DiveWarning(kind: .ceilingViolation, severity: .critical,
                        message: "Tavan ihlali", raisedAtElapsed: 100)
        ], ndl: 900, ceiling: 5)
        XCTAssertEqual(DiveDisplayBuilder.build(from: state).ndlColorRole, .danger)
    }

    // MARK: - Derinlik göstergesi

    func testDepthIndicatorScaling() {
        let indicator = DepthIndicator(depth: 30, maxDepth: 40)
        XCTAssertEqual(indicator.scaleDepth, 50, accuracy: 0.001)   // maxDepth * 1.25
        XCTAssertEqual(indicator.fraction, 0.6, accuracy: 0.001)
        XCTAssertEqual(indicator.maxFraction, 0.8, accuracy: 0.001)
    }

    func testDepthIndicatorMinimumScale() {
        let shallow = DepthIndicator(depth: 3, maxDepth: 4)
        XCTAssertEqual(shallow.scaleDepth, 10, accuracy: 0.001)
        XCTAssertEqual(shallow.fraction, 0.3, accuracy: 0.001)
    }

    func testDepthIndicatorClampsAtOne() {
        // Ölçek maxDepth * 1.25 olduğu için %100 dolgu ancak çok derin
        // dalışlarda ulaşılır; ölçeği aşan değerler 1'e kırpılır.
        let normal = DepthIndicator(depth: 100, maxDepth: 100)
        XCTAssertEqual(normal.fraction, 0.8, accuracy: 0.001)

        let overflow = DepthIndicator(depth: 500, maxDepth: 500)
        XCTAssertEqual(overflow.fraction, 0.8, accuracy: 0.001)
        XCTAssertEqual(DepthIndicator(depth: 5, maxDepth: 500).fraction, 0.008, accuracy: 0.001)
    }

    // MARK: - Çıkış hızı göstergesi

    func testAscentRateIndicatorLevels() {
        XCTAssertEqual(AscentRateIndicator(rate: 3, depth: 20).level, .safe)
        XCTAssertEqual(AscentRateIndicator(rate: 8, depth: 20).level, .caution)
        XCTAssertEqual(AscentRateIndicator(rate: 15, depth: 20).level, .danger)
        XCTAssertEqual(AscentRateIndicator(rate: -10, depth: 20).level, .descending)
        XCTAssertEqual(AscentRateIndicator(rate: 20, depth: 0).level, .surface)
    }

    func testAscentRateIndicatorFillAndText() {
        let indicator = AscentRateIndicator(rate: 9.25, depth: 20)
        XCTAssertEqual(indicator.text, "9.2")
        XCTAssertEqual(indicator.fill, 9.25 / 15, accuracy: 0.001)
        XCTAssertEqual(indicator.aodLabel, "9")
        XCTAssertEqual(indicator.level.colorRole, .caution)

        // 15 m/dk üstü tam dolu
        XCTAssertEqual(AscentRateIndicator(rate: 20, depth: 20).fill, 1.0)
    }

    func testAscentRateAodSymbol() {
        XCTAssertEqual(AscentRateLevel.safe.aodSymbol, "✓")
        XCTAssertEqual(AscentRateLevel.danger.aodSymbol, "▲")
        XCTAssertEqual(AscentRateLevel.descending.aodSymbol, "▼")
        XCTAssertEqual(AscentRateLevel.caution.aodSymbol, "!")
    }

    // MARK: - Pusola

    func testCompassCardinals() {
        // Türkçe: K = Kuzey, D = Doğu, G = Güney, B = Batı
        XCTAssertEqual(CompassIndicator(heading: 0).cardinal, "K")
        XCTAssertEqual(CompassIndicator(heading: 90).cardinal, "D")
        XCTAssertEqual(CompassIndicator(heading: 180).cardinal, "G")
        XCTAssertEqual(CompassIndicator(heading: 270).cardinal, "B")
        XCTAssertEqual(CompassIndicator(heading: 45).cardinal, "KD")
        XCTAssertEqual(CompassIndicator(heading: 225).cardinal, "GB")
        XCTAssertEqual(CompassIndicator(heading: 360).cardinal, "K")   // 360 = 0
    }

    func testCompassWithoutHeading() {
        let compass = CompassIndicator(heading: nil)
        XCTAssertNil(compass.heading)
        XCTAssertEqual(compass.cardinal, "—")
        XCTAssertTrue(compass.needsCalibration)
    }

    func testCompassNormalizesNegativeAngles() {
        let compass = CompassIndicator(heading: -90)
        XCTAssertEqual(compass.normalized, 270, accuracy: 0.001)
        XCTAssertEqual(compass.cardinal, "B")
    }

    func testCompassTickOffset() {
        // Merkezde 0, kenarlarda ±1
        XCTAssertEqual(CompassIndicator.tickOffset(forHeading: 0) ?? 0, 0, accuracy: 0.001)
        let right = CompassIndicator.tickOffset(forHeading: 60) ?? 0
        XCTAssertGreaterThan(right, 0.9)
        // Görüş alanı dışındaki açılar nil
        XCTAssertNil(CompassIndicator.tickOffset(forHeading: 180))
    }

    // MARK: - Emniyet durağı göstergesi

    func testSafetyStopIndicatorStates() {
        let idle = SafetyStopIndicator(state: SafetyStopState())
        XCTAssertFalse(idle.isActive)
        XCTAssertFalse(idle.isComplete)
        XCTAssertEqual(idle.remainingText, "03:00")
        XCTAssertEqual(idle.progress, 0)
        XCTAssertEqual(idle.subtitle, "\(Int(DiveSafetyLimits.safetyStopDepth)) m'ye in")

        var running = SafetyStopState()
        running.isActive = true
        running.accumulated = 90
        let runningIndicator = SafetyStopIndicator(state: running)
        XCTAssertEqual(runningIndicator.remainingText, "01:30")
        XCTAssertEqual(runningIndicator.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(runningIndicator.subtitle, "3 dakika bekle")

        var done = SafetyStopState()
        done.accumulated = 180
        XCTAssertEqual(SafetyStopIndicator(state: done).subtitle, "Tamamlandı ✓")

        var skipped = SafetyStopState()
        skipped.accumulated = 20
        skipped.wasAbandoned = true
        XCTAssertEqual(SafetyStopIndicator(state: skipped).subtitle, "Tamamlanmadı")
    }

    // MARK: - Banner

    func testBannerPicksMostSevereWarning() {
        let banner = DiveBanner.make(from: [
            DiveWarning(kind: .gasSwitch, severity: .info, message: "EAN32", raisedAtElapsed: 1),
            DiveWarning(kind: .cnsLimit, severity: .warning, message: "CNS", raisedAtElapsed: 2),
            DiveWarning(kind: .fastAscent, severity: .critical, message: "Hızlı çıkış", raisedAtElapsed: 3)
        ])
        XCTAssertEqual(banner?.kind, .fastAscent)
        XCTAssertEqual(banner?.title, "HIZLI ÇIKIŞ")
        XCTAssertEqual(banner?.colorRole, .danger)
    }

    func testBannerTitles() {
        func banner(_ kind: DiveWarning.Kind) -> String? {
            DiveBanner.make(from: [DiveWarning(kind: kind, severity: .critical,
                                              message: "x", raisedAtElapsed: 0)])?.title
        }
        XCTAssertEqual(banner(.ceilingViolation), "TAVAN İHLALİ")
        XCTAssertEqual(banner(.noDecoLimitReached), "DEKO ZORUNLU")
        XCTAssertEqual(banner(.cnsLimit), "CNS")
        XCTAssertEqual(banner(.depthExceeded), "MOD AŞIMI")
    }

    func testNoWarningsNoBanner() {
        XCTAssertNil(DiveBanner.make(from: []))
    }

    func testAlarmActiveOnlyForCritical() {
        let warning = DiveWarning(kind: .cnsLimit, severity: .warning, message: "x", raisedAtElapsed: 0)
        XCTAssertFalse(DiveDisplayBuilder.build(from: makeState(warnings: [warning])).isAlarmActive)

        let critical = DiveWarning(kind: .fastAscent, severity: .critical, message: "x", raisedAtElapsed: 0)
        let display = DiveDisplayBuilder.build(from: makeState(warnings: [critical]))
        XCTAssertTrue(display.isAlarmActive)
        XCTAssertEqual(display.backgroundColorRole, .criticalBackground)
    }

    // MARK: - Always-On Display

    func testAlwaysOnModeSimplifiesTypography() {
        let state = makeState(depth: 24, diveTime: 600)
        let active = DiveDisplayBuilder.build(from: state, isAlwaysOn: false)
        let alwaysOn = DiveDisplayBuilder.build(from: state, isAlwaysOn: true)

        XCTAssertFalse(active.isAlwaysOn)
        XCTAssertTrue(alwaysOn.isAlwaysOn)
        XCTAssertEqual(active.depthTextRole, .hero)
        XCTAssertEqual(alwaysOn.depthTextRole, .alwaysOn)
        XCTAssertEqual(active.timeTextRole, .large)
        XCTAssertEqual(alwaysOn.timeTextRole, .alwaysOn)
        // AOD'da da değerler aynıdır (yalnızca sunum sadeleşir)
        XCTAssertEqual(active.depthText, alwaysOn.depthText)
        XCTAssertEqual(active.diveTimeText, alwaysOn.diveTimeText)
    }

    func testAlwaysOnHidesInfoBanner() {
        let info = DiveWarning(kind: .gasSwitch, severity: .info, message: "EAN32", raisedAtElapsed: 1)
        let state = makeState(warnings: [info])

        XCTAssertNotNil(DiveDisplayBuilder.build(from: state, isAlwaysOn: false).banner)
        XCTAssertNil(DiveDisplayBuilder.build(from: state, isAlwaysOn: true).banner,
                     "AOD'da bilgi mesajı gürültü yaratır")
    }

    func testAlwaysOnKeepsCriticalBanner() {
        let critical = DiveWarning(kind: .fastAscent, severity: .critical, message: "HIZLI", raisedAtElapsed: 1)
        let display = DiveDisplayBuilder.build(from: makeState(warnings: [critical]), isAlwaysOn: true)
        XCTAssertNotNil(display.banner)
        XCTAssertTrue(display.isAlarmActive)
    }

    // MARK: - Yüzey / sığ derinlik

    func testSurfaceDepthIsNeutral() {
        let display = DiveDisplayBuilder.build(from: makeState(depth: 0.1))
        XCTAssertEqual(display.depthColorRole, .secondary)

        let deep = DiveDisplayBuilder.build(from: makeState(depth: 12))
        XCTAssertEqual(deep.depthColorRole, .hero)
    }

    // MARK: - Codable

    func testDisplayStateCodableRoundTrip() throws {
        let display = DiveDisplayBuilder.build(from: makeState(depth: 18, maxDepth: 22,
                                                              ndl: 600, ceiling: 3, nextStop: 3,
                                                              ascentRate: 8, heading: 120))
        let data = try JSONEncoder().encode(display)
        let decoded = try JSONDecoder().decode(DiveDisplayState.self, from: data)
        XCTAssertEqual(decoded, display)
    }

    func testCompassCodable() throws {
        let compass = CompassIndicator(heading: 225)
        let data = try JSONEncoder().encode(compass)
        XCTAssertEqual(try JSONDecoder().decode(CompassIndicator.self, from: data), compass)
    }
}