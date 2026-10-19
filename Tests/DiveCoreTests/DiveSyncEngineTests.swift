import XCTest
@testable import DiveCore

/// Watch ⇄ iPhone senkronizasyonu: kuyruk, onay, çakışma çözümü, kodlama.
final class DiveSyncEngineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func dive(at offset: TimeInterval = 0,
                      updatedAt: TimeInterval = 0,
                      device: String = "watch") -> LoggedDive {
        var value = DiveSampleFixtures.dive(at: offset, device: device)
        value.updatedAt = base.addingTimeInterval(updatedAt)
        return value
    }

    // MARK: - Outbound

    func testEnqueueAddsPendingRecord() {
        var engine = DiveSyncEngine()
        XCTAssertFalse(engine.hasPending)

        engine.enqueue(dive())
        XCTAssertTrue(engine.hasPending)
        XCTAssertEqual(engine.outbound.count, 1)
        XCTAssertEqual(engine.statistics.pending, 1)
    }

    func testEnqueueSameDiveUpdatesInsteadOfDuplicating() {
        var engine = DiveSyncEngine()
        var first = dive()
        engine.enqueue(first)
        // Aynı dalışın güncellenmiş sürümü (aynı kimlik)
        first.updatedAt = base.addingTimeInterval(60)
        engine.enqueue(first)

        XCTAssertEqual(engine.outbound.count, 1, "Aynı dalış iki kez kuyruğa girmemeli")
        XCTAssertEqual(engine.outbound.first?.updatedAt, base.addingTimeInterval(60))
    }

    func testOutboundQueueIsOrderedByTime() {
        var engine = DiveSyncEngine()
        engine.enqueue(dive(at: 7200, updatedAt: 300))
        engine.enqueue(dive(at: 3600, updatedAt: 100))
        engine.enqueue(dive(at: 0, updatedAt: 200))

        XCTAssertEqual(engine.outbound.map(\.updatedAt),
                       [100, 200, 300].map { base.addingTimeInterval(TimeInterval($0)) })
    }

    func testFlushSendsThroughTransport() {
        var engine = DiveSyncEngine()
        let transport = LoopbackSyncTransport()
        engine.enqueue(dive())
        engine.flush(using: transport)

        XCTAssertEqual(transport.sent.count, 1)
    }

    func testAcknowledgementClearsQueue() {
        var engine = DiveSyncEngine()
        let transport = LoopbackSyncTransport()
        let record = dive()
        engine.enqueue(record)

        transport.onAcknowledgement = { engine.acknowledge($0) }
        let batch = engine.outbound
        transport.send(batch)
        XCTAssertTrue(engine.hasPending, "Onay gelene kadar kuyruk durmalı")
        transport.drain()

        XCTAssertFalse(engine.hasPending)
        XCTAssertEqual(engine.statistics.uploaded, 1)
        XCTAssertEqual(engine.statistics.pending, 0)
    }

    func testUnreachableTransportKeepsQueue() {
        var engine = DiveSyncEngine()
        let transport = LoopbackSyncTransport()
        transport.isReachable = false
        engine.enqueue(dive())

        transport.onFailure = { _ in engine.handleFailure() }
        let batch = engine.outbound
        transport.send(batch)
        transport.drain()

        XCTAssertTrue(engine.hasPending, "Ulaşılamıyorsa kuyruk korunmalı")
        XCTAssertEqual(engine.statistics.failures, 1)
        XCTAssertEqual(engine.retryCount, 1)
    }

    func testRetryLimit() {
        var engine = DiveSyncEngine()
        engine.maximumRetries = 2
        engine.enqueue(dive())

        XCTAssertNotNil(engine.retryNext())
        engine.handleFailure()
        XCTAssertNotNil(engine.retryNext())
        engine.handleFailure()
        XCTAssertTrue(engine.isRetryExhausted)
        XCTAssertNil(engine.retryNext())
    }

    func testRetryResetsAfterSuccess() {
        var engine = DiveSyncEngine()
        engine.enqueue(dive())
        engine.handleFailure()
        XCTAssertEqual(engine.retryCount, 1)

        let transport = LoopbackSyncTransport()
        let batch = engine.outbound
        transport.send(batch)
        XCTAssertEqual(engine.retryCount, 1, "Gönderim tamamlanana kadar sayaç durur")
    }

    // MARK: - Inbound

    func testReceiveDeduplicatesByID() {
        var engine = DiveSyncEngine()
        let record = dive()
        engine.receive([DiveSyncRecord(dive: record)])
        engine.receive([DiveSyncRecord(dive: record)])

        XCTAssertEqual(engine.inbound.count, 1)
        XCTAssertEqual(engine.statistics.received, 2)
    }

    func testReceiveKeepsNewestVersion() {
        var engine = DiveSyncEngine()
        engine.receive([DiveSyncRecord(dive: dive(updatedAt: 100))])
        engine.receive([DiveSyncRecord(dive: dive(updatedAt: 50))])

        XCTAssertEqual(engine.inbound.count, 1)
        XCTAssertEqual(engine.inbound.first?.updatedAt, base.addingTimeInterval(100),
                       "Eski sürüm yeniyi ezmemeli")
    }

    // MARK: - Birleştirme

    func testMergeInsertsUnknownDives() {
        var engine = DiveSyncEngine()
        engine.receive([DiveSyncRecord(dive: dive(at: 0))])

        let plan = engine.mergePlan(against: [])
        XCTAssertEqual(plan.inserted.count, 1)
        XCTAssertTrue(plan.updated.isEmpty)
        XCTAssertEqual(engine.statistics.conflicts, 0)
    }

    func testMergeUpdatesWhenIncomingIsNewer() {
        var engine = DiveSyncEngine()
        let local = dive(updatedAt: 100)
        engine.receive([DiveSyncRecord(dive: dive(updatedAt: 500))])

        let plan = engine.mergePlan(against: [local])
        XCTAssertEqual(plan.updated.count, 1)
        XCTAssertEqual(plan.updated.first?.updatedAt, base.addingTimeInterval(500))
        XCTAssertEqual(engine.statistics.conflicts, 1)
    }

    func testMergeMarksOrphanWhenLocalIsNewer() {
        var engine = DiveSyncEngine()
        let local = dive(updatedAt: 900)
        engine.receive([DiveSyncRecord(dive: dive(updatedAt: 100))])

        let plan = engine.mergePlan(against: [local])
        XCTAssertEqual(plan.orphaned.count, 1)
        XCTAssertTrue(plan.inserted.isEmpty)
        XCTAssertTrue(plan.updated.isEmpty)
    }

    func testMergeUnchangedWhenSameVersion() {
        var engine = DiveSyncEngine()
        let local = dive(updatedAt: 300)
        engine.receive([DiveSyncRecord(dive: local)])

        let plan = engine.mergePlan(against: [local])
        XCTAssertEqual(plan.unchanged, 1)
        XCTAssertTrue(plan.isEmpty)
    }

    func testApplyMergeWritesToStore() throws {
        var engine = DiveSyncEngine()
        let incoming = dive(at: 7200)
        engine.receive([DiveSyncRecord(dive: incoming)])

        let store = InMemoryDiveLogStore()
        let plan = engine.mergePlan(against: [])
        try engine.applyMerge(plan, to: store)

        XCTAssertEqual(store.diveCount, 1)
        XCTAssertEqual(try store.dive(id: incoming.id), incoming)
        XCTAssertTrue(engine.inbound.isEmpty, "Uygulanan kayıtlar kuyruktan temizlenmeli")
        XCTAssertEqual(engine.statistics.applied, 1)
    }

    func testMergeOfMultipleRecords() {
        var engine = DiveSyncEngine()
        let known = dive(at: 0, updatedAt: 100)
        engine.receive([
            DiveSyncRecord(dive: known),
            DiveSyncRecord(dive: dive(at: 3600)),
            DiveSyncRecord(dive: dive(at: 7200))
        ])

        let plan = engine.mergePlan(against: [known])
        XCTAssertEqual(plan.unchanged, 1)
        XCTAssertEqual(plan.inserted.count, 2)
        XCTAssertEqual(plan.changeCount, 2)
    }

    // MARK: - Kodlama

    func testRecordCodableRoundTrip() throws {
        let record = DiveSyncRecord(dive: DiveSampleFixtures.richDive())
        let data = try DiveSyncEngine.encode([record])
        let decoded = try DiveSyncEngine.decode(data)
        XCTAssertEqual(decoded, [record])
    }

    func testSingleRecordCodable() throws {
        let record = DiveSyncRecord(dive: DiveSampleFixtures.dive(at: 0))
        let data = try DiveSyncEngine.encodeSingle(record)
        XCTAssertEqual(try DiveSyncEngine.decodeSingle(data), record)
    }

    func testDecodingCorruptDataThrows() {
        let garbage = Data([0x00, 0x01, 0x02])
        XCTAssertThrowsError(try DiveSyncEngine.decode(garbage))
    }

    func testProtocolVersion() {
        let record = DiveSyncRecord(dive: DiveSampleFixtures.dive(at: 0))
        XCTAssertEqual(record.protocolVersion, DiveSyncRecord.currentVersion)
        XCTAssertTrue(DiveSyncError.isCompatible(remote: DiveSyncRecord.currentVersion))
        XCTAssertFalse(DiveSyncError.isCompatible(remote: 99))
    }

    func testSupersedes() {
        let older = DiveSyncRecord(dive: DiveSampleFixtures.dive(at: 0))
        var newerDive = older.dive
        newerDive.updatedAt = older.updatedAt.addingTimeInterval(60)
        let newer = DiveSyncRecord(dive: newerDive)

        XCTAssertTrue(newer.supersedes(older))
        XCTAssertFalse(older.supersedes(newer))
    }

    // MARK: - Döngüsel taşıma

    func testLoopbackTransportAcknowledges() {
        let transport = LoopbackSyncTransport()
        var engine = DiveSyncEngine()
        transport.onAcknowledgement = { engine.acknowledge($0) }
        engine.enqueue(DiveSampleFixtures.dive(at: 0))

        let batch = engine.outbound
        transport.send(batch)
        XCTAssertEqual(transport.pendingCallbackCount, 1, "Onay asenkron tetiklenir")
        transport.drain()
        XCTAssertFalse(engine.hasPending)
    }

    func testLoopbackTransportDelivers() {
        let transport = LoopbackSyncTransport()
        var engine = DiveSyncEngine()
        var received: [DiveSyncRecord] = []
        transport.onRecords = { received = $0 }

        transport.deliver([DiveSyncRecord(dive: DiveSampleFixtures.dive(at: 0))])
        transport.drain()
        engine.receive(received)
        XCTAssertEqual(engine.inbound.count, 1)
    }

    func testResetClearsEverything() {
        var engine = DiveSyncEngine()
        engine.enqueue(DiveSampleFixtures.dive(at: 0))
        engine.receive([DiveSyncRecord(dive: DiveSampleFixtures.dive(at: 3600))])
        engine.handleFailure()

        engine.reset()
        XCTAssertTrue(engine.inbound.isEmpty)
        XCTAssertFalse(engine.hasPending)
        XCTAssertEqual(engine.statistics.failures, 0)
        XCTAssertEqual(engine.retryCount, 0)
    }
}