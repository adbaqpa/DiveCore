import XCTest
@testable import DiveCore

/// Günlük CNS/OTU toplamları, genel istatistikler ve dalış defteri servisi.
@MainActor
final class DiveLogbookTests: XCTestCase {

    private let calendar = Calendar.current
    /// Test verilerinin günü (sabit ve deterministik)
    private var today = Calendar.current.startOfDay(for: DiveSampleFixtures.baseDate)

    // MARK: - Günlük toplamlar

    func testDailyTotalsAccumulate() {
        var totals = DailyDiveTotals(day: today)
        totals.add(DiveSampleFixtures.dive(at: 0))
        totals.add(DiveSampleFixtures.dive(at: 3600))

        XCTAssertEqual(totals.diveCount, 2)
        XCTAssertEqual(totals.otuSum, 180, accuracy: 0.001)
        XCTAssertEqual(totals.cnsSum, 40, accuracy: 0.001)
        XCTAssertEqual(totals.maxDepth, 30)
        XCTAssertEqual(totals.totalDiveTime, 600)
    }

    func testDailyTotalsIgnoreOtherDays() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let old = DiveSampleFixtures.dive(at: -86400)

        var totals = DailyDiveTotals(day: today)
        totals.add(old)
        XCTAssertEqual(totals.diveCount, 0, "Başka güne ait dalış eklenmemeli")
    }

    func testDailyTotalsGrouping() {
        let dives = [
            DiveSampleFixtures.dive(at: 0),
            DiveSampleFixtures.dive(at: 3600),
            DiveSampleFixtures.dive(at: -86400)
        ]
        let grouped = DailyTotalsBuilder.make(from: dives)

        XCTAssertEqual(grouped.count, 2)
        XCTAssertGreaterThan(grouped[0].day, grouped[1].day)
        XCTAssertEqual(grouped[0].diveCount, 2)
        XCTAssertEqual(grouped[1].diveCount, 1)
    }

    func testForDayQuery() {
        let dives = [DiveSampleFixtures.dive(at: 0), DiveSampleFixtures.dive(at: -86400)]
        let totals = DailyTotalsBuilder.forDay(today, from: dives)
        XCTAssertEqual(totals.diveCount, 1)
    }

    func testOtuPercentAndExceedance() {
        var totals = DailyDiveTotals(day: today, otuSum: 40)
        XCTAssertEqual(totals.otuPercent, 50, accuracy: 0.001)
        XCTAssertFalse(totals.isOTUExceeding)

        totals.otuSum = 120
        XCTAssertEqual(totals.otuPercent, 150, accuracy: 0.001)
        XCTAssertTrue(totals.isOTUExceeding)
    }

    func testCnsExceedance() {
        let totals = DailyDiveTotals(day: today, cnsSum: 120)
        XCTAssertTrue(totals.isCNSExceeding)
        XCTAssertEqual(totals.cnsPercent, 120, accuracy: 0.001)
    }

    func testRecoveryTimeUsesHalfLife() {
        // OTU 2 saat yarı ömür: %100 → %50 için 2 saat beklenir
        let totals = DailyDiveTotals(day: today, otuSum: 80)
        XCTAssertEqual(totals.rest(forOTUPercent: 50, cnsPercent: 0), 2 * 3600, accuracy: 1)

        // CNS yarı ömür 4 saat
        let cnsOnly = DailyDiveTotals(day: today, cnsSum: 100)
        XCTAssertEqual(cnsOnly.rest(forOTUPercent: 0, cnsPercent: 50), 4 * 3600, accuracy: 1)
    }

    func testRecoveryTimeRoundedToQuarterHour() {
        let totals = DailyDiveTotals(day: today, otuSum: 90)
        let rest = totals.rest()
        XCTAssertEqual(rest.truncatingRemainder(dividingBy: 900), 0, accuracy: 1)
        XCTAssertGreaterThan(rest, 0)
    }

    func testNoRestWhenBelowLimit() {
        let totals = DailyDiveTotals(day: today, cnsSum: 20, otuSum: 30)
        XCTAssertEqual(totals.rest(), 0)
        XCTAssertTrue(totals.advice().contains("sınırları içinde"))
    }

    func testAdviceMessages() {
        let otuHigh = DailyDiveTotals(day: today, otuSum: 120)
        XCTAssertTrue(otuHigh.advice().contains("OTU"))

        let both = DailyDiveTotals(day: today, cnsSum: 130, otuSum: 120)
        XCTAssertTrue(both.advice().contains("başka dalış"))

        XCTAssertTrue(otuHigh.advice(afterRest: true).contains("bekle"))
    }

    // MARK: - Genel istatistikler

    func testStatisticsFromEmpty() {
        let stats = DiveStatistics.make(from: [])
        XCTAssertEqual(stats.diveCount, 0)
        XCTAssertNil(stats.firstDiveDate)
        XCTAssertEqual(stats.totalDiveTime, 0)
    }

    func testStatisticsAggregates() {
        var deep = DiveSampleFixtures.dive(at: 0, maxDepth: 40)
        deep.totalDiveTime = 3600
        deep.hadDecoObligation = true
        deep.safetyStopCompleted = false
        let dives = [deep, DiveSampleFixtures.dive(at: -86400)]

        let stats = DiveStatistics.make(from: dives)
        XCTAssertEqual(stats.diveCount, 2)
        XCTAssertEqual(stats.deepestDive, 40)
        XCTAssertEqual(stats.longestDiveTime, 3600)
        XCTAssertEqual(stats.divesWithDeco, 1)
        XCTAssertEqual(stats.completedSafetyStops, 1)
        XCTAssertEqual(stats.totalDiveTime, 3600 + 300)
        XCTAssertEqual(stats.gasUsage["Air"], 2)
        XCTAssertNotNil(stats.firstDiveDate)
        XCTAssertNotNil(stats.lastDiveDate)
    }

    func testStatisticsBestGrade() {
        let dives = [DiveSampleFixtures.dive(at: 0), DiveSampleFixtures.richDive()]
        XCTAssertEqual(DiveStatistics.make(from: dives).bestGrade, DiveGrade.good)
    }

    // MARK: - Defter servisi

    private func makeLogbook() -> (DiveLogbook, InMemoryDiveLogStore) {
        let store = InMemoryDiveLogStore()
        return (DiveLogbook(store: store), store)
    }

    private func makeLogAndReport() -> (LogEntry, DiveReport) {
        let controller = DiveSessionController(configuration: .recreational)
        let start = Date()
        controller.start(at: start)
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        let log = controller.end(at: start.addingTimeInterval(controller.state.diveTime))!
        return (log, controller.makeReport(log: log))
    }

    func testAddPersistsAndQueues() throws {
        let (logbook, store) = makeLogbook()
        let (log, report) = makeLogAndReport()

        let dive = try logbook.add(log: log, report: report)
        XCTAssertEqual(logbook.diveCount, 1)
        XCTAssertEqual(store.diveCount, 1)
        XCTAssertEqual(logbook.pendingSyncCount, 1, "Yeni dalış senkronizasyon kuyruğuna alınmalı")
        XCTAssertEqual(logbook.dive(id: dive.id)?.id, dive.id)
    }

    func testQueriesAndSorting() throws {
        let (logbook, _) = makeLogbook()
        try logbook.addAll([
            DiveSampleFixtures.dive(at: -86400),
            DiveSampleFixtures.dive(at: 0)
        ])

        XCTAssertEqual(logbook.diveCount, 2)
        XCTAssertEqual(logbook.recent(limit: 1).count, 1)
        XCTAssertGreaterThan(logbook.dives[0].startDate, logbook.dives[1].startDate)
        XCTAssertEqual(logbook.divesGroupedByMonth().count, 1)
    }

    func testDeleteAndClear() throws {
        let (logbook, store) = makeLogbook()
        try logbook.addAll([DiveSampleFixtures.dive(at: 0)])
        try logbook.delete(id: logbook.dives[0].id)
        XCTAssertEqual(logbook.diveCount, 0)

        try logbook.addAll([DiveSampleFixtures.dive(at: 0)])
        try logbook.deleteAll()
        XCTAssertEqual(store.diveCount, 0)
    }

    func testStatisticsAndTotalsThroughLogbook() throws {
        let (logbook, _) = makeLogbook()
        try logbook.addAll((0..<3).map { index in DiveSampleFixtures.dive(at: Double(index) * 3600) })

        XCTAssertEqual(logbook.statistics.diveCount, 3)
        XCTAssertEqual(logbook.totals(for: today).diveCount, 3)
        XCTAssertEqual(logbook.dailyTotals.count, 1)
    }

    func testDisplayData() throws {
        let (logbook, _) = makeLogbook()
        let empty = logbook.display()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.rows.count, 0)

        try logbook.addAll([DiveSampleFixtures.dive(at: 0, maxDepth: 30)])
        let display = logbook.display()
        XCTAssertFalse(display.isEmpty)
        XCTAssertEqual(display.rows.count, 1)
        XCTAssertTrue(display.rows[0].title.contains("m"))
        XCTAssertFalse(display.statisticsLines.isEmpty)
        XCTAssertEqual(display.syncLabel, "Yerel")
    }

    func testChartCreation() throws {
        let (logbook, _) = makeLogbook()
        try logbook.addAll([DiveSampleFixtures.dive(at: 0)])
        let id = logbook.dives[0].id

        guard let chart = logbook.chart(for: id) else {
            return XCTFail("Grafik oluşturulamadı")
        }
        XCTAssertEqual(chart.diveID, id)
        XCTAssertNotNil(chart.series(.depth))
        XCTAssertNil(logbook.chart(for: UUID()))
        XCTAssertNotNil(logbook.combinedDepthChart())
    }

    func testSyncRoundTrip() throws {
        let (logbook, store) = makeLogbook()
        let transport = LoopbackSyncTransport()
        logbook.bind(transport: transport)
        XCTAssertTrue(transport.isReachable)
        XCTAssertEqual(transport.activateCount, 1)

        let (log, report) = makeLogAndReport()
        let local = try logbook.add(log: log, report: report)
        XCTAssertEqual(logbook.pendingSyncCount, 1)

        logbook.syncNow()
        transport.drain()
        XCTAssertEqual(logbook.pendingSyncCount, 0, "Onay sonrası kuyruk temizlenmeli")

        // Karşı tarafın gönderdiği kayıt (watch → phone)
        let phoneCopy = DiveSampleFixtures.dive(at: 7200)
        logbook.accept([DiveSyncRecord(dive: phoneCopy)])

        XCTAssertEqual(logbook.diveCount, 2)
        XCTAssertNotNil(logbook.dive(id: phoneCopy.id))
        XCTAssertEqual(store.diveCount, 2)
        XCTAssertNotNil(local.id)
    }

    func testSyncConflictKeepsNewest() throws {
        let (logbook, _) = makeLogbook()
        var local = DiveSampleFixtures.dive(at: 0)
        local.updatedAt = Date()
        try logbook.add(local, enqueue: false)

        var newer = local
        newer.updatedAt = local.updatedAt.addingTimeInterval(120)
        newer.markerCount = 9

        logbook.accept([DiveSyncRecord(dive: newer)])
        XCTAssertEqual(logbook.dive(id: local.id)?.markerCount, 9,
                       "Daha yeni sürüm kazanmalı")
    }

    func testSyncConflictRequeuesLocalWhenNewer() throws {
        let (logbook, _) = makeLogbook()
        var local = DiveSampleFixtures.dive(at: 0)
        local.updatedAt = Date()
        try logbook.add(local, enqueue: false)

        var older = local
        older.updatedAt = local.updatedAt.addingTimeInterval(-3600)

        logbook.accept([DiveSyncRecord(dive: older)])
        XCTAssertEqual(logbook.pendingSyncCount, 1,
                       "Yerel kayıt daha yeniyse karşı tarafa yeniden gönderilmeli")
    }

    func testSyncLabelReflectsState() throws {
        let (logbook, _) = makeLogbook()
        XCTAssertEqual(logbook.defaultSyncLabel(), "Yerel")

        let transport = LoopbackSyncTransport()
        logbook.bind(transport: transport)
        XCTAssertEqual(logbook.defaultSyncLabel(), "Senkronize")

        try logbook.add(DiveSampleFixtures.dive(at: 0), enqueue: true)
        XCTAssertTrue(logbook.defaultSyncLabel().contains("bekliyor"))
    }

    func testSyncCallbackUpdatesStatistics() throws {
        let (logbook, _) = makeLogbook()
        var observed: SyncStatistics?
        logbook.onSyncChange = { statistics in observed = statistics }

        try logbook.add(DiveSampleFixtures.dive(at: 0), enqueue: true)
        XCTAssertEqual(observed?.pending, 1)
    }

    func testReloadPicksUpExternalChanges() throws {
        let store = InMemoryDiveLogStore()
        let logbook = DiveLogbook(store: store)
        try store.save(DiveSampleFixtures.dive(at: 0))

        XCTAssertEqual(logbook.diveCount, 0)
        logbook.reload()
        XCTAssertEqual(logbook.diveCount, 1)
    }
}