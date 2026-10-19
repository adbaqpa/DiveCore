import XCTest
@testable import DiveCore

/// ADIM 11 — Pil optimizasyonu: tema (OLED), enerji bütçesi ve dinamik örnekleme.
final class EnergyOptimizationTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcılar

    private func divingState(depth: Double = 24, rate: Double = 0,
                             ceiling: Double = 0, ndl: TimeInterval = 600) -> DiveState {
        var state = DiveState()
        state.phase = .bottom
        state.currentDepth = depth
        state.maxDepth = max(depth, 30)
        state.diveTime = 900
        state.ascentRate = rate
        state.ceilingDepth = ceiling
        state.noDecompressionLimit = ndl
        return state
    }

    // MARK: - DiveRGB

    func testPerceivedBrightnessOrdering() {
        XCTAssertEqual(DiveRGB.off.perceivedBrightness, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(DiveRGB(red: 1, green: 1, blue: 1).perceivedBrightness,
                             DiveRGB(red: 1, green: 0, blue: 0).perceivedBrightness)
        XCTAssertGreaterThan(DiveRGB(red: 0, green: 1, blue: 0).perceivedBrightness,
                             DiveRGB(red: 1, green: 0, blue: 0).perceivedBrightness)
    }

    func testBlueIsMostExpensiveOnOled() {
        let red = DiveRGB(red: 1, green: 0, blue: 0).oledCost
        let green = DiveRGB(red: 0, green: 1, blue: 0).oledCost
        let blue = DiveRGB(red: 0, green: 0, blue: 1).oledCost
        XCTAssertLessThan(red, green)
        XCTAssertLessThan(green, blue, "Mavi alt piksel en pahalıdır")
    }

    func testBlackIsFreeAndWhiteIsMostExpensive() {
        XCTAssertEqual(DiveRGB.off.oledCost, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(DiveRGB.fullWhite.oledCost, 4)
    }

    func testChannelsAreClamped() {
        let color = DiveRGB(red: 2, green: -1, blue: 0.5)
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 0)
        XCTAssertEqual(color.blue, 0.5)
    }

    func testDimmingPreservesHue() {
        let dimmed = DiveRGB(red: 1, green: 1, blue: 1).dimmed
        XCTAssertLessThan(dimmed.green, dimmed.red)
        XCTAssertLessThan(dimmed.blue, dimmed.red)
    }

    // MARK: - Temalar

    func testAllThemesHaveSpecs() {
        for theme in DiveDisplayTheme.allCases {
            let spec = DiveThemeCatalog.spec(for: theme)
            XCTAssertEqual(spec.theme, theme)
            XCTAssertFalse(spec.palette.isEmpty)
            XCTAssertGreaterThan(spec.maximumBrightness, 0)
            XCTAssertFalse(theme.title.isEmpty)
            XCTAssertFalse(theme.detail.isEmpty)
        }
    }

    func testNightThemesHaveBlackBackground() {
        XCTAssertEqual(DiveThemeCatalog.spec(for: .standard).background, DiveRGB(red: 0.02, green: 0.06, blue: 0.10))
        XCTAssertEqual(DiveThemeCatalog.spec(for: .nightShift).background, DiveRGB.off)
        XCTAssertEqual(DiveThemeCatalog.spec(for: .alwaysOnRed).background, DiveRGB.off)
    }

    func testNightPalettesAreRedDominant() {
        for theme in [DiveDisplayTheme.nightShift, .alwaysOnRed] {
            let spec = DiveThemeCatalog.spec(for: theme)
            for (role, color) in spec.palette {
                XCTAssertTrue(color.isRedDominant,
                              "\(theme) / \(role) kırmızı tonda olmalı")
            }
        }
    }

    func testStandardPaletteIsNotRedDominant() {
        let spec = DiveThemeCatalog.spec(for: .standard)
        XCTAssertFalse(spec.color(for: .accent).isRedDominant)
        XCTAssertFalse(spec.color(for: .safe).isRedDominant)
    }

    func testNightModeSavesPower() {
        let standard = DiveThemeCatalog.spec(for: .standard).estimatedPower()
        let night = DiveThemeCatalog.spec(for: .nightShift).estimatedPower()
        let aod = DiveThemeCatalog.spec(for: .alwaysOnRed).estimatedPower()
        XCTAssertLessThan(night, standard, "Kırmızı mod OLED gücünü düşürmeli")
        XCTAssertLessThan(aod, night, "AOD kırmızı en düşük güçte olmalı")
    }

    func testAodRedIsLowestPowerOverall() {
        let aod = DiveThemeCatalog.spec(for: .alwaysOnRed)
        let standard = DiveThemeCatalog.spec(for: .standard)
        XCTAssertLessThan(aod.estimatedPower(), standard.estimatedPower())
    }

    func testAlwaysOnRedHidesDetails() {
        let aod = DiveThemeCatalog.spec(for: .alwaysOnRed)
        XCTAssertFalse(aod.showsSeconds)
        XCTAssertFalse(aod.showsSecondaryDetails)
        XCTAssertFalse(aod.showsInfoBanner)
        XCTAssertTrue(DiveThemeCatalog.spec(for: .standard).showsSeconds)
    }

    func testOnlyStandardAndNightAreUserSelectable() {
        XCTAssertTrue(DiveDisplayTheme.standard.isUserSelectable)
        XCTAssertTrue(DiveDisplayTheme.nightShift.isUserSelectable)
        XCTAssertFalse(DiveDisplayTheme.alwaysOnRed.isUserSelectable)
    }

    // MARK: - Tema çözümleme

    func testAlwaysOnForcesRedTheme() {
        let state = EnergyState(isAlwaysOn: true, isDiving: true)
        for preference in EnergyManager.NightModePreference.allCases {
            XCTAssertEqual(
                EnergyManager.resolveTheme(state: state, preference: preference),
                .alwaysOnRed,
                "AOD'da tema zorunlu olarak kırmızı olmalı")
        }
    }

    func testForcedPreferenceAlwaysNight() {
        let state = EnergyState(batteryLevel: 1.0, theme: .standard)
        XCTAssertEqual(
            EnergyManager.resolveTheme(state: state, preference: .forced), .nightShift)
    }

    func testOffPreferenceKeepsStandard() {
        let state = EnergyState(batteryLevel: 0.1, isAlwaysOn: false)
        XCTAssertEqual(EnergyManager.resolveTheme(state: state, preference: .off), .standard)
    }

    func testAutoUsesNightWhenBatteryLow() {
        let state = EnergyState(batteryLevel: 0.2, isAlwaysOn: false)
        let noon = base.addingTimeInterval(12 * 3600)
        XCTAssertEqual(
            EnergyManager.resolveTheme(state: state, preference: .auto, now: noon),
            .nightShift, "Pil %20 iken gündüz de kırmızı mod")
    }

    func testAutoUsesNightAtNightHours() {
        let state = EnergyState(batteryLevel: 1.0, isAlwaysOn: false)
        var components = DateComponents()
        components.year = 2023
        components.month = 11
        components.day = 15
        components.hour = 23
        let late = Calendar.current.date(from: components)!
        XCTAssertEqual(
            EnergyManager.resolveTheme(state: state, preference: .auto, now: late),
            .nightShift)
    }

    func testAutoKeepsStandardInDaytimeWithFullBattery() {
        let state = EnergyState(batteryLevel: 0.95, isAlwaysOn: false)
        var components = DateComponents()
        components.year = 2023
        components.month = 11
        components.day = 15
        components.hour = 13
        let noon = Calendar.current.date(from: components)!
        XCTAssertEqual(
            EnergyManager.resolveTheme(state: state, preference: .auto, now: noon),
            .standard)
    }

    // MARK: - Enerji durumu

    func testBatteryHelpers() {
        let empty = EnergyState(batteryLevel: 0.10)
        XCTAssertTrue(empty.isBatteryCritical)
        XCTAssertTrue(empty.isBatteryLow)
        XCTAssertTrue(empty.shouldConserve)
        XCTAssertEqual(empty.batteryPercent, 10)

        let full = EnergyState(batteryLevel: 1.0)
        XCTAssertFalse(full.isBatteryCritical)
        XCTAssertFalse(full.shouldConserve)
        XCTAssertEqual(full.batteryPercent, 100)
    }

    func testUnknownBatteryIsNotCritical() {
        let unknown = EnergyState(batteryLevel: nil)
        XCTAssertTrue(unknown.isBatteryUnknown)
        XCTAssertFalse(unknown.isBatteryCritical)
        XCTAssertFalse(unknown.shouldConserve)
        XCTAssertEqual(unknown.batteryPercent, 100)
    }

    func testThermalConstraints() {
        let nominal = EnergyState(thermalState: .nominal)
        let serious = EnergyState(thermalState: .serious)
        let critical = EnergyState(thermalState: .critical)
        XCTAssertFalse(nominal.isThermallyConstrained)
        XCTAssertTrue(serious.isThermallyConstrained)
        XCTAssertTrue(critical.isThermallyConstrained)
        XCTAssertTrue(critical.shouldConserve)
    }

    func testThermalStateOrdering() {
        XCTAssertLessThan(EnergyState.ThermalState.nominal, EnergyState.ThermalState.fair)
        XCTAssertLessThan(EnergyState.ThermalState.fair, EnergyState.ThermalState.serious)
        XCTAssertLessThan(EnergyState.ThermalState.serious, EnergyState.ThermalState.critical)
    }

    // MARK: - Profiller

    func testProfileBaseIntervals() {
        XCTAssertEqual(PowerProfile.performance.baseInterval, 0.5,
                       "Performans 2 Hz'de çalışır")
        XCTAssertEqual(PowerProfile.balanced.baseInterval, 1)
        XCTAssertGreaterThan(PowerProfile.saver.baseInterval,
                             PowerProfile.balanced.baseInterval)
    }

    /// `ascentRate` işareti: pozitif = **yukarı** (dalış bilgisayarı geleneği).
    /// Yanlış işaret, hızlı inişi "hızlı çıkış" sanıp gerçek çıkışı
    /// seyrekleştirirdi.
    func testAscentRateSignConventionIsUpward() {
        let policy = AdaptiveSamplingPolicy()
        // Yükseliş 12 m/dk → hızlı çıkış
        XCTAssertEqual(policy.decide(context(depth: 10, rate: 12, ndl: 300)).reason,
                       .fastAscent)
        // İniş 15 m/dk (ascentRate negatif) → hızlı çıkış **değil**
        XCTAssertNotEqual(policy.decide(context(depth: 20, rate: -15, ndl: 300)).reason,
                          .fastAscent)
    }

    func testPerformanceProfileConstrainedByThermals() {
        let hot = EnergyState(thermalState: .critical)
        XCTAssertEqual(PowerProfile.performance.constrained(by: hot), .balanced)
    }

    func testPerformanceProfileConstrainedByCriticalBattery() {
        let dying = EnergyState(batteryLevel: 0.05)
        XCTAssertEqual(PowerProfile.performance.constrained(by: dying), .balanced)
    }

    func testPerformanceProfileConstrainedByLowPowerMode() {
        let saver = EnergyState(isLowPowerModeEnabled: true)
        XCTAssertEqual(PowerProfile.performance.constrained(by: saver), .balanced)
    }

    func testSaverProfileIsNeverConstrainedUp() {
        let dying = EnergyState(batteryLevel: 0.02, thermalState: .critical)
        XCTAssertEqual(PowerProfile.saver.constrained(by: dying), .saver)
    }

    // MARK: - Enerji bütçesi

    func testDisplayPowerOrdering() {
        let standard = EnergyBudget.displayMilliwatts(theme: .standard, isAlwaysOn: true)
        let night = EnergyBudget.displayMilliwatts(theme: .nightShift, isAlwaysOn: true)
        let aod = EnergyBudget.displayMilliwatts(theme: .alwaysOnRed, isAlwaysOn: true)
        XCTAssertLessThan(night, standard)
        XCTAssertLessThan(aod, night)
    }

    func testDisplayOffStillRespondsToTheme() {
        // AOD kapalıyken ekran yalnızca kol kaldırıldığında yanar; tema
        // etkisi duty cycle ile ölçeklenir ama sıfır olmaz.
        let off = EnergyBudget.displayMilliwatts(theme: .alwaysOnRed, isAlwaysOn: false)
        let full = EnergyBudget.displayMilliwatts(theme: .standard, isAlwaysOn: false)
        XCTAssertLessThan(off, full)
        XCTAssertGreaterThan(off, EnergyBudget.Component.display.baseMilliwatts)
    }

    func testCoarseSamplingSavesSensorPower() {
        let fast = EnergyBudget.sensorMilliwatts(interval: 1)
        let slow = EnergyBudget.sensorMilliwatts(interval: 5)
        XCTAssertLessThan(slow, fast)
        // Daha kaba örnekleme alt sınıra doğru iner, sıfıra değil
        XCTAssertGreaterThan(slow, 12)
    }

    func testProjectedHoursScalesWithBattery() {
        let half = EnergyBudget.projectedHoursRemaining(batteryLevel: 0.5, milliamps: 100)
        let full = EnergyBudget.projectedHoursRemaining(batteryLevel: 1.0, milliamps: 100)
        XCTAssertEqual(half, full / 2, accuracy: 0.01)
    }

    func testProjectedHoursUnknownBatteryIsInfinite() {
        XCTAssertTrue(EnergyBudget.projectedHoursRemaining(batteryLevel: nil, milliamps: 100)
            .isInfinite)
        XCTAssertTrue(EnergyBudget.projectedHoursRemaining(batteryLevel: 0.5, milliamps: 0)
            .isInfinite)
    }

    func testTotalPowerLowerWithSaverAndNight() {
        let rich = EnergyBudget.totalMilliwatts(theme: .standard, isAlwaysOn: true,
                                                samplingInterval: 0.5, isDiving: true)
        let poor = EnergyBudget.totalMilliwatts(theme: .alwaysOnRed, isAlwaysOn: true,
                                                samplingInterval: 5, isDiving: true)
        XCTAssertLessThan(poor, rich)
    }

    func testNotDivingCostsMuchLess() {
        let diving = EnergyBudget.totalMilliwatts(theme: .standard, isAlwaysOn: false,
                                                  samplingInterval: 1, isDiving: true)
        let idle = EnergyBudget.totalMilliwatts(theme: .standard, isAlwaysOn: false,
                                                samplingInterval: 1, isDiving: false)
        XCTAssertLessThan(idle, diving)
    }

    // MARK: - EnergyManager

    func testManagerResolvesThemeAndProfile() {
        var manager = EnergyManager(
            state: EnergyState(batteryLevel: 0.8, isDiving: true, profile: .balanced),
            nightModePreference: .auto)
        XCTAssertEqual(manager.profile, .balanced)

        manager.setPowerProfileForTest(.performance)
        XCTAssertEqual(manager.profile, .performance)

        manager.update(state: EnergyState(batteryLevel: 0.8, isDiving: true,
                                          profile: .performance))
        XCTAssertEqual(manager.profile, .performance)
    }

    func testManagerDowngradesProfileOnThermal() {
        let manager = EnergyManager(
            state: EnergyState(batteryLevel: 0.9, thermalState: .critical,
                               isDiving: true, profile: .performance))
        XCTAssertEqual(manager.profile, .balanced)
    }

    func testManagerIncreasesIntervalOnThermal() {
        let normal = EnergyManager(state: EnergyState(batteryLevel: 0.9, isDiving: true,
                                                      profile: .balanced))
        let hot = EnergyManager(state: EnergyState(batteryLevel: 0.9, thermalState: .serious,
                                                   isDiving: true, profile: .balanced))
        XCTAssertGreaterThan(hot.recommendedInterval, normal.recommendedInterval)
    }

    func testManagerIntervalIsBounded() {
        for battery in [0.0, 0.1, 0.5, 1.0] {
            for thermal in EnergyState.ThermalState.allCases {
                for profile in PowerProfile.allCases {
                    let manager = EnergyManager(state: EnergyState(
                        batteryLevel: battery, thermalState: thermal,
                        isDiving: true, profile: profile))
                    XCTAssertGreaterThanOrEqual(manager.recommendedInterval, 0.1)
                    XCTAssertLessThanOrEqual(manager.recommendedInterval, 10,
                                             "Örnekleme aralığı asla 10 sn'yi geçmemeli")
                }
            }
        }
    }

    func testManagerSummaryText() {
        let manager = EnergyManager(
            state: EnergyState(batteryLevel: 0.55, isDiving: true, profile: .balanced))
        let text = manager.summaryText
        XCTAssertTrue(text.contains("55"))
        XCTAssertTrue(text.contains("Dengeli"))
    }

    func testGuidanceForCriticalBattery() {
        let manager = EnergyManager(state: EnergyState(batteryLevel: 0.08, isDiving: true))
        XCTAssertTrue(manager.guidance.contains { $0.id == "batteryCritical"
            && $0.kind == .critical })
    }

    func testGuidanceForThermal() {
        let manager = EnergyManager(state: EnergyState(batteryLevel: 0.8,
                                                       thermalState: .critical,
                                                       isDiving: true))
        XCTAssertTrue(manager.guidance.contains { $0.id == "thermalCritical" })
    }

    func testGuidanceForAod() {
        let manager = EnergyManager(state: EnergyState(batteryLevel: 0.8, isAlwaysOn: true))
        XCTAssertEqual(manager.theme, .alwaysOnRed)
        XCTAssertTrue(manager.guidance.contains { $0.id == "aodRed" })
    }

    func testNoGuidanceWhenEverythingIsFine() {
        let manager = EnergyManager(state: EnergyState(batteryLevel: 0.95, isDiving: true))
        XCTAssertTrue(manager.guidance.isEmpty)
    }

    // MARK: - Örnekleme politikası

    private func context(depth: Double = 24, rate: Double = 0, ceiling: Double = 0,
                         ndl: TimeInterval = 600, isDiving: Bool = true,
                         critical: Bool = false) -> AdaptiveSamplingPolicy.Context {
        AdaptiveSamplingPolicy.Context(isDiving: isDiving, depth: depth,
                                       ascentRate: rate, ceilingDepth: ceiling,
                                       ndl: ndl, hasCriticalWarning: critical)
    }

    func testFastAscentTriggersFastSampling() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(depth: 12, rate: 14, ndl: 300))
        XCTAssertEqual(decision.reason, .fastAscent)
        XCTAssertLessThanOrEqual(decision.interval, 0.5)
    }

    func testCriticalWarningTriggersFastestSampling() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(depth: 24, critical: true))
        XCTAssertEqual(decision.reason, .criticalAlarm)
        XCTAssertEqual(decision.interval, policy.safetyInterval)
    }

    func testDecompressionStopUsesBaseIntervalWhenStationary() {
        let policy = AdaptiveSamplingPolicy()
        // Durağın 3 m üstünde, hareketsiz: gaz yükü yavaş değişiyor.
        let stop = policy.decide(context(depth: 6, rate: 0, ceiling: 3, ndl: 0))
        XCTAssertEqual(stop.reason, .decompressionObligation)
        XCTAssertEqual(stop.interval, policy.baseInterval)
    }

    func testDecompressionObligationSpeedsUpWhenRising() {
        let policy = AdaptiveSamplingPolicy()
        // Durağa doğru yükselirken hızlı örnekleme gerekir.
        let rising = policy.decide(context(depth: 8, rate: 5, ceiling: 3, ndl: 0))
        XCTAssertEqual(rising.reason, .decompressionObligation)
        XCTAssertLessThanOrEqual(rising.interval, 0.5)
    }

    func testNearCeilingIsFastSampled() {
        let policy = AdaptiveSamplingPolicy()
        // Tavanın 1 m üstünde: ihlal riski maksimum.
        let near = policy.decide(context(depth: 4, rate: 0, ceiling: 3, ndl: 0))
        XCTAssertEqual(near.reason, .ceilingViolationRisk)
        XCTAssertLessThanOrEqual(near.interval, 0.5)
    }

    func testNdlZeroTriggersObligation() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(depth: 24, ceiling: 0, ndl: 0))
        XCTAssertEqual(decision.reason, .decompressionObligation)
    }

    func testActiveMovementUsesBaseInterval() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(depth: 18, rate: 5))
        XCTAssertEqual(decision.reason, .activeMovement)
        XCTAssertEqual(decision.interval, policy.baseInterval)
    }

    func testBottomIdleUsesLongerInterval() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(depth: 30, rate: 0))
        XCTAssertEqual(decision.reason, .bottomIdle)
        XCTAssertGreaterThan(decision.interval, policy.baseInterval)
    }

    func testSurfaceWaitInsideDiveUsesSurfaceInterval() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(depth: 0.2, rate: 0, ceiling: 0, ndl: 300))
        XCTAssertEqual(decision.reason, .surfaceWait)
        XCTAssertGreaterThan(decision.interval, policy.idleInterval)
    }

    func testNotDivingUsesLongestInterval() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(context(isDiving: false))
        XCTAssertEqual(decision.reason, .notDiving)
        XCTAssertEqual(decision.interval, policy.idleDiveInterval)
    }

    func testSafetyIntervalsNeverExceedOneSecond() {
        for profile in PowerProfile.allCases {
            let policy = AdaptiveSamplingPolicy(profile: profile,
                                               state: EnergyState(isDiving: true))
            for critical in [context(depth: 24, critical: true),
                             context(depth: 5, rate: 20, ndl: 0),
                             context(depth: 4, ceiling: 3, ndl: 0),
                             context(depth: 3.2, ceiling: 3, ndl: 0)] {
                let decision = policy.decide(critical)
                XCTAssertLessThanOrEqual(decision.interval, 1.0,
                                         "Güvenlik durumunda örnekleme 1 sn'yi geçmemeli")
            }
        }
    }

    func testNonDivingNeverTriggersSafetyReasons() {
        let policy = AdaptiveSamplingPolicy()
        let decision = policy.decide(
            context(ceiling: 3, ndl: 0, isDiving: false, critical: true))
        XCTAssertEqual(decision.reason, .notDiving)
    }

    func testProfileIntervalsAreOrdered() {
        let performance = AdaptiveSamplingPolicy(profile: .performance, state: EnergyState())
        let balanced = AdaptiveSamplingPolicy(profile: .balanced, state: EnergyState())
        let saver = AdaptiveSamplingPolicy(profile: .saver, state: EnergyState())

        XCTAssertLessThan(performance.baseInterval, balanced.baseInterval)
        XCTAssertLessThan(balanced.baseInterval, saver.baseInterval)
        XCTAssertLessThan(performance.maximumInterval, saver.maximumInterval)
    }

    func testEnergyAdjustmentStretchesBaseButNotSafety() {
        var policy = AdaptiveSamplingPolicy(profile: .performance, state: EnergyState())
        let originalSafety = policy.safetyInterval
        policy = policy.adjusted(for: EnergyState(thermalState: .critical))
        XCTAssertGreaterThanOrEqual(policy.baseInterval, 1.0)
        XCTAssertEqual(policy.safetyInterval, originalSafety,
                       "Güvenlik aralığı asla gevşememeli")
    }

    func testLowBatteryForcesSlowerBase() {
        let policy = AdaptiveSamplingPolicy(profile: .performance, state: EnergyState())
            .adjusted(for: EnergyState(batteryLevel: 0.15))
        XCTAssertGreaterThanOrEqual(policy.baseInterval, 1.0)
    }

    func testSafetyCriticalDetection() {
        let policy = AdaptiveSamplingPolicy()
        XCTAssertTrue(policy.isSafetyCritical(context(depth: 6, ceiling: 3, ndl: 0)))
        XCTAssertTrue(policy.isSafetyCritical(context(depth: 24, critical: true)))
        XCTAssertFalse(policy.isSafetyCritical(context(depth: 30, rate: 0, ndl: 600)))
        XCTAssertFalse(policy.isSafetyCritical(context(isDiving: false)))
    }

    // MARK: - Uyarı bekleme süresi

    /// Dalış başındaki tek bir hızlı çıkış, kalan dalışı yüksek örnekleme
    /// hapsinde tutmamalıdır.
    func testTransientWarningExpiresAfterCooldown() {
        var state = divingState()
        state.diveTime = 1000
        state.warnings = [DiveWarning(kind: .fastAscent, severity: .critical,
                                      message: "Hızlı çıkış", raisedAtElapsed: 1000)]
        let fresh = AdaptiveSamplingPolicy.Context(state: state, transientWarningCooldown: 120)
        XCTAssertTrue(fresh.hasCriticalWarning)

        state.diveTime = 1300   // 300 sn sonra
        let stale = AdaptiveSamplingPolicy.Context(state: state, transientWarningCooldown: 120)
        XCTAssertFalse(stale.hasCriticalWarning, "Geçici ihlal süresi doldu")
    }

    func testStateBasedWarningNeverExpires() {
        var state = divingState()
        state.diveTime = 5000
        state.ceilingDepth = 0
        state.noDecompressionLimit = 0
        state.warnings = [DiveWarning(kind: .noDecoLimitReached, severity: .critical,
                                      message: "NDL doldu", raisedAtElapsed: 200)]
        let context = AdaptiveSamplingPolicy.Context(state: state, transientWarningCooldown: 60)
        XCTAssertTrue(context.hasCriticalWarning, "Durum uyarısı kalıcıdır")
    }

    func testContextFromDiveState() {
        let state = divingState(depth: 18, rate: -3, ceiling: 3, ndl: 0)
        let context = AdaptiveSamplingPolicy.Context(state: state)
        XCTAssertTrue(context.isDiving)
        XCTAssertEqual(context.depth, 18)
        XCTAssertEqual(context.ceilingDepth, 3)
    }

    // MARK: - AdaptiveSampler

    func testSamplerStartsWithFirstReading() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy())
        XCTAssertTrue(sampler.shouldProcess(context: context(depth: 10), elapsed: 0))
    }

    func testSamplerSkipsRedundantReadings() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy(profile: .saver,
                                                                       state: EnergyState()))
        _ = sampler.shouldProcess(context: context(depth: 30), elapsed: 0)
        // Aralık dolmadan ve derinlik değişmeden → atlanır
        XCTAssertFalse(sampler.shouldProcess(context: context(depth: 30.05), elapsed: 0.5))
        XCTAssertTrue(sampler.shouldProcess(context: context(depth: 30.05), elapsed: 5))
    }

    func testSamplerProcessesLargeDepthJumps() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy(profile: .saver,
                                                                       state: EnergyState()))
        _ = sampler.shouldProcess(context: context(depth: 5), elapsed: 0)
        XCTAssertTrue(sampler.shouldProcess(context: context(depth: 18), elapsed: 0.2),
                      "Ani derinlik değişimi atlanmamalı")
    }

    func testSamplerAlwaysProcessesInSafety() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy(profile: .saver,
                                                                       state: EnergyState()))
        _ = sampler.shouldProcess(context: context(depth: 5, ceiling: 3, ndl: 0), elapsed: 0)
        for step in 1...5 {
            XCTAssertTrue(sampler.shouldProcess(context: context(depth: 5, ceiling: 3, ndl: 0),
                                                elapsed: Double(step) * 0.1))
        }
    }

    func testSamplerSwitchesImmediatelyToSafety() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy(profile: .saver,
                                                                       state: EnergyState()))
        let idle = sampler.update(context: context(depth: 30), elapsed: 0)
        XCTAssertEqual(idle.reason, .bottomIdle)

        // Deko yükümlülüğü başlar — beklemeden uygulanır
        let obligation = sampler.update(context: context(depth: 6, ceiling: 3, ndl: 0),
                                        elapsed: 1)
        XCTAssertEqual(obligation.reason, .decompressionObligation)
        XCTAssertEqual(obligation.interval,
                       AdaptiveSamplingPolicy(profile: .saver, state: EnergyState()).baseInterval)

        // Tavana yaklaşınca güvenlik aralığına düşer
        let safety = sampler.update(context: context(depth: 3.4, ceiling: 3, ndl: 0), elapsed: 2)
        XCTAssertEqual(safety.reason, .ceilingViolationRisk)
        XCTAssertLessThanOrEqual(safety.interval, 0.5)
    }

    func testSamplerExitsSafetyImmediately() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy(profile: .saver,
                                                                       state: EnergyState()))
        _ = sampler.update(context: context(depth: 6, ceiling: 3, ndl: 0), elapsed: 0)
        let back = sampler.update(context: context(depth: 30), elapsed: 1)
        XCTAssertNotEqual(back.reason, .decompressionObligation)
    }

    func testSamplerCountsChanges() {
        var sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy(profile: .saver,
                                                                       state: EnergyState()))
        _ = sampler.update(context: context(depth: 30), elapsed: 0)
        let before = sampler.changeCount
        _ = sampler.update(context: context(depth: 6, ceiling: 3, ndl: 0), elapsed: 1)
        XCTAssertGreaterThan(sampler.changeCount, before)
    }

    func testSamplerHonoursEnergyState() {
        var sampler = AdaptiveSampler(profile: .performance,
                                      state: EnergyState(batteryLevel: 1.0))
        let normal = sampler.update(context: context(depth: 30), elapsed: 0)
        sampler.applyEnergy(EnergyState(batteryLevel: 0.10))
        let throttled = sampler.update(context: context(depth: 30), elapsed: 60)
        XCTAssertGreaterThan(throttled.interval, normal.interval)
    }

    func testDecisionHertzIsReciprocal() {
        let decision = AdaptiveSamplingPolicy.Decision(interval: 2, reason: .bottomIdle)
        XCTAssertEqual(decision.hertz, 0.5, accuracy: 0.0001)
    }

    // MARK: - Ekran verisi

    func testAodThemeHidesSecondaryDetails() {
        var state = divingState()
        state.maxDepth = 28.4
        let standard = DiveDisplayBuilder.build(from: state, isAlwaysOn: true,
                                                theme: .standard)
        let red = DiveDisplayBuilder.build(from: state, isAlwaysOn: true,
                                           theme: .alwaysOnRed)
        XCTAssertNotEqual(standard.maxDepthText, red.maxDepthText)
        XCTAssertEqual(red.maxDepthText, "—")
        XCTAssertTrue(red.showsSecondaryDetails == false)
    }

    func testAodThemeShortensDiveTime() {
        var state = divingState()
        state.diveTime = 125
        let standard = DiveDisplayBuilder.build(from: state, isAlwaysOn: true)
        let red = DiveDisplayBuilder.build(from: state, isAlwaysOn: true, theme: .alwaysOnRed)
        XCTAssertTrue(standard.diveTimeText.contains(":"))
        XCTAssertFalse(red.diveTimeText.contains(":"))
    }

    func testThemeReachesDisplayState() {
        let state = divingState()
        for theme in DiveDisplayTheme.allCases {
            let display = DiveDisplayBuilder.build(from: state, theme: theme)
            XCTAssertEqual(display.theme, theme)
            XCTAssertEqual(display.backgroundRGB, DiveThemeCatalog.spec(for: theme).background)
        }
    }

    func testNightThemeBackgroundIsBlack() {
        let display = DiveDisplayBuilder.build(from: divingState(), theme: .nightShift)
        XCTAssertEqual(display.backgroundRGB, DiveRGB.off)
    }

    func testInfoBannerHiddenInAodRed() {
        var state = divingState()
        state.warnings = [DiveWarning(kind: .gasSwitch, severity: .info,
                                      message: "Gaz değişti", raisedAtElapsed: 600)]
        let standard = DiveDisplayBuilder.build(from: state, theme: .standard)
        let red = DiveDisplayBuilder.build(from: state, isAlwaysOn: true, theme: .alwaysOnRed)
        XCTAssertNotNil(standard.banner)
        XCTAssertNil(red.banner)
    }

    func testCriticalBannerSurvivesAodRed() {
        var state = divingState()
        state.warnings = [DiveWarning(kind: .fastAscent, severity: .critical,
                                      message: "Hızlı çıkış", raisedAtElapsed: 600)]
        let red = DiveDisplayBuilder.build(from: state, isAlwaysOn: true, theme: .alwaysOnRed)
        XCTAssertNotNil(red.banner, "Kritik alarm hiçbir temada gizlenmemeli")
        XCTAssertTrue(red.isAlarmActive)
    }

    // MARK: - Ayarlar

    func testSettingsCarryEnergyOptions() {
        var settings = DiveSettings()
        XCTAssertEqual(settings.powerProfile, .balanced)
        XCTAssertEqual(settings.nightModePreference, .auto)
        XCTAssertTrue(settings.allowsAlwaysOnDisplay)

        settings.powerProfile = .saver
        settings.nightModePreference = .forced
        settings.allowsAlwaysOnDisplay = false
        XCTAssertEqual(settings.powerProfile, .saver)
        XCTAssertEqual(settings.nightModePreference, .forced)
        XCTAssertFalse(settings.allowsAlwaysOnDisplay)
    }

    func testSettingsRoundTripWithEnergyOptions() throws {
        var settings = DiveSettings()
        settings.powerProfile = .performance
        settings.nightModePreference = .forced
        settings.allowsAlwaysOnDisplay = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DiveSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testUserSelectableThemes() {
        var settings = DiveSettings()
        settings.nightModePreference = .forced
        XCTAssertEqual(DiveThemeCatalog.userSelectableThemes(for: settings), [.nightShift])
        settings.nightModePreference = .off
        XCTAssertEqual(DiveThemeCatalog.userSelectableThemes(for: settings), [.standard])
    }

    // MARK: - Bütünleşme

    @MainActor
    func testSaverProfileImprovesProjectedRuntime() {
        let state = EnergyState(batteryLevel: 0.8, isDiving: true, profile: .balanced)
        let balanced = EnergyManager(state: state)
        let saver = EnergyManager(
            state: EnergyState(batteryLevel: 0.8, isDiving: true, profile: .saver))
        XCTAssertGreaterThan(saver.projectedHours, balanced.projectedHours)
    }

    @MainActor
    func testNightModeImprovesProjectedRuntime() {
        let standard = EnergyManager(state: EnergyState(batteryLevel: 0.8, isDiving: true,
                                                        profile: .balanced),
                                    nightModePreference: .off)
        let night = EnergyManager(state: EnergyState(batteryLevel: 0.8, isDiving: true,
                                                      profile: .balanced),
                                  nightModePreference: .forced)
        XCTAssertEqual(standard.theme, .standard)
        XCTAssertEqual(night.theme, .nightShift)
        XCTAssertGreaterThan(night.projectedHours, standard.projectedHours)
    }

    func testAlwaysOnCostsRuntimeInTheSameTheme() {
        // AOD ekranı sürekli yandığı için aynı temada pil daha hızlı tükenir.
        let off = EnergyBudget.displayMilliwatts(theme: .standard, isAlwaysOn: false)
        let on = EnergyBudget.displayMilliwatts(theme: .standard, isAlwaysOn: true)
        XCTAssertGreaterThan(on, off)
    }

    func testRedAlwaysOnBeatsStandardNonAlwaysOn() {
        // Kırmızı AOD, standart paletten daha verimli olmalıdır: mavi/yeşil
        // piksellerin kapatılması, ekranın sürekli yanmasından daha büyük
        // bir kazanç sağlar.
        let standardScreen = EnergyManager(
            state: EnergyState(batteryLevel: 0.8, isAlwaysOn: false, isDiving: true,
                               profile: .balanced),
            nightModePreference: .off)
        let redAlwaysOn = EnergyManager(
            state: EnergyState(batteryLevel: 0.8, isAlwaysOn: true, isDiving: true,
                               profile: .balanced))
        XCTAssertEqual(standardScreen.theme, .standard)
        XCTAssertEqual(redAlwaysOn.theme, .alwaysOnRed)
        XCTAssertGreaterThan(redAlwaysOn.projectedHours, standardScreen.projectedHours)
    }

    @MainActor
    func testFullDiveEnergyProfile() {
        // Gerçekçi bir dalış boyunca tüketim profili izlenir.
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        var manager = EnergyManager(state: EnergyState(batteryLevel: 0.75, isDiving: true))

        let readings = DiveSimulator(scenario: .decompressionDive).readings
        for reading in readings {
            controller.ingest(reading)
            let state = controller.state
            manager.update(state: EnergyState(
                batteryLevel: manager.state.batteryLevel,
                thermalState: .nominal,
                isAlwaysOn: state.phase == .safetyStop,
                isDiving: state.phase.isDiving,
                profile: .balanced))
            XCTAssertGreaterThan(manager.currentMilliwatts, 0)
            XCTAssertLessThanOrEqual(manager.recommendedInterval, 10)
        }
        XCTAssertGreaterThan(manager.projectedHours, 1)
    }
}

// MARK: - Yardımcı

extension EnergyManager {
    /// Test kısayolu (gerçek API `setProfile` kullanır).
    mutating func setPowerProfileForTest(_ profile: PowerProfile) {
        setProfile(profile)
    }
}
