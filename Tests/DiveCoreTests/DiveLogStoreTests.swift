import XCTest
@testable import DiveCore

/// Kalıcılık modeli ve depo (bellek içi uygulama).
final class DiveLogStoreTests: XCTestCase {

    // MARK: - Yardımcı

    @MainActor
    private func makeDive(minutesAgo: Double = 0,
                          depth: Double = 30,
                          duration: TimeInterval = 1500,
                          device: String = "watch",
                          cns: Double = 20,
                          otu: Double = 90) -> LoggedDive {
        let scenario = DiveScenario(name: "t", segments: [
            .descent(to: depth, at: 15), .hover(at: depth, for: duration)
        ])
        let controller = DiveSessionController(configuration: .recreational)
        let start = Date(timeIntervalSince1970: 1_700_000_000 - minutesAgo * 60)
        controller.start(at: start)
        controller.ingest(DiveSimulator(scenario: scenario).readings)
        let log = controller.end(at: start.addingTimeInterval(duration))!

        var report = controller.makeReport(log: log)
        report.cnsPercent = cns
        report.otuUnits = otu
        return LoggedDive.make(log: log, report: report, originDevice: device)
    }

    // MARK: - LoggedDive

    func testStableIDIsDeterministic() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(LoggedDive.stableID(for: date), LoggedDive.stableID(for: date))
        XCTAssertEqual(LoggedDive.stableID(for: date, device: "watch"),
                       LoggedDive.stableID(for: date, device: "watch"))
    }

    func testStableIDDiffersByDeviceAndTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNotEqual(LoggedDive.stableID(for: date),
                          LoggedDive.stableID(for: date, device: "phone"))
        XCTAssertNotEqual(LoggedDive.stableID(for: date),
                          LoggedDive.stableID(for: date.addingTimeInterval(3600)))
    }

    func testStableIDIsUUIDVersion4() {
        let id = LoggedDive.stableID(for: Date(timeIntervalSince1970: 1_700_000_123))
        XCTAssertEqual(id.uuidString.count, 36)
        XCTAssertEqual(id.uuidString.split(separator: "-")[2].first, "4",
                       "Sürüm 4 olmalı")
    }

    @MainActor
    func testLoggedDiveFieldsFromLogAndReport() {
        let dive = makeDive(depth: 30, duration: 1500)
        XCTAssertGreaterThan(dive.maxDepth, 29)
        XCTAssertGreaterThan(dive.totalDiveTime, 1400)
        XCTAssertGreaterThan(dive.samples.count, 100, "Profil örnekleri saklanmalı")
        XCTAssertFalse(dive.gasLabels.isEmpty)
        XCTAssertTrue(dive.displayTitle.contains("m"))
        XCTAssertTrue(dive.durationText.contains("dk"))
        XCTAssertGreaterThan(dive.updatedAt.timeIntervalSince1970, 0)
    }

    @MainActor
    func testIsNewerComparison() {
        let first = makeDive()
        var second = first
        second.updatedAt = first.updatedAt.addingTimeInterval(60)
        XCTAssertTrue(second.isNewer(than: first))
        XCTAssertFalse(first.isNewer(than: second))
    }

    func testCodableRoundTrip() throws {
        let original = DiveSampleFixtures.richDive()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LoggedDive.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.decoStops.count, 1)
        XCTAssertEqual(decoded.gasLabels, "Air / EAN32")
        XCTAssertEqual(decoded.score, 4)
    }

    func testRichFixtureFields() {
        let dive = DiveSampleFixtures.richDive()
        XCTAssertEqual(dive.decoStops.first?.gas, GasMix.oxygen)
        XCTAssertEqual(dive.penalties.first?.kind, DivePenalty.Kind.fastAscent)
        XCTAssertEqual(dive.grade, DiveGrade.good)
        XCTAssertTrue(dive.hadDecoObligation)
    }

    // MARK: - InMemoryDiveLogStore

    func testSaveAndFetch() throws {
        let store = InMemoryDiveLogStore()
        XCTAssertEqual(store.diveCount, 0)

        let dive = DiveSampleFixtures.dive(at: 0)
        try store.save(dive)
        XCTAssertEqual(store.diveCount, 1)
        XCTAssertEqual(try store.dive(id: dive.id), dive)
        XCTAssertNil(try store.dive(id: UUID()))
    }

    func testSaveUpdatesByID() throws {
        let store = InMemoryDiveLogStore()
        let dive = DiveSampleFixtures.dive(at: 0)
        try store.save(dive)

        var updated = dive
        updated.markerCount = 7
        try store.save(updated)

        XCTAssertEqual(store.diveCount, 1, "Aynı kimlik güncellenmeli, kopya olmamalı")
        XCTAssertEqual(try store.dive(id: dive.id)?.markerCount, 7)
    }

    func testSortingIsNewestFirst() throws {
        let store = InMemoryDiveLogStore()
        try store.saveAll([
            DiveSampleFixtures.dive(at: 0),
            DiveSampleFixtures.dive(at: 3600),
            DiveSampleFixtures.dive(at: 7200)
        ])

        let all = try store.allDives()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].startDate, all[1].startDate.addingTimeInterval(3600))
        XCTAssertGreaterThan(all[0].startDate, all[2].startDate)
    }

    func testRecentDivesLimit() throws {
        let store = InMemoryDiveLogStore()
        try store.saveAll((0..<5).map { DiveSampleFixtures.dive(at: Double($0) * 3600) })
        XCTAssertEqual(try store.recentDives(limit: 2).count, 2)
        XCTAssertEqual(try store.recentDives(limit: 0).count, 0)
        XCTAssertEqual(try store.recentDives(limit: 99).count, 5)
    }

    func testDateRangeQuery() throws {
        let store = InMemoryDiveLogStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try store.saveAll([
            DiveSampleFixtures.dive(at: 0),
            DiveSampleFixtures.dive(at: 3600),
            DiveSampleFixtures.dive(at: 7200)
        ])
        let result = try store.dives(from: base.addingTimeInterval(1800),
                                     to: base.addingTimeInterval(5400))
        XCTAssertEqual(result.count, 1)
    }

    func testDeleteAndClear() throws {
        let store = InMemoryDiveLogStore()
        let dive = DiveSampleFixtures.dive(at: 0)
        try store.save(dive)

        try store.delete(id: dive.id)
        XCTAssertEqual(store.diveCount, 0)

        try store.saveAll((0..<3).map { DiveSampleFixtures.dive(at: Double($0) * 60) })
        try store.deleteAll()
        XCTAssertEqual(store.diveCount, 0)
    }
}

// MARK: - Test verisi yardımcısı

enum DiveSampleFixtures {

    /// Test verilerinin sabit başlangıç noktası (deterministik).
    static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)


    /// Tüm alanları dolu (kodlama testi için) bir kayıt.
    static func richDive() -> LoggedDive {
        let base = dive(at: 0)
        let stop = DecoStopRecord(depth: 6, arrivalElapsed: 1500, duration: 300,
                                  departureElapsed: 1800, gas: GasMix.oxygen)
        let penalty = DivePenalty(kind: .fastAscent, reason: "Çıkış 15 m/dk", weight: 2)
        return LoggedDive(id: base.id, startDate: base.startDate, endDate: base.endDate,
                          totalDiveTime: 1000, maxDepth: 30, averageDepth: 20,
                          bottomTime: 800, minimumTemperature: 18, maximumTemperature: 24,
                          maxAscentRate: 9, maxDescentRate: 15,
                          gases: [.air, .ean32], startGasIndex: 1,
                          maxPO2: 1.2, maxGF99: 90, cnsPercent: 30, otuUnits: 120,
                          hadDecoObligation: true, decoStops: [stop],
                          safetyStopCompleted: true, safetyStopAccumulated: 180,
                          noFlyTime: 3600, score: 4, grade: .good,
                          penalties: [penalty], markerCount: 2,
                          samples: base.samples, updatedAt: base.updatedAt,
                          originDevice: "watch")
    }

    /// Belirli bir zaman kaydı üreten geçerli bir `LoggedDive`.
    static func dive(at offset: TimeInterval,
                     maxDepth: Double = 30,
                     device: String = "watch") -> LoggedDive {
        let start = baseDate.addingTimeInterval(offset)
        let samples = (0...30).map { index in
            DiveSample(elapsed: Double(index) * 10,
                       depth: min(maxDepth, Double(index) * 2),
                       temperature: 22, ambientPressure: 3, po2: 0.8,
                       ascentRate: 0, gasIndex: 0, gf99: 40, ceiling: 0,
                       leadingTissuePressure: 1.2)
        }
        // Kimlik başlangıç tarihinden türetilir → aynı dalış hep aynı `id`
        return LoggedDive(
            id: LoggedDive.stableID(for: start, device: device),
            startDate: start,
            endDate: start.addingTimeInterval(300),
            totalDiveTime: 300, maxDepth: maxDepth, averageDepth: maxDepth / 2,
            bottomTime: 200, minimumTemperature: 19, maximumTemperature: 24,
            maxAscentRate: 9, maxDescentRate: 15,
            gases: [.air], startGasIndex: 0,
            maxPO2: 0.85, maxGF99: 80, cnsPercent: 20, otuUnits: 90,
            hadDecoObligation: false, decoStops: [],
            safetyStopCompleted: true, safetyStopAccumulated: 180,
            noFlyTime: 5400, score: 5, grade: .excellent, penalties: [],
            markerCount: 0, samples: samples,
            updatedAt: start, originDevice: device)
    }
}