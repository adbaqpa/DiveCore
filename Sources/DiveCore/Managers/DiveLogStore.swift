import Foundation

/// Dalış günlüğü deposu (ADIM 5).
///
/// Arayüz platformdan bağımsızdır: uygulama `InMemoryDiveLogStore` (testler),
/// `SwiftDataDiveLogStore` (cihaz) veya ileride Core Data tabanlı bir
/// uygulamayı görebilir.
public protocol DiveLogStore: AnyObject {

    /// Tek kayıt ekler veya (aynı `id` ile) günceller.
    func save(_ dive: LoggedDive) throws

    /// Toplu ekleme/güncelleme.
    func saveAll(_ dives: [LoggedDive]) throws

    /// Kimliğe göre tek kayıt.
    func dive(id: UUID) throws -> LoggedDive?

    /// Tüm kayıtlar (en yeni önce).
    func allDives() throws -> [LoggedDive]

    /// En fazla `limit` kayıt (en yeni).
    func recentDives(limit: Int) throws -> [LoggedDive]

    /// Tarih aralığındaki kayıtlar (en yeni önce).
    func dives(from start: Date, to end: Date) throws -> [LoggedDive]

    /// Sil.
    func delete(id: UUID) throws

    /// Tümünü sil.
    func deleteAll() throws

    /// Kayıt sayısı.
    var diveCount: Int { get }
}

/// Testler ve önizlemeler için bellek içi depo.
///
/// Aynı `id` ile ikinci kez `save` çağrılırsa **günceller** (senkronizasyon
/// çakışma çözümüyle uyumlu).
public final class InMemoryDiveLogStore: DiveLogStore, @unchecked Sendable {

    private var storage: [UUID: LoggedDive] = [:]
    private let lock = NSLock()

    public init(dives: [LoggedDive] = []) {
        for dive in dives { storage[dive.id] = dive }
    }

    public var diveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    public func save(_ dive: LoggedDive) throws {
        lock.lock(); defer { lock.unlock() }
        storage[dive.id] = dive
    }

    public func saveAll(_ dives: [LoggedDive]) throws {
        lock.lock(); defer { lock.unlock() }
        for dive in dives { storage[dive.id] = dive }
    }

    public func dive(id: UUID) throws -> LoggedDive? {
        lock.lock(); defer { lock.unlock() }
        return storage[id]
    }

    public func allDives() throws -> [LoggedDive] {
        lock.lock(); defer { lock.unlock() }
        return sorted(Array(storage.values))
    }

    public func recentDives(limit: Int) throws -> [LoggedDive] {
        lock.lock(); defer { lock.unlock() }
        return Array(sorted(Array(storage.values)).prefix(max(0, limit)))
    }

    public func dives(from start: Date, to end: Date) throws -> [LoggedDive] {
        lock.lock(); defer { lock.unlock() }
        return sorted(Array(storage.values).filter { $0.startDate >= start && $0.startDate <= end })
    }

    public func delete(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: id)
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }

    private func sorted(_ values: [LoggedDive]) -> [LoggedDive] {
        values.sorted { $0.startDate > $1.startDate }
    }
}