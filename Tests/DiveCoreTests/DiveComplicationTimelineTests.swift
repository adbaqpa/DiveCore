import XCTest
@testable import DiveCore

/// ADIM 9 — komplikasyon zaman çizelgesi (WidgetKit `TimelineProvider` çekirdeği).
final class DiveComplicationTimelineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func divingState() -> DiveState {
        var state = DiveState()
        state.phase = .bottom
        state.currentDepth = 24
        state.maxDepth = 24
        state.diveTime = 900
        state.noDecompressionLimit = 600
        return state
    }

    private func surfacedState() -> DiveState {
        var state = DiveState()
        state.phase = .surfaced
        return state
    }

    private func status(noFly: TimeInterval, gf99: Double = 80) -> SurfaceIntervalStatus {
        SurfaceIntervalStatus(elapsed: 3600, gf99: gf99,
                              desaturationRemaining: max(0, noFly - 900),
                              noFlyRemaining: noFly,
                              isNoFlyCleared: noFly <= 0,
                              recommendation: "Yüzey aralığı sürüyor",
                              statusDate: base)
    }

    private let policy = BackgroundMonitoringPolicy.standard
    private var noFlyRequest: DiveComplicationTimeline.Request {
        .init(mode: .noFly, style: .circular)
    }

    // MARK: - Yapı

    func testEntriesAlwaysStartWithNow() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: status(noFly: 4 * 3600),
            request: noFlyRequest, now: base)
        XCTAssertEqual(entries.first?.date, base)
        XCTAssertGreaterThan(entries.count, 1, "Geri sayım sürerken birden fazla giriş üretilir")
    }

    func testEntriesAreChronologicalAndUnique() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: status(noFly: 8 * 3600),
            request: noFlyRequest, now: base)
        let dates = entries.map { $0.date }
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testEntryCountRespectsWidgetLimit() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: status(noFly: 30 * 3600),
            request: noFlyRequest, now: base)
        XCTAssertLessThanOrEqual(entries.count, DiveComplicationTimeline.maximumEntries)
        XCTAssertLessThanOrEqual(entries.count, policy.maximumChecks + 1)
    }

    func testCountdownDecreasesAlongEntries() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: status(noFly: 4 * 3600),
            request: noFlyRequest, now: base)
        let values = entries.compactMap { entry -> TimeInterval? in
            entry.countdownText.map { DurationFormatter.parse($0) }
        }
        XCTAssertEqual(values.count, entries.count)
        XCTAssertEqual(values, values.sorted(by: >), "Geri sayım azalmalı")
    }

    func testEntriesStopBeforeNoFlyEnds() {
        let noFly: TimeInterval = 2 * 3600
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: status(noFly: noFly),
            request: noFlyRequest, now: base)
        for entry in entries {
            XCTAssertLessThan(entry.date.timeIntervalSince(base), noFly)
        }
    }

    func testClearedStatusProducesSingleEntry() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false,
            status: status(noFly: 0, gf99: 0), request: noFlyRequest, now: base)
        XCTAssertEqual(entries.count, 1)
    }

    func testNoStatusProducesSingleLiveEntry() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: nil,
            request: noFlyRequest, now: base)
        XCTAssertEqual(entries.count, 1)
    }

    func testDivingEntriesLookAheadOneMinute() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: divingState(), isDiving: true, status: status(noFly: 3600),
            request: noFlyRequest, now: base)
        XCTAssertEqual(entries.count, 4, "Şimdi + 3 dakikalık ileri bakış")
        XCTAssertEqual(entries[1].date.timeIntervalSince(base), 60)
        XCTAssertEqual(entries[3].date.timeIntervalSince(base), 180)
        // Dalış sırasında "uçuş yasağı" modu canlı moda düşer
        XCTAssertTrue(entries.allSatisfy { $0.countdownText == nil })
    }

    func testEachEntryCarriesRequestedStyle() {
        for style in DiveComplicationData.Style.allCases {
            let entries = DiveComplicationTimeline.makeEntries(
                state: surfacedState(), isDiving: false, status: status(noFly: 2 * 3600),
                request: .init(mode: .noFly, style: style), now: base)
            XCTAssertTrue(entries.allSatisfy { $0.data.style == style })
        }
    }

    func testSurfaceModeProgressesThroughModes() {
        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: status(noFly: 6 * 3600),
            request: .init(mode: .surfaceInterval, style: .rectangular), now: base)
        // GF99 doğrusal azaldığı için son girişte daha düşük değer görülür
        let gauges = entries.map { $0.data.gauge }
        XCTAssertEqual(gauges, gauges.sorted(by: >))
    }

    // MARK: - Yenileme zamanı

    func testNoRefreshWhenCleared() {
        XCTAssertNil(DiveComplicationTimeline.nextRefreshDate(
            state: surfacedState(), isDiving: false,
            status: status(noFly: 0), now: base))
    }

    func testNoRefreshWithoutStatus() {
        XCTAssertNil(DiveComplicationTimeline.nextRefreshDate(
            state: surfacedState(), isDiving: false, status: nil, now: base))
    }

    func testRefreshDuringDiveIsShort() {
        let next = DiveComplicationTimeline.nextRefreshDate(
            state: divingState(), isDiving: true, status: nil,
            now: base, minimumInterval: 60)
        XCTAssertEqual(next?.timeIntervalSince(base), 60)
    }

    func testRefreshHonoursPolicyAndNeverExceedsNoFly() {
        let noFly: TimeInterval = 3 * 3600
        let next = DiveComplicationTimeline.nextRefreshDate(
            state: surfacedState(), isDiving: false,
            status: status(noFly: noFly), now: base)
        guard let next else { return XCTFail("Yenileme tarihi bekleniyordu") }
        let delta = next.timeIntervalSince(base)
        XCTAssertGreaterThan(delta, 0)
        XCTAssertLessThanOrEqual(delta, noFly)
        XCTAssertEqual(delta, policy.checkInterval(remaining: noFly), accuracy: 1)
    }

    func testRefreshFrequentPolicyIsShorter() {
        let status = self.status(noFly: 12 * 3600)
        let standard = DiveComplicationTimeline.nextRefreshDate(
            state: surfacedState(), isDiving: false, status: status, now: base)
        let frequent = DiveComplicationTimeline.nextRefreshDate(
            state: surfacedState(), isDiving: false, status: status, now: base,
            policy: .frequent)
        guard let frequent, let standard else { return XCTFail("Yenileme tarihi bekleniyordu") }
        XCTAssertLessThan(frequent.timeIntervalSince(base), standard.timeIntervalSince(base))
    }

    // MARK: - Doğrusal ilerletme

    func testProjectedStatusDecreasesRemainders() {
        let start = status(noFly: 4 * 3600, gf99: 100)
        let later = start.projected(to: base.addingTimeInterval(1800))
        XCTAssertEqual(later.elapsed, start.elapsed + 1800)
        XCTAssertEqual(later.noFlyRemaining, start.noFlyRemaining - 1800)
        XCTAssertLessThan(later.gf99, start.gf99)
        XCTAssertEqual(later.gf99, 87.5, accuracy: 0.01)
        XCTAssertEqual(later.desaturationRemaining, start.desaturationRemaining - 1800)
    }

    func testProjectedStatusClearsAtNoFlyEnd() {
        let start = status(noFly: 3600)
        let after = start.projected(to: base.addingTimeInterval(3600))
        XCTAssertTrue(after.isNoFlyCleared)
        XCTAssertEqual(after.gf99, 0, accuracy: 0.01)
    }

    func testProjectedStatusInPastReturnsSelf() {
        let start = status(noFly: 3600)
        XCTAssertEqual(start.projected(to: base.addingTimeInterval(-60)), start)
    }

    func testStatusWithoutDateCannotProject() {
        let start = SurfaceIntervalStatus(elapsed: 0, gf99: 50, desaturationRemaining: 100,
                                          noFlyRemaining: 200, isNoFlyCleared: false,
                                          recommendation: "—")
        XCTAssertNil(start.snapshotDate)
        XCTAssertEqual(start.projected(to: base.addingTimeInterval(600)), start)
    }

    // MARK: - Gerçek yüzey yöneticisiyle bütünleşme

    @MainActor
    func testTimelineMatchesRealSurfaceManager() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .decompressionDive).readings)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
        let diveEnd = log.endDate ?? base

        var manager = SurfaceIntervalManager(resolution: 60)
        manager.recordDiveEnd(at: diveEnd, log: log)
        let now = diveEnd
        let snapshot = manager.status(at: now)

        let entries = DiveComplicationTimeline.makeEntries(
            state: surfacedState(), isDiving: false, status: snapshot,
            request: noFlyRequest, now: now)
        XCTAssertGreaterThan(entries.count, 1)
        XCTAssertEqual(entries.first?.date, now)
        XCTAssertTrue(entries.first?.data.isAlarmActive ?? false)

        // İlk girişin geri sayımı yöneticinin ölçümüyle aynı olmalı
        XCTAssertEqual(entries.first?.countdownText,
                       DurationFormatter.clock(snapshot.noFlyRemaining))

        // Son giriş, gerçek durumla karşılaştırıldığında uyuşmalı (kabin yok)
        guard let last = entries.last else { return XCTFail("Son giriş bekleniyordu") }
        let real = manager.status(at: last.date)
        let difference = abs(real.noFlyRemaining - (last.countdownText
            .map { DurationFormatter.parse($0) } ?? 0))
        XCTAssertLessThan(difference, 30 * 60,
                          "Doğrusal ilerletme gerçek çözünmeye yakın olmalı")
    }

    // MARK: - Kurulumlar

    func testPresetRequestsCoverBothFamilies() {
        let live = DiveComplicationTimeline.Request.presets.filter { $0.mode.isLive }
        let surface = DiveComplicationTimeline.Request.presets.filter { $0.mode.isSurface }
        XCTAssertEqual(live.count, 2)
        XCTAssertEqual(surface.count, 2)
    }

    func testEntryRoundTripsThroughCodable() throws {
        let entry = DiveComplicationTimeline.Entry(
            date: base,
            data: SurfaceComplicationBuilder.build(
                mode: .noFly, status: status(noFly: 3600), style: .rectangular),
            countdownText: "1:00:00")
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(DiveComplicationTimeline.Entry.self, from: data),
                       entry)
    }
}