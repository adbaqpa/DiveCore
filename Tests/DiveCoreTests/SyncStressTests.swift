import XCTest
@testable import DiveCore

/// ADIM 12 — **sınır durum ve stres testleri (3/3)**: WatchConnectivity
/// kopması, yeniden bağlanma, çakışma çözümü ve veri kaybı senaryoları.
///
/// ## Neden bu kadar çok senaryo?
/// Watch ⇄ iPhone bağlantısı **güvenilmez** bir kanaldır: kapsama giremez,
/// pil biter, kullanıcı bileği çıkarır, uygulama askıya alınır. Kritik
/// kural şudur: **kuyruktaki hiçbir dalış kaybı olmamalıdır**; bağlantı
/// ne zaman koparsa kopsun, tüm kayıtlar yeniden bağlantıda taşınmalıdır.
final class SyncStressTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcılar

    /// Testlerde kullanılan örnek dalış kaydı.
    ///
    /// - Note: `stableID(for:device:)` ile üretilir; böylece aynı başlangıç
    ///   zamanı ve cihaz için **her çağrıda aynı kimlik** elde edilir ve
    ///   senaryolar birbirinden bağımsız kalır.
    private func makeDive(minutes: Double = 30,
                          offset: TimeInterval = 0,
                          device: String = "watch") -> LoggedDive {
        let start = base.addingTimeInterval(offset)
        let duration = minutes * 60
        var dive = LoggedDive(
            id: LoggedDive.stableID(for: start, device: device),
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            totalDiveTime: duration,
            maxDepth: 30, averageDepth: 18, bottomTime: minutes * 50,
            minimumTemperature: 19, maximumTemperature: 24,
            maxAscentRate: 8, maxDescentRate: 14,
            gases: [.air], startGasIndex: 0,
            maxPO2: 1.05, maxGF99: 62, cnsPercent: 12, otuUnits: 0.8,
            hadDecoObligation: false, decoStops: [],
            safetyStopCompleted: true, safetyStopAccumulated: 180,
            noFlyTime: 7200, score: 5, grade: .excellent, penalties: [],
            markerCount: 0, samples: [],
            updatedAt: start.addingTimeInterval(60),
            originDevice: device)
        return dive
    }

    /// Testlerde kullanılan sahte taşıma katmanı.
    private final class FakeTransport: DiveSyncTransport {
        var isReachable = true
        var onRecords: (([DiveSyncRecord]) -> Void)?
        var onAcknowledgement: (([UUID]) -> Void)?
        var onFailure: ((Error) -> Void)?

        private(set) var sentBatches: [[DiveSyncRecord]] = []
        /// Otomatik onay kapalıyken gönderim "kaybolur"
        var autoAcknowledge = true
        var failNextSend = false

        struct SendError: Error {}

        func activate() {}
        func deactivate() { isReachable = false }

        func send(_ records: [DiveSyncRecord]) {
            guard !failNextSend else {
                failNextSend = false
                onFailure?(SendError())
                return
            }
            sentBatches.append(records)
            if autoAcknowledge {
                onAcknowledgement?(records.map(\.id))
            }
        }

        /// Gönderilen kayıtları "karşı tarafa teslim eder".
        func deliver() -> [DiveSyncRecord] {
            sentBatches.flatMap { $0 }
        }

        func clear() { sentBatches.removeAll() }
    }

    /// Gerçek bağlantıyı taklit eder: gönder → onayla.
    ///
    /// - Note: `DiveSyncEngine` bir **yapı** olduğundan taşıma katmanı
    ///  Closure ile doğrudan onay yollayamaz (değer yakalaması motorun
    ///   kopyasını güncellerdi). Bu yüzden bağlantı elle kurulur.
    private func flushAndAcknowledge(_ engine: inout DiveSyncEngine,
                                     _ transport: FakeTransport) {
        transport.clear()
        engine.flush(using: transport)
        engine.acknowledge(transport.deliver().map(\.id))
    }

    // MARK: - Temel kopma senaryosu

    func testUnreachableTransportPreservesQueue() {
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        transport.isReachable = false

        for i in 0..<3 { engine.enqueue(makeDive(offset: Double(i) * 3600)) }
        XCTAssertEqual(engine.outbound.count, 3)

        engine.flush(using: transport)
        XCTAssertEqual(engine.outbound.count, 3, "Ulaşılamazken kuyruk boşalmamalı")
        XCTAssertEqual(engine.statistics.failures, 1)
        XCTAssertEqual(engine.retryCount, 1)
    }

    func testReconnectDeliversEverything() {
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        transport.isReachable = false
        for i in 0..<5 { engine.enqueue(makeDive(offset: Double(i) * 3600)) }

        // 1) Bağlantı yok: 3 kez başarısız deneme
        for _ in 0..<3 { engine.flush(using: transport) }
        XCTAssertEqual(engine.outbound.count, 5)

        // 2) Bağlantı geldi
        transport.isReachable = true
        flushAndAcknowledge(&engine, transport)
        XCTAssertEqual(transport.deliver().count, 5, "Kuyruktaki 5 kayıt taşınmalı")
        XCTAssertEqual(engine.outbound.count, 0, "Onaylanan kayıtlar temizlenmeli")
        XCTAssertEqual(engine.statistics.uploaded, 5)
    }

    func testFailureHandlerKeepsQueue() {
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        engine.enqueue(makeDive())
        transport.failNextSend = true
        engine.flush(using: transport)
        engine.handleFailure()
        XCTAssertEqual(engine.outbound.count, 1)
    }

    func testRetryExhaustionStillKeepsData() {
        var engine = DiveSyncEngine()
        engine.maximumRetries = 3
        let transport = FakeTransport()
        transport.isReachable = false
        engine.enqueue(makeDive())

        for _ in 0..<5 { engine.flush(using: transport) }
        XCTAssertTrue(engine.isRetryExhausted)
        XCTAssertEqual(engine.outbound.count, 1,
                       "Yeniden deneme sınırı aşıldı diye veri silinmemeli")
        XCTAssertNil(engine.retryNext(), "Sınır aşıldıysa yeni deneme başlatılmaz")
    }

    func testRetryAfterRecoverySucceeds() {
        var engine = DiveSyncEngine()
        engine.maximumRetries = 10
        let transport = FakeTransport()
        transport.isReachable = false
        engine.enqueue(makeDive())
        for _ in 0..<4 { engine.flush(using: transport) }
        XCTAssertTrue(engine.retryNext() != nil)

        transport.isReachable = true
        flushAndAcknowledge(&engine, transport)
        XCTAssertEqual(engine.outbound.count, 0)
        XCTAssertEqual(engine.retryCount, 0, "Başarılı gönderimde sayaç sıfırlanır")
    }

    func testPartialAcknowledgementKeepsRest() {
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        transport.autoAcknowledge = false
        for i in 0..<4 { engine.enqueue(makeDive(offset: Double(i) * 3600)) }
        engine.flush(using: transport)

        // Yalnızca ilk iki onaylanıyor
        let ids = Array(engine.outbound.prefix(2).map(\.id))
        engine.acknowledge(ids)
        XCTAssertEqual(engine.outbound.count, 2)
        XCTAssertEqual(engine.outbound.first?.dive.maxDepth, 30)
    }

    // MARK: - Çakışma çözümü

    func testNewerRemoteWins() {
        var engine = DiveSyncEngine()
        let local = makeDive()
        var remote = local
        remote.score = 2                      // "karşı taraftan düzenlendi"
        remote.updatedAt = local.updatedAt.addingTimeInterval(60)

        engine.receive([DiveSyncRecord(dive: remote)])
        let plan = engine.mergePlan(against: [local])
        XCTAssertEqual(plan.updated.count, 1)
        XCTAssertEqual(plan.updated.first?.score, 2)
        XCTAssertEqual(engine.statistics.conflicts, 1)
    }

    func testNewerLocalWinsAndIsResent() {
        var engine = DiveSyncEngine()
        var local = makeDive()
        local.score = 4                  // "yerelde düzenlendi"
        var older = makeDive()
        older.updatedAt = local.updatedAt.addingTimeInterval(-120)

        engine.receive([DiveSyncRecord(dive: older)])
        let plan = engine.mergePlan(against: [local])
        XCTAssertTrue(plan.updated.isEmpty, "Daha eski kayıt uygulanmamalı")
        XCTAssertEqual(plan.orphaned.count, 1, "Eski kayıt karşı tarafa geri gönderilmeli")
    }

    func testEqualTimestampsKeepLocal() {
        var engine = DiveSyncEngine()
        let local = makeDive()
        var remote = makeDive()
        remote.updatedAt = local.updatedAt   // tam aynı
        remote.score = 1                      // "uzak"

        engine.receive([DiveSyncRecord(dive: remote)])
        let plan = engine.mergePlan(against: [local])
        XCTAssertTrue(plan.inserted.isEmpty)
        XCTAssertTrue(plan.updated.isEmpty, "Eşitlikte veri kaybı olmamalı")
        XCTAssertEqual(plan.unchanged, 1)
    }

    func testNewDiveIsInserted() {
        var engine = DiveSyncEngine()
        let remote = makeDive(offset: 7200)
        engine.receive([DiveSyncRecord(dive: remote)])
        let plan = engine.mergePlan(against: [makeDive()])
        XCTAssertEqual(plan.inserted.count, 1)
        XCTAssertEqual(plan.inserted.first?.id, remote.id)
    }

    // MARK: - Yinelenen ve karışık transferler

    func testDuplicateRecordsAreDeduplicated() {
        var engine = DiveSyncEngine()
        let dive = makeDive()
        // Aynı kayıt üç kez
        engine.receive([DiveSyncRecord(dive: dive),
                        DiveSyncRecord(dive: dive),
                        DiveSyncRecord(dive: dive)])
        XCTAssertEqual(engine.inbound.count, 1)
        XCTAssertEqual(engine.statistics.received, 3, "Sayaç tüm gelen kayıtları saymalı")
    }

    func testDuplicateInBatchYieldsSingleInsert() {
        var engine = DiveSyncEngine()
        let dive = makeDive()
        engine.receive([DiveSyncRecord(dive: dive), DiveSyncRecord(dive: dive)])
        let plan = engine.mergePlan(against: [])
        XCTAssertEqual(plan.inserted.count, 1, "Aynı dalış iki kez eklenmemeli")
    }

    func testOutOfOrderArrivalKeepsNewest() {
        var engine = DiveSyncEngine()
        let dive = makeDive()
        var older = DiveSyncRecord(dive: dive)
        older.updatedAt = base
        var newer = DiveSyncRecord(dive: dive)
        newer.updatedAt = base.addingTimeInterval(600)

        // Yeni önce, eski sonra geliyor
        engine.receive([newer, older])
        XCTAssertEqual(engine.inbound.count, 1)
        XCTAssertEqual(engine.inbound.first?.updatedAt, newer.updatedAt,
                       "Eski kayıt yenisiyle değiştirilmemeli")
    }

    func testInterleavedDisconnectMidTransfer() {
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        transport.autoAcknowledge = false
        for i in 0..<6 { engine.enqueue(makeDive(offset: Double(i) * 3600)) }

        // İlk 3 gönderilir, bağlantı kopar
        let all = engine.outbound
        transport.send(Array(all.prefix(3)))
        transport.isReachable = false
        engine.handleFailure()
        engine.handleFailure()
        XCTAssertEqual(engine.outbound.count, 6, "Hiçbir kayıt kaybolmamalı")

        // Bağlantı gelir, hepsi tekrar gönderilir
        transport.isReachable = true
        transport.clear()
        engine.flush(using: transport)
        XCTAssertEqual(Set(transport.deliver().map(\.id)).count, 6,
                       "Yeniden gönderimde tüm kayıtlar bulunmalı")
    }

    func testBulkRoundTrip() throws {
        // 100 dalışlık tam gidiş-dönüş
        var watch = DiveSyncEngine()
        var phone = DiveSyncEngine()
        let transport = FakeTransport()
        let dives = (0..<100).map { makeDive(offset: Double($0) * 3600) }
        let store = InMemoryDiveLogStore()

        for dive in dives { watch.enqueue(dive) }
        watch.flush(using: transport)
        var unique: [DiveSyncRecord] = []
        var seen = Set<UUID>()
        for record in transport.deliver() where !seen.contains(record.id) {
            seen.insert(record.id)
            unique.append(record)
        }
        XCTAssertEqual(unique.count, 100, "Aynı dalış iki kez taşınmamalı")
        let data = try DiveSyncEngine.encode(unique)
        let decoded = try DiveSyncEngine.decode(data)

        phone.receive(decoded)
        let plan = phone.mergePlan(against: try store.allDives())
        XCTAssertEqual(plan.inserted.count, 100)
        try phone.applyMerge(plan, to: store)
        XCTAssertEqual(try store.allDives().count, 100)
    }

    func testStableIDPreventsDuplicatesAcrossDevices() {
        // Aynı dalış, aynı cihazda aynı kimliği almalı
        XCTAssertEqual(makeDive(device: "watch").id, makeDive(device: "watch").id)
        // Farklı cihazlar farklı kimlik üretmeli
        XCTAssertNotEqual(makeDive(device: "watch").id,
                          makeDive(device: "phone").id)
    }

    // MARK: - Bozuk veri

    func testCorruptPayloadThrows() {
        let garbage = Data([0x00, 0xFF, 0x13, 0x37])
        XCTAssertThrowsError(try DiveSyncEngine.decode(garbage))
    }

    func testTruncatedPayloadThrows() throws {
        let records = [DiveSyncRecord(dive: makeDive())]
        let data = try DiveSyncEngine.encode(records)
        let truncated = data.prefix(data.count / 2)
        XCTAssertThrowsError(try DiveSyncEngine.decode(truncated))
    }

    func testEngineSurvivesDecodeFailure() throws {
        var engine = DiveSyncEngine()
        engine.enqueue(makeDive())
        _ = try? DiveSyncEngine.decode(Data([0x00]))
        XCTAssertEqual(engine.outbound.count, 1, "Bozuk veri kuyruğu bozmamalı")
    }

    /// Boş paket (uygulama askıya alındığında sık görülür) hata üretmemeli.
    func testEmptyPayloadDecodesToEmptyArray() throws {
        XCTAssertTrue(try DiveSyncEngine.decode(Data()).isEmpty)
    }

    func testWhitespaceOnlyPayloadIsTreatedAsEmpty() throws {
        XCTAssertTrue(try DiveSyncEngine.decode(Data([0x20, 0x0A])).isEmpty)
    }

    // MARK: - Sıfırlama

    func testResetClearsEverything() {
        var engine = DiveSyncEngine()
        engine.enqueue(makeDive())
        engine.receive([DiveSyncRecord(dive: makeDive(offset: 7200))])
        engine.reset()
        XCTAssertTrue(engine.outbound.isEmpty)
        XCTAssertTrue(engine.inbound.isEmpty)
        XCTAssertEqual(engine.retryCount, 0)
        XCTAssertEqual(engine.statistics.pending, 0)
    }

    func testMergeAfterResetIsClean() {
        var engine = DiveSyncEngine()
        engine.receive([DiveSyncRecord(dive: makeDive())])
        engine.reset()
        let plan = engine.mergePlan(against: [makeDive(offset: 99_999)])
        XCTAssertTrue(plan.inserted.isEmpty, "Sıfırlamadan sonra eski gelen kayıt olmamalı")
    }

    // MARK: - İstatistik tutarlılığı

    func testStatisticsCountersAddUp() {
        var engine = DiveSyncEngine()
        let store = InMemoryDiveLogStore()
        let transport = FakeTransport()
        for i in 0..<4 { engine.enqueue(makeDive(offset: Double(i) * 3600)) }
        flushAndAcknowledge(&engine, transport)
        XCTAssertEqual(engine.statistics.uploaded, 4)
        XCTAssertEqual(engine.statistics.pending, 0)

        engine.receive([DiveSyncRecord(dive: makeDive(offset: 9999))])
        let plan = engine.mergePlan(against: [])
        try? engine.applyMerge(plan, to: store)
        XCTAssertEqual(engine.statistics.applied, 1)
        XCTAssertEqual(engine.statistics.received, 1)
    }

    func testQueueOrderIsChronological() {
        var engine = DiveSyncEngine()
        for offset in [7200.0, 0.0, 3600.0] {
            engine.enqueue(makeDive(offset: offset))
        }
        let dates = engine.outbound.map { $0.dive.startDate }
        XCTAssertEqual(dates, dates.sorted(), "Kuyruk kronolojik sıralı olmalı")
    }

    func testReenqueueSameDiveUpdatesNotDuplicates() {
        var engine = DiveSyncEngine()
        var dive = makeDive()
        engine.enqueue(dive)
        dive.score = 3                       // "güncellendi"
        dive.updatedAt = dive.updatedAt.addingTimeInterval(60)
        engine.enqueue(dive)
        XCTAssertEqual(engine.outbound.count, 1, "Aynı dalış iki kez kuyruğa girmemeli")
        XCTAssertEqual(engine.outbound.first?.dive.score, 3)
    }

    func testPendingIDsReflectQueue() {
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        transport.autoAcknowledge = false
        for i in 0..<3 { engine.enqueue(makeDive(offset: Double(i) * 3600)) }
        engine.flush(using: transport)
        XCTAssertEqual(engine.pendingIDs.count, 3)
        XCTAssertTrue(engine.hasPending)
    }

    // MARK: - Dayanıklılık (soak)

    func testSoakRepeatedConnectCycles() {
        // 50 kopma/bağlanma döngüsü — hiçbir dalış kaybolmamalı.
        //
        // Kurgu: tek bir kuyruk birikir, yarı döngülerde bağlantı kopar
        // (gönderim başarısız, kuyruk korunur), diğer yarıda bağlantı gelir
        // ve **kuyruğun tamamı** yeniden gönderilip onaylanır.
        var engine = DiveSyncEngine()
        let transport = FakeTransport()
        var created: [UUID] = []
        var delivered = Set<UUID>()

        for cycle in 0..<50 {
            let dive = makeDive(offset: Double(cycle) * 3600)
            created.append(dive.id)
            engine.enqueue(dive)

            if cycle % 2 == 0 {
                // Bağlantı kopuk: gönderim başarısız, kuyruk korunur
                transport.isReachable = false
                engine.flush(using: transport)
                engine.handleFailure()
                XCTAssertTrue(engine.hasPending, "Kopukken kuyruk boşalmamalı")
            } else {
                // Bağlantı geldi: kuyruğun tamamı taşınır
                transport.isReachable = true
                transport.clear()
                engine.flush(using: transport)
                let batch = transport.deliver()
                delivered.formUnion(batch.map(\.id))
                engine.acknowledge(batch.map(\.id))
            }
        }

        // Son kuyruk da taşınmalı
        transport.isReachable = true
        transport.clear()
        engine.flush(using: transport)
        delivered.formUnion(transport.deliver().map(\.id))

        XCTAssertEqual(delivered.count, created.count,
                       "Kopma/bağlanma döngüsünde veri kaybı olmamalı")
        XCTAssertEqual(Set(created), delivered)
    }
}
