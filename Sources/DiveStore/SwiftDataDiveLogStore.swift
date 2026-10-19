// SwiftData tabanlı dalış günlüğü deposu.
//
// ⚠️ Bu dosya yalnızca iOS/watchOS'ta derlenir (`#if os(watchOS) || os(iOS)`).
// SwiftData'nın `@Model` makrosu Xcode araç zincirinin parçasıdır; yalnızca
// Command Line Tools bulunan bir makinede derlenemez. Bu yüzden tüm mantık
// (`LoggedDive`, `DiveLogStore` protokolü, senkronizasyon) saf Swift olan
// `DiveCore` modülündedir ve platformdan bağımsız test edilir; burada yalnızca
// SwiftData ile saf veri modeli arasındaki eşleme vardır.
#if os(watchOS) || os(iOS)
import Foundation
import SwiftData
import DiveCore

/// SwiftData varlığı: dalış kaydı (kalıcı model).
@Model
public final class StoredDive {
    /// Kararlı senkronizasyon kimliği (`LoggedDive.stableID`)
    @Attribute(.unique) public var identifier: UUID
    public var startDate: Date
    public var endDate: Date
    public var updatedAt: Date
    public var originDevice: String

    public var totalDiveTime: Double
    public var maxDepth: Double
    public var averageDepth: Double
    public var bottomTime: Double
    public var minimumTemperature: Double
    public var maximumTemperature: Double
    public var maxAscentRate: Double
    public var maxDescentRate: Double

    /// Gaz listesi JSON olarak saklanır (ilişkisel tablodan kaçınmak için)
    public var gasesJSON: Data
    public var startGasIndex: Int
    public var maxPO2: Double
    public var maxGF99: Double
    public var cnsPercent: Double
    public var otuUnits: Double

    public var hadDecoObligation: Bool
    public var decoStopsJSON: Data
    public var penaltiesJSON: Data
    public var safetyStopCompleted: Bool
    public var safetyStopAccumulated: Double
    public var noFlyTime: Double

    public var score: Int
    public var gradeRaw: String
    public var markerCount: Int

    /// Profil örnekleri JSON (kayıt başına tek satır → hızlı yazma)
    public var samplesJSON: Data

    public init(dive: LoggedDive) {
        self.identifier = dive.id
        self.startDate = dive.startDate
        self.endDate = dive.endDate
        self.updatedAt = dive.updatedAt
        self.originDevice = dive.originDevice
        self.totalDiveTime = dive.totalDiveTime
        self.maxDepth = dive.maxDepth
        self.averageDepth = dive.averageDepth
        self.bottomTime = dive.bottomTime
        self.minimumTemperature = dive.minimumTemperature
        self.maximumTemperature = dive.maximumTemperature
        self.maxAscentRate = dive.maxAscentRate
        self.maxDescentRate = dive.maxDescentRate
        self.gasesJSON = (try? JSONEncoder().encode(dive.gases)) ?? Data()
        self.startGasIndex = dive.startGasIndex
        self.maxPO2 = dive.maxPO2
        self.maxGF99 = dive.maxGF99
        self.cnsPercent = dive.cnsPercent
        self.otuUnits = dive.otuUnits
        self.hadDecoObligation = dive.hadDecoObligation
        self.decoStopsJSON = (try? JSONEncoder().encode(dive.decoStops)) ?? Data()
        self.penaltiesJSON = (try? JSONEncoder().encode(dive.penalties)) ?? Data()
        self.safetyStopCompleted = dive.safetyStopCompleted
        self.safetyStopAccumulated = dive.safetyStopAccumulated
        self.noFlyTime = dive.noFlyTime
        self.score = dive.score
        self.gradeRaw = dive.grade.rawValue
        self.markerCount = dive.markerCount
        self.samplesJSON = (try? JSONEncoder().encode(dive.samples)) ?? Data()
    }

    /// Saf modele geri çevirir.
    public func toLoggedDive() -> LoggedDive {
        LoggedDive(
            id: identifier,
            startDate: startDate, endDate: endDate,
            totalDiveTime: totalDiveTime, maxDepth: maxDepth,
            averageDepth: averageDepth, bottomTime: bottomTime,
            minimumTemperature: minimumTemperature, maximumTemperature: maximumTemperature,
            maxAscentRate: maxAscentRate, maxDescentRate: maxDescentRate,
            gases: (try? JSONDecoder().decode([GasMix].self, from: gasesJSON)) ?? [.air],
            startGasIndex: startGasIndex,
            maxPO2: maxPO2, maxGF99: maxGF99, cnsPercent: cnsPercent, otuUnits: otuUnits,
            hadDecoObligation: hadDecoObligation,
            decoStops: (try? JSONDecoder().decode([DecoStopRecord].self, from: decoStopsJSON)) ?? [],
            safetyStopCompleted: safetyStopCompleted,
            safetyStopAccumulated: safetyStopAccumulated,
            noFlyTime: noFlyTime,
            score: score,
            grade: DiveGrade(rawValue: gradeRaw) ?? .good,
            penalties: (try? JSONDecoder().decode([DivePenalty].self, from: penaltiesJSON)) ?? [],
            markerCount: markerCount,
            samples: (try? JSONDecoder().decode([DiveSample].self, from: samplesJSON)) ?? [],
            updatedAt: updatedAt,
            originDevice: originDevice)
    }
}

/// `DiveLogStore` protokolünün SwiftData uygulaması.
@MainActor
public final class SwiftDataDiveLogStore: DiveLogStore {

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Kalıcı kapsayıcı (uygulama başlangıcında bir kez oluşturulur).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: StoredDive.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    public convenience init(container: ModelContainer) {
        self.init(context: container.mainContext)
    }

    public var diveCount: Int {
        (try? context.fetchCount(FetchDescriptor<StoredDive>())) ?? 0
    }

    public func save(_ dive: LoggedDive) throws {
        let identifier = dive.id
        let descriptor = FetchDescriptor<StoredDive>(predicate: #Predicate { $0.identifier == identifier })
        if let existing = try context.fetch(descriptor).first {
            let updated = StoredDive(dive: dive)
            existing.startDate = updated.startDate
            existing.endDate = updated.endDate
            existing.updatedAt = updated.updatedAt
            existing.totalDiveTime = updated.totalDiveTime
            existing.maxDepth = updated.maxDepth
            existing.averageDepth = updated.averageDepth
            existing.samplesJSON = updated.samplesJSON
            existing.score = updated.score
            existing.gradeRaw = updated.gradeRaw
        } else {
            context.insert(StoredDive(dive: dive))
        }
        try context.save()
    }

    public func saveAll(_ dives: [LoggedDive]) throws {
        for dive in dives { try save(dive) }
    }

    public func dive(id: UUID) throws -> LoggedDive? {
        let identifier = id
        let descriptor = FetchDescriptor<StoredDive>(predicate: #Predicate { $0.identifier == identifier })
        return try context.fetch(descriptor).first?.toLoggedDive()
    }

    public func allDives() throws -> [LoggedDive] {
        let descriptor = FetchDescriptor<StoredDive>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return try context.fetch(descriptor).map { $0.toLoggedDive() }
    }

    public func recentDives(limit: Int) throws -> [LoggedDive] {
        var descriptor = FetchDescriptor<StoredDive>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = max(0, limit)
        return try context.fetch(descriptor).map { $0.toLoggedDive() }
    }

    public func dives(from start: Date, to end: Date) throws -> [LoggedDive] {
        let descriptor = FetchDescriptor<StoredDive>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate <= end },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        return try context.fetch(descriptor).map { $0.toLoggedDive() }
    }

    public func delete(id: UUID) throws {
        let identifier = id
        let descriptor = FetchDescriptor<StoredDive>(predicate: #Predicate { $0.identifier == identifier })
        for item in try context.fetch(descriptor) { context.delete(item) }
        try context.save()
    }

    public func deleteAll() throws {
        for item in try context.fetch(FetchDescriptor<StoredDive>()) { context.delete(item) }
        try context.save()
    }
}
#endif
