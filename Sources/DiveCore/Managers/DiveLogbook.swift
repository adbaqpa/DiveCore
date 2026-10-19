import Foundation

/// Dalış defteri — kalıcılık, istatistik, grafik ve senkronizasyonu tek
/// yerden yöneten uygulama servisi (ADIM 5).
///
/// `DiveCore` içinde yaşar; platforma bağımlı değildir. Gerçek uygulamada
/// `SwiftDataDiveLogStore` (iOS/watchOS) ve `WatchConnectivityTransport` ile
/// beslenir; testlerde `InMemoryDiveLogStore` + `LoopbackSyncTransport` kullanılır.
@MainActor
public final class DiveLogbook {

    // MARK: - Bileşenler

    private let store: DiveLogStore
    private var sync = DiveSyncEngine()
    private weak var transport: DiveSyncTransport?

    /// Bellek içi önbellek (UI'ın hızlı okuması için)
    public private(set) var dives: [LoggedDive] = []

    /// Senkronizasyon durumu değiştiğinde çağrılır.
    public var onSyncChange: ((SyncStatistics) -> Void)?

    public init(store: DiveLogStore, transport: DiveSyncTransport? = nil) {
        self.store = store
        self.transport = transport
        reload()
    }

    // MARK: - Kayıt

    /// Dalış bitince kaydeder ve senkronizasyon kuyruğuna alır.
    @discardableResult
    public func add(log: LogEntry, report: DiveReport,
                    device: String = "watch") throws -> LoggedDive {
        let dive = LoggedDive.make(log: log, report: report, originDevice: device)
        try store.save(dive)
        reload()
        sync.enqueue(dive)
        onSyncChange?(sync.statistics)
        return dive
    }

    /// Doğrudan kayıt ekler (senkronizasyonla gelen veri için `enqueue: false`).
    @discardableResult
    public func add(_ dive: LoggedDive, enqueue: Bool = true) throws -> LoggedDive {
        try store.save(dive)
        reload()
        if enqueue {
            sync.enqueue(dive)
            onSyncChange?(sync.statistics)
        }
        return dive
    }

    /// Toplu ekleme (iPhone → watch aktarımı).
    public func addAll(_ incoming: [LoggedDive], enqueue: Bool = false) throws {
        try store.saveAll(incoming)
        reload()
        if enqueue {
            for dive in incoming { sync.enqueue(dive) }
            onSyncChange?(sync.statistics)
        }
    }

    public func delete(id: UUID) throws {
        try store.delete(id: id)
        reload()
    }

    public func deleteAll() throws {
        try store.deleteAll()
        reload()
    }

    public func reload() {
        dives = (try? store.allDives()) ?? []
    }

    // MARK: - Sorgular

    public var diveCount: Int { dives.count }

    public func dive(id: UUID) -> LoggedDive? {
        dives.first { $0.id == id }
    }

    public func recent(limit: Int = 20) -> [LoggedDive] {
        Array(dives.prefix(max(0, limit)))
    }

    public func dives(from start: Date, to end: Date) -> [LoggedDive] {
        dives.filter { $0.startDate >= start && $0.startDate <= end }
    }

    /// Aylara göre gruplanmış kayıtlar (grafik ekranı için).
    public func divesGroupedByMonth() -> [(month: Date, dives: [LoggedDive])] {
        var groups: [Date: [LoggedDive]] = [:]
        for dive in dives {
            let components = Calendar.current.dateComponents([.year, .month], from: dive.startDate)
            guard let month = Calendar.current.date(from: components) else { continue }
            groups[month, default: []].append(dive)
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.startDate > $1.startDate }) }
    }

    // MARK: - İstatistik

    public var statistics: DiveStatistics { DiveStatistics.make(from: dives) }

    public var dailyTotals: [DailyDiveTotals] { DailyTotalsBuilder.make(from: dives) }

    public func totals(for day: Date = Date()) -> DailyDiveTotals {
        DailyTotalsBuilder.forDay(day, from: dives)
    }

    /// İstatistik ve günlük toplamları içeren ekran verisi.
    public func display(syncLabel: String? = nil) -> LogbookDisplay {
        LogbookDisplay(dives: dives, statistics: statistics,
                       today: totals().diveCount > 0 ? totals() : nil,
                       syncLabel: syncLabel ?? defaultSyncLabel())
    }

    // MARK: - Grafik

    /// Bir dalışın profil grafiği (nokta bütçesiyle indirgenmiş).
    public func chart(for id: UUID, pointBudget: Int = DiveChartBuilder.defaultPointBudget) -> DiveProfileChart? {
        guard let dive = dive(id: id) else { return nil }
        return DiveChartBuilder.make(from: dive, pointBudget: pointBudget)
    }

    /// Tüm dalışların derinlik profili (karşılaştırma grafiği).
    public func combinedDepthChart(pointBudget: Int = 60) -> DiveProfileChart? {
        guard !dives.isEmpty else { return nil }
        let all = dives.sorted { $0.startDate < $1.startDate }
        return DiveChartBuilder.make(diveID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                     startDate: all.first!.startDate,
                                     samples: all.flatMap(\.samples),
                                     duration: all.map(\.totalDiveTime).reduce(0, +),
                                     maxDepth: dives.map(\.maxDepth).max() ?? 0,
                                     pointBudget: pointBudget)
    }

    // MARK: - Senkronizasyon

    /// Taşıma katmanını bağlar ve olayları dinler.
    public func bind(transport: DiveSyncTransport) {
        self.transport = transport
        transport.onAcknowledgement = { [weak self] ids in
            guard let self else { return }
            self.sync.acknowledge(ids)
            self.onSyncChange?(self.sync.statistics)
        }
        transport.onRecords = { [weak self] records in
            self?.accept(records)
        }
        transport.onFailure = { [weak self] _ in
            guard let self else { return }
            self.sync.handleFailure()
            self.onSyncChange?(self.sync.statistics)
        }
        transport.activate()
    }

    /// Bekleyen kayıtları gönderir.
    public func syncNow() {
        guard let transport else { return }
        sync.flush(using: transport)
        onSyncChange?(sync.statistics)
    }

    /// Karşı taraftan gelen kayıtları birleştirir.
    public func accept(_ records: [DiveSyncRecord]) {
        sync.receive(records)
        let plan = sync.mergePlan(against: dives)
        try? sync.applyMerge(plan, to: store)
        reload()
        // Yerelde daha yeni olan kayıtlar karşı tarafa geri gönderilir
        for stale in plan.orphaned {
            if let local = dive(id: stale.id) { sync.enqueue(local) }
        }
        onSyncChange?(sync.statistics)
    }

    /// Senkronizasyon sayaçları.
    public var syncStatistics: SyncStatistics { sync.statistics }

    /// Gönderilmeyi bekleyen kayıt sayısı.
    public var pendingSyncCount: Int { sync.outbound.count }

    /// Karşı taraf erişilebilir mi?
    public var isReachable: Bool { transport?.isReachable ?? false }

    /// Durum etiketi ("2 bekliyor", "Senkronize").
    public func defaultSyncLabel() -> String {
        if transport == nil { return "Yerel" }
        let pending = sync.outbound.count
        if pending > 0 { return "\(pending) bekliyor" }
        return isReachable ? "Senkronize" : "Çevrimdışı"
    }
}