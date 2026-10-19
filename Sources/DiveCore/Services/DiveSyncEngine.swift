import Foundation

/// WatchConnectivity telinde taşınan tek dalış kaydı.
public struct DiveSyncRecord: Codable, Equatable, Sendable, Identifiable {

    public var protocolVersion: Int
    public var updatedAt: Date
    public var dive: LoggedDive

    public var id: UUID { dive.id }

    public init(dive: LoggedDive, protocolVersion: Int = DiveSyncRecord.currentVersion) {
        self.protocolVersion = protocolVersion
        self.updatedAt = dive.updatedAt
        self.dive = dive
    }

    /// Tel protokol sürümü (şema değişikliklerinde artırılır).
    public static let currentVersion = 1

    /// Aynı dalışın yeni sürümü mü?
    public func supersedes(_ other: DiveSyncRecord) -> Bool {
        id == other.id && updatedAt > other.updatedAt
    }
}

/// Senkronizasyon sonucunda ne yapılacağını anlatan plan.
public struct SyncMergeResult: Equatable, Sendable {
    /// Depoya eklenecek yeni kayıtlar
    public var inserted: [LoggedDive]
    /// Depoda güncellenecek kayıtlar
    public var updated: [LoggedDive]
    /// Karşılığı bulunamadığı için atlanan kayıtlar
    public var orphaned: [LoggedDive]
    /// Değişmediği için dokunulmayan kayıtlar
    public var unchanged: Int

    public init(inserted: [LoggedDive] = [], updated: [LoggedDive] = [],
                orphaned: [LoggedDive] = [], unchanged: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.orphaned = orphaned
        self.unchanged = unchanged
    }

    /// Hiçbir değişiklik gerekiyor mu? (eşleşen ama aynı sürümdeki kayıtlar
    /// değişiklik sayılmaz)
    public var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && orphaned.isEmpty
    }

    /// Uygulanacak kayıt sayısı.
    public var changeCount: Int { inserted.count + updated.count }
}

/// Senkronizasyon sayaçları.
public struct SyncStatistics: Equatable, Codable, Sendable {
    public var pending: Int = 0
    public var uploaded: Int = 0
    public var received: Int = 0
    public var applied: Int = 0
    public var conflicts: Int = 0
    public var failures: Int = 0
    public var lastTransferAt: Date?

    public init() {}

    public init(pending: Int = 0, uploaded: Int = 0, received: Int = 0, applied: Int = 0,
                conflicts: Int = 0, failures: Int = 0, lastTransferAt: Date? = nil) {
        self.pending = pending
        self.uploaded = uploaded
        self.received = received
        self.applied = applied
        self.conflicts = conflicts
        self.failures = failures
        self.lastTransferAt = lastTransferAt
    }
}

/// WatchConnectivity taşıma katmanı arayüzü.
///
/// `WCSession` sarmalayıcıları bu protokolü uygular; böylece birleştirme ve
/// kuyruk mantığı platformdan bağımsız test edilir.
public protocol DiveSyncTransport: AnyObject {
    /// Oturumu etkinleştir (tel hazır).
    func activate()
    /// Oturumu kapat.
    func deactivate()
    /// Kayıtları karşı tarafa gönder.
    func send(_ records: [DiveSyncRecord])
    /// Karşı taraftan gelen kayıtlar.
    var onRecords: (([DiveSyncRecord]) -> Void)? { get set }
    /// Gönderimin başarıyla tamamlandığı bildirimi (kimlikler).
    var onAcknowledgement: (([UUID]) -> Void)? { get set }
    /// Hata bildirimi.
    var onFailure: ((Error) -> Void)? { get set }
    /// Karşı taraf erişilebilir mi?
    var isReachable: Bool { get }
}

/// Watch ⇄ iPhone senkronizasyon mantığı.
///
/// Sorumlulukları:
/// - Yeni/güncellenmiş dalışları **outbound** kuyruğa almak,
/// - Kuyruğu taşıma katmanına vermek ve onayla temizlemek,
/// - Gelen kayıtları mevcut kayıtlarla karşılaştırıp **çakışma çözmek**
///   (daha yeni `updatedAt` kazanır),
/// - İstatistik tutmak.
public struct DiveSyncEngine {

    /// Gönderilmeyi bekleyen kayıtlar (eskiden yeniye)
    public private(set) var outbound: [DiveSyncRecord] = []
    /// Gelen ama henüz uygulanmamış kayıtlar
    public private(set) var inbound: [DiveSyncRecord] = []

    public private(set) var statistics = SyncStatistics()
    /// Yeniden deneme sayısı (hata arttıkça artar)
    public private(set) var retryCount: Int = 0
    /// Maksimum yeniden deneme (aşılınca kuyruk bekler)
    public var maximumRetries: Int = 5

    public init() {}

    // MARK: - Outbound

    /// Dalışı gönderim kuyruğuna alır (aynı kayıt zaten kuyruktaysa günceller).
    public mutating func enqueue(_ dive: LoggedDive) {
        let record = DiveSyncRecord(dive: dive)
        if let index = outbound.firstIndex(where: { $0.id == record.id }) {
            outbound[index] = record
        } else {
            outbound.append(record)
            outbound.sort { $0.updatedAt < $1.updatedAt }
        }
        statistics.pending = outbound.count
    }

    /// Kuyruktaki tüm kayıtları taşıma katmanına verir.
    public mutating func flush(using transport: DiveSyncTransport) {
        guard !outbound.isEmpty else { return }
        transport.send(outbound)
        if !transport.isReachable {
            statistics.failures += 1
            retryCount += 1
            return
        }
        retryCount = 0
    }

    /// Gönderilen kayıtlar onaylandı: kuyruktan temizle.
    public mutating func acknowledge(_ ids: [UUID]) {
        let acknowledged = Set(ids)
        outbound.removeAll { acknowledged.contains($0.id) }
        statistics.pending = outbound.count
        statistics.uploaded += ids.count
        statistics.lastTransferAt = Date()
    }

    /// Gönderim başarısız: tüm kuyruğu koru, yeniden deneme sayacını artır.
    public mutating func handleFailure() {
        statistics.failures += 1
        retryCount += 1
    }

    /// Yeniden deneme sınırı aşıldı mı?
    public var isRetryExhausted: Bool { retryCount >= maximumRetries }

    /// Kuyruktaki ilk kaydı yeniden dener (gönderilemeyenler sırada bekler).
    public mutating func retryNext() -> DiveSyncRecord? {
        guard !isRetryExhausted, !outbound.isEmpty else { return nil }
        return outbound.first
    }

    // MARK: - Inbound

    /// Gelen kayıtları kuyruğa alır (aynı `id` için en yenisi kalır).
    public mutating func receive(_ records: [DiveSyncRecord]) {
        for record in records {
            statistics.received += 1
            if let index = inbound.firstIndex(where: { $0.id == record.id }) {
                if record.updatedAt > inbound[index].updatedAt { inbound[index] = record }
            } else {
                inbound.append(record)
            }
        }
    }

    /// Gelen kayıtları mevcut kayıtlarla karşılaştırır ve uygulama planını üretir.
    ///
    /// - Note: Çakışma kuralı: aynı `id` için daha yeni `updatedAt` kazanır.
    ///   Eşitlikte yerel kayıt korunur (veri kaybı olmaz).
    public mutating func mergePlan(against existing: [LoggedDive]) -> SyncMergeResult {
        var result = SyncMergeResult()
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for record in inbound {
            guard let local = byID[record.id] else {
                result.inserted.append(record.dive)
                continue
            }
            if record.updatedAt > local.updatedAt {
                result.updated.append(record.dive)
                statistics.conflicts += 1
            } else if record.updatedAt < local.updatedAt {
                // Yerel kayıt daha yeni → karşı tarafa yeniden gönderilecek
                result.orphaned.append(record.dive)
            } else {
                result.unchanged += 1
            }
        }
        return result
    }

    /// Gelen kayıtları uygular ve kuyruğu temizler (istatistik güncellenir).
    public mutating func applyMerge(_ result: SyncMergeResult,
                                     to store: DiveLogStore) throws {
        for dive in result.inserted { try store.save(dive) }
        for dive in result.updated { try store.save(dive) }
        statistics.applied += result.changeCount
        inbound.removeAll { record in
            result.inserted.contains { $0.id == record.dive.id }
                || result.updated.contains { $0.id == record.dive.id }
        }
    }

    /// Gelen kayıtları uygular ve bağlantıyı sıfırlar.
    public mutating func reset() {
        outbound.removeAll()
        inbound.removeAll()
        retryCount = 0
        statistics = SyncStatistics()
    }

    /// Kuyrukta bekleyen kayıt var mı?
    public var hasPending: Bool { !outbound.isEmpty }

    /// Bekleyen kayıt kimlikleri (arayüzde rozet için).
    public var pendingIDs: [UUID] { outbound.map(\.id) }

    // MARK: - Yardımcı dönüştürmeler

    /// Kayıtları JSON verisine çevirir (WatchConnectivity `userInfo`/`file`).
    public static func encode(_ records: [DiveSyncRecord]) throws -> Data {
        try JSONEncoder().encode(records)
    }

    /// JSON verisinden kayıtları çözer; bozuk veri hâlinde hata fırlatır.
    ///
    /// - Note: **Boş (yalnızca boşluk içeren) veri hata değildir** ve boş dizi
    ///   döndürülür. Gerçek `WCSession` aktarımlarında boş ya da kesilmiş
    ///   paket sık görülür (uygulama askıya alındığında); bunu istisna olarak
    ///   ele almak senkronizasyon döngüsünü durdururdu.
    public static func decode(_ data: Data) throws -> [DiveSyncRecord] {
        let significant = data.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
        guard !significant.isEmpty else { return [] }
        return try JSONDecoder().decode([DiveSyncRecord].self, from: data)
    }

    /// Tek kayıt verisi (hata ayıklama/döküm için).
    public static func encodeSingle(_ record: DiveSyncRecord) throws -> Data {
        try JSONEncoder().encode(record)
    }

    public static func decodeSingle(_ data: Data) throws -> DiveSyncRecord {
        try JSONDecoder().decode(DiveSyncRecord.self, from: data)
    }
}

/// Testler ve simülasyon için döngüsel taşıma katmanı.
///
/// **Gerçekçilik notu:** `WCSession` geri çağrılarını **asenkron** yapar.
/// Bu sınıf da öyle davranır: gönderim ve teslim **kuyruğa** alınır,
/// geri çağrılar `drain()` ile tetiklenir. Böylece `DiveSyncEngine` mutating
/// bir metot çağrısı sırasında aynı değişkene ikinci kez erişilmez
/// (Swift çalışma zamanı "fatal access conflict" hatası).
public final class LoopbackSyncTransport: DiveSyncTransport, @unchecked Sendable {
    public var onRecords: (([DiveSyncRecord]) -> Void)?
    public var onAcknowledgement: (([UUID]) -> Void)?
    public var onFailure: ((Error) -> Void)?
    public var isReachable = true

    public private(set) var sent: [DiveSyncRecord] = []
    public private(set) var activateCount = 0

    private var pendingCallbacks: [() -> Void] = []

    public init() {}

    public func activate() { activateCount += 1 }
    public func deactivate() { isReachable = false }

    public func send(_ records: [DiveSyncRecord]) {
        guard isReachable else {
            queue { [weak self] in self?.onFailure?(DiveSyncError.unreachable) }
            return
        }
        sent.append(contentsOf: records)
        let ids = records.map(\.id)
        queue { [weak self] in self?.onAcknowledgement?(ids) }
    }

    /// Karşı taraftan kayıt gönderir (asenkron).
    public func deliver(_ records: [DiveSyncRecord]) {
        queue { [weak self] in self?.onRecords?(records) }
    }

    /// Bekleyen geri çağrıları tetikler (WCSession'ın "delivery" anı).
    public func drain() {
        let callbacks = pendingCallbacks
        pendingCallbacks = []
        for callback in callbacks { callback() }
    }

    /// Bekleyen geri çağrı sayısı.
    public var pendingCallbackCount: Int { pendingCallbacks.count }

    /// Gönderimi başarısız yapar.
    public func failSend() {
        isReachable = false
        queue { [weak self] in self?.onFailure?(DiveSyncError.unreachable) }
    }

    private func queue(_ callback: @escaping () -> Void) {
        pendingCallbacks.append(callback)
    }
}

/// Senkronizasyon hataları.
public enum DiveSyncError: Error, Equatable, LocalizedError {
    case unreachable
    case decodingFailed
    case versionMismatch(local: Int, remote: Int)

    public var errorDescription: String? {
        switch self {
        case .unreachable: return "Karşı cihaza ulaşılamıyor"
        case .decodingFailed: return "Gelen veri okunamadı"
        case .versionMismatch(let local, let remote):
            return "Sürüm uyuşmazlığı (yerel \(local), uzak \(remote))"
        }
    }

    /// Protokol sürümü uyumlu mu?
    public static func isCompatible(local: Int = DiveSyncRecord.currentVersion,
                                    remote: Int) -> Bool {
        local == remote
    }
}