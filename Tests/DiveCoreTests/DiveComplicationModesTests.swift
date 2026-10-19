import XCTest
@testable import DiveCore

/// ADIM 9 — komplikasyon modları: dalış sırası canlı veri, dalış dışı
/// yüzey aralığı / uçuş yasağı.
final class DiveComplicationModesTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcılar

    private func divingState(depth: Double = 24, seconds: Double = 900) -> DiveState {
        var state = DiveState()
        state.phase = .bottom
        state.currentDepth = depth
        state.maxDepth = depth
        state.diveTime = seconds
        state.noDecompressionLimit = 600
        state.ceilingDepth = 0
        return state
    }

    private func surfacedState() -> DiveState {
        var state = DiveState()
        state.phase = .surfaced
        state.diveTime = 1800
        return state
    }

    private func loadedStatus(gf99: Double = 85, noFly: TimeInterval = 4 * 3600,
                              cleared: Bool = false) -> SurfaceIntervalStatus {
        SurfaceIntervalStatus(elapsed: 2 * 3600, gf99: gf99,
                              desaturationRemaining: max(0, noFly - 1800),
                              noFlyRemaining: noFly,
                              isNoFlyCleared: cleared,
                              recommendation: "Uyarı: artık yük")
    }

    // MARK: - Mod tanımları

    func testModesPartitionLiveAndSurface() {
        let live = DiveComplicationMode.allCases.filter { $0.isLive }
        let surface = DiveComplicationMode.allCases.filter { $0.isSurface }
        XCTAssertEqual(live.count + surface.count, DiveComplicationMode.allCases.count)
        XCTAssertEqual(Set(live).union(surface).count, DiveComplicationMode.allCases.count)
        XCTAssertTrue(live.allSatisfy { !$0.isSurface })
        XCTAssertTrue(surface.allSatisfy { !$0.isLive })
    }

    func testFallbackStaysInSameFamily() {
        for mode in DiveComplicationMode.allCases {
            XCTAssertEqual(mode.fallback.isLive, mode.isLive,
                           "\(mode) yedeği aynı ailede olmalı")
            XCTAssertNotEqual(mode, mode.fallback)
        }
    }

    func testModesHaveTitlesAndDetails() {
        for mode in DiveComplicationMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.detail.isEmpty)
            XCTAssertFalse(mode.id.isEmpty)
        }
    }

    func testIsSuitableMatchesPhase() {
        let diving = divingState()
        let surfaced = surfacedState()
        XCTAssertTrue(DiveComplicationMode.liveNDL.isSuitable(for: diving, isDiving: true))
        XCTAssertFalse(DiveComplicationMode.liveNDL.isSuitable(for: surfaced, isDiving: false))
        XCTAssertTrue(DiveComplicationMode.noFly.isSuitable(for: surfaced, isDiving: false))
    }

    // MARK: - Çözümleyici

    func testLiveModeIsUsedWhileDiving() {
        let state = divingState()
        let status = loadedStatus()
        for mode in [DiveComplicationMode.liveDepth, .liveNDL] {
            XCTAssertEqual(
                DiveComplicationModeResolver.effective(mode: mode, state: state,
                                                        isDiving: true, status: status),
                mode)
        }
    }

    func testSurfaceModeFallsBackToSurfaceFamilyWhileDiving() {
        let state = divingState()
        let status = loadedStatus()
        for mode in [DiveComplicationMode.surfaceInterval, .noFly] {
            XCTAssertEqual(
                DiveComplicationModeResolver.effective(mode: mode, state: state,
                                                        isDiving: true, status: status),
                .liveDepth)
        }
    }

    func testLiveModeFallsBackToSurfaceFamilyOnSurface() {
        let state = surfacedState()
        let status = loadedStatus()
        // Yasa varken canlı mod, yüzey ailesinin en görevli moduna düşer
        XCTAssertEqual(
            DiveComplicationModeResolver.effective(mode: .liveNDL, state: state,
                                                    isDiving: false, status: status),
            .noFly)
    }

    func testNoFlyModeDropsToSurfaceIntervalWhenCleared() {
        let state = surfacedState()
        let cleared = loadedStatus(gf99: 3, noFly: 0, cleared: true)
        XCTAssertEqual(
            DiveComplicationModeResolver.effective(mode: .noFly, state: state,
                                                    isDiving: false, status: cleared),
            .surfaceInterval)
    }

    func testNoFlyModeKeptWhenRestrictionActive() {
        let state = surfacedState()
        XCTAssertEqual(
            DiveComplicationModeResolver.effective(mode: .noFly, state: state,
                                                    isDiving: false,
                                                    status: loadedStatus()),
            .noFly)
    }

    func testAvailableModesDuringDive() {
        let modes = DiveComplicationModeResolver.availableModes(
            state: divingState(), isDiving: true, status: loadedStatus())
        XCTAssertEqual(modes, [.liveDepth, .liveNDL])
    }

    func testAvailableModesOnSurfaceWithoutRestriction() {
        let modes = DiveComplicationModeResolver.availableModes(
            state: surfacedState(), isDiving: false,
            status: loadedStatus(cleared: true))
        XCTAssertEqual(modes, [.surfaceInterval, .noFly])
    }

    func testAvailableModesOnSurfaceWithRestriction() {
        let modes = DiveComplicationModeResolver.availableModes(
            state: surfacedState(), isDiving: false, status: loadedStatus())
        XCTAssertEqual(modes, [.surfaceInterval],
                       "Uçuş yasağı varken 'uçuş yasağı' modu zaten açık")
    }

    func testAvailableModesWithoutAnyDive() {
        let modes = DiveComplicationModeResolver.availableModes(
            state: DiveState(), isDiving: false, status: nil)
        XCTAssertEqual(modes, [.surfaceInterval, .noFly])
    }

    // MARK: - Canlı NDL verisi

    func testLiveNDLRectangularShowsDepthAndNdl() {
        let data = DiveComplicationBuilder.buildLiveNDL(from: divingState(depth: 24.5),
                                                         style: .rectangular)
        XCTAssertTrue(data.primaryText.contains("24"))
        XCTAssertTrue(data.secondaryText.contains("NDL"))
        XCTAssertTrue(data.secondaryText.contains("10:00"))
        XCTAssertEqual(data.style, .rectangular)
    }

    func testLiveNDLSwitchesToCeilingWhenDecoObligation() {
        var state = divingState()
        state.noDecompressionLimit = 0
        state.ceilingDepth = 3
        state.nextStopDepth = 3
        let data = DiveComplicationBuilder.buildLiveNDL(from: state, style: .circular)
        XCTAssertEqual(data.secondaryText, "tavan")
        XCTAssertEqual(data.tertiaryText, "3.0")
        XCTAssertEqual(data.accentRole, .caution)
    }

    func testLiveNDLInlineIsCompact() {
        let data = DiveComplicationBuilder.buildLiveNDL(from: divingState(), style: .inline)
        XCTAssertTrue(data.primaryText.contains("m"))
        XCTAssertTrue(data.tertiaryText.isEmpty, "Inline komplikasyonda üçüncü satır yok")
    }

    func testAlarmOverridesColorRole() {
        var state = divingState()
        state.warnings = [DiveWarning(kind: .fastAscent, severity: .critical, message: "Hızlı çıkış", raisedAtElapsed: 600)]
        let data = DiveComplicationBuilder.buildLiveNDL(from: state, style: .circular)
        XCTAssertEqual(data.accentRole, .danger)
        XCTAssertTrue(data.isAlarmActive)
    }

    // MARK: - Yüzey aralığı / uçuş yasağı verisi

    func testNoFlyCircularShowsRemainingTime() {
        let data = SurfaceComplicationBuilder.build(
            mode: .noFly, status: loadedStatus(gf99: 85, noFly: 3 * 3600 + 600),
            style: .circular)
        XCTAssertEqual(data.primaryText, DurationFormatter.clock(3 * 3600 + 600))
        XCTAssertEqual(data.secondaryText, "uçuş yasağı")
        XCTAssertTrue(data.isAlarmActive)
        XCTAssertEqual(data.accentRole, .caution)
    }

    func testSurfaceIntervalCircularShowsGF99() {
        let data = SurfaceComplicationBuilder.build(
            mode: .surfaceInterval, status: loadedStatus(gf99: 85, noFly: 3 * 3600),
            style: .circular)
        XCTAssertEqual(data.primaryText, "%85",
                       "Yüzey aralığı modunda geri sayım değil GF99 gösterilir")
        XCTAssertEqual(data.secondaryText, "GF99")
        XCTAssertFalse(data.isAlarmActive, "GF yüksekliği bir alarm değildir")
    }

    func testNoFlyRectangularShowsCabinProfile() {
        let data = SurfaceComplicationBuilder.build(
            mode: .noFly, status: loadedStatus(gf99: 85, noFly: 4 * 3600),
            cabin: .standardFlight, cabinRemaining: 18 * 3600,
            style: .rectangular)
        XCTAssertTrue(data.primaryText.contains("Uçuş yasağı"))
        XCTAssertTrue(data.secondaryText.contains("GF99"))
        XCTAssertTrue(data.tertiaryText.contains("Standart uçuş"))
        XCTAssertTrue(data.tertiaryText.contains("18s 0dk"))
    }

    func testNoFlyInlineIsSingleLine() {
        let data = SurfaceComplicationBuilder.build(
            mode: .noFly, status: loadedStatus(gf99: 85, noFly: 4 * 3600),
            style: .inline)
        XCTAssertTrue(data.primaryText.hasPrefix("Uçuş "))
        XCTAssertTrue(data.tertiaryText.isEmpty)
    }

    func testClearedStatusIsSafeAndShowsElapsed() {
        let cleared = loadedStatus(gf99: 2, noFly: 0, cleared: true)
        for style in [DiveComplicationData.Style.inline, .circular, .rectangular, .corner] {
            let data = SurfaceComplicationBuilder.build(mode: .noFly, status: cleared, style: style)
            XCTAssertEqual(data.accentRole, .safe, "\(style) serbest durumda güvenli olmalı")
            XCTAssertFalse(data.isAlarmActive)
        }
        let circular = SurfaceComplicationBuilder.build(mode: .noFly, status: cleared,
                                                        style: .circular)
        XCTAssertEqual(circular.primaryText, "%2")
    }

    func testCornerComplicationUsesAirplaneGlyph() {
        let data = SurfaceComplicationBuilder.build(
            mode: .noFly, status: loadedStatus(), style: .corner)
        XCTAssertEqual(data.secondaryText, "airplane")
    }

    func testGaugeTracksGasLoad() {
        let light = SurfaceComplicationBuilder.build(
            mode: .surfaceInterval,
            status: loadedStatus(gf99: 20, noFly: 3600), style: .circular)
        let heavy = SurfaceComplicationBuilder.build(
            mode: .surfaceInterval,
            status: loadedStatus(gf99: 120, noFly: 3600), style: .circular)
        XCTAssertLessThan(light.gauge, heavy.gauge)
        XCTAssertLessThanOrEqual(heavy.gauge, 1)
    }

    // MARK: - Birleşik giriş noktası

    func testUnifiedBuilderDispatchesToEachMode() {
        let diving = divingState()
        let status = loadedStatus()

        let live = DiveComplicationBuilder.build(mode: .liveDepth, state: diving,
                                                 isDiving: true, style: .rectangular,
                                                 status: status)
        let liveNDL = DiveComplicationBuilder.build(mode: .liveNDL, state: diving,
                                                    isDiving: true, style: .rectangular,
                                                    status: status)
        let surface = DiveComplicationBuilder.build(mode: .surfaceInterval,
                                                    state: surfacedState(), isDiving: false,
                                                    style: .rectangular, status: status)
        let noFly = DiveComplicationBuilder.build(mode: .noFly, state: surfacedState(),
                                                  isDiving: false, style: .rectangular,
                                                  status: status)

        XCTAssertNotEqual(live, liveNDL)
        XCTAssertNotEqual(surface, noFly)
        XCTAssertTrue(noFly.primaryText.contains("Uçuş"))
        XCTAssertTrue(surface.primaryText.contains("Yüzey"))
    }

    func testUnifiedBuilderFallsBackWhenNoDiveRecorded() {
        let data = DiveComplicationBuilder.build(mode: .noFly, state: DiveState(),
                                                 isDiving: false, style: .inline, status: nil)
        XCTAssertEqual(data.style, .inline)
        XCTAssertFalse(data.primaryText.isEmpty)
    }

    func testUnifiedBuilderMatchesManualSurfaceBuild() {
        let state = surfacedState()
        let status = loadedStatus(gf99: 60, noFly: 2 * 3600)
        for style in [DiveComplicationData.Style.inline, .circular, .rectangular, .corner] {
            let viaBuilder = DiveComplicationBuilder.build(mode: .noFly, state: state,
                                                           isDiving: false, style: style,
                                                           status: status)
            let direct = SurfaceComplicationBuilder.build(mode: .noFly, status: status,
                                                          style: style)
            XCTAssertEqual(viaBuilder, direct, "\(style) yolları aynı veriyi üretmeli")
        }
    }

    func testIntentIsStartDiveWhenCleared() {
        let cleared = loadedStatus(gf99: 0, noFly: 0, cleared: true)
        let data = SurfaceComplicationBuilder.build(mode: .surfaceInterval, status: cleared,
                                                    style: .rectangular)
        XCTAssertEqual(data.intentLabel, DiveActionIntent.startDive.label)
    }

    func testAllStylesProduceDistinctEnoughData() {
        let status = loadedStatus(gf99: 70, noFly: 5 * 3600)
        var seen: Set<DiveComplicationData.Style> = []
        for style in DiveComplicationData.Style.allCases {
            let data = SurfaceComplicationBuilder.build(mode: .noFly, status: status, style: style)
            XCTAssertEqual(data.style, style)
            XCTAssertFalse(data.primaryText.isEmpty)
            seen.insert(style)
        }
        XCTAssertEqual(seen.count, DiveComplicationData.Style.allCases.count)
    }

    // MARK: - Kodlanabilirlik

    func testModesRoundTripThroughCodable() throws {
        for mode in DiveComplicationMode.allCases {
            let data = try JSONEncoder().encode(mode)
            XCTAssertEqual(try JSONDecoder().decode(DiveComplicationMode.self, from: data), mode)
        }
    }

    func testComplicationDataRoundTrip() throws {
        let data = SurfaceComplicationBuilder.build(
            mode: .noFly, status: loadedStatus(gf99: 70, noFly: 3 * 3600),
            cabin: .highAltitudeFlight, cabinRemaining: 22 * 3600, style: .rectangular)
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(DiveComplicationData.self, from: encoded)
        XCTAssertEqual(decoded, data)
    }

    // MARK: - Yüzey yöneticisi ile bütünleşme

    @MainActor
    func testComplicationsFollowRealSurfaceInterval() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .decompressionDive).readings)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
        let diveEnd = log.endDate ?? base

        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: diveEnd, log: log)

        // Dalıştan hemen sonra: uçuş yasağı aktif
        let justAfter = manager.status(at: diveEnd)
        let data = DiveComplicationBuilder.build(
            mode: .noFly, state: surfacedState(), isDiving: false,
            style: .circular, status: justAfter)
        XCTAssertTrue(data.isAlarmActive)
        XCTAssertFalse(data.primaryText.isEmpty)

        // Yeterince sonra: yasa kalkar, komplikasyon güvenliye döner
        let muchLater = manager.status(at: diveEnd.addingTimeInterval(48 * 3600))
        let cleared = DiveComplicationBuilder.build(
            mode: .noFly, state: surfacedState(), isDiving: false,
            style: .circular, status: muchLater)
        XCTAssertFalse(cleared.isAlarmActive)
        XCTAssertEqual(cleared.accentRole, .safe)
    }
}