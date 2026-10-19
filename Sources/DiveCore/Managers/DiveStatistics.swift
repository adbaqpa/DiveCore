import Foundation

/// Günlük dalış istatistikleri (CNS/OTU toplamları dahil).
///
/// ADIM 5'te kalıcılık üstüne kurulan toplulaştırma. OTU/CNS **günlük**
/// kümülatif değerlerdir (NOAA), bu yüzden tek dalışla değil gün
/// toplamıyla değerlendirilir.
public struct DailyDiveTotals: Equatable, Codable, Sendable, Identifiable {

    public var day: Date
    public var diveCount: Int
    public var totalDiveTime: TimeInterval
    public var maxDepth: Double
    /// Günün toplam CNS yüzdesi
    public var cnsSum: Double
    /// Günün toplam OTU birimi
    public var otuSum: Double
    /// Günün en yüksek GF99'ı
    public var peakGF99: Double

    public var id: Date { day }

    /// OTU/CNS için günlük limitler (NOAA çerçevesi)
    public static let dailyOTULimit: Double = 80
    public static let dailyCNSLimit: Double = 100

    /// Otu için yarı ömrü (saniye). NOAA: OTU atılımı yaklaşık 2 saatlik
    /// yarı ömürle modellenir.
    public static let otuHalfLife: TimeInterval = 2 * 3600

    /// CNS saatinin yarı ömrü (saniye) — daha yavaş (~4 saat)
    public static let cnsHalfLife: TimeInterval = 4 * 3600

    public init(day: Date, diveCount: Int = 0, totalDiveTime: TimeInterval = 0,
                maxDepth: Double = 0, cnsSum: Double = 0, otuSum: Double = 0,
                peakGF99: Double = 0) {
        self.day = day
        self.diveCount = diveCount
        self.totalDiveTime = totalDiveTime
        self.maxDepth = maxDepth
        self.cnsSum = cnsSum
        self.otuSum = otuSum
        self.peakGF99 = peakGF99
    }

    /// Bir dalışı güne ekler (yeni gün ise yeni kayıt başlatır).
    public mutating func add(_ dive: LoggedDive) {
        let key = Calendar.current.startOfDay(for: dive.startDate)
        guard key == day else { return }   // farklı gün — `add(dive:)` çağıran sorumlu
        diveCount += 1
        totalDiveTime += dive.totalDiveTime
        maxDepth = max(maxDepth, dive.maxDepth)
        cnsSum += dive.cnsPercent
        otuSum += dive.otuUnits
        peakGF99 = max(peakGF99, dive.maxGF99)
    }

    // MARK: - Değerlendirme

    public var otuPercent: Double { otuSum / DailyDiveTotals.dailyOTULimit * 100 }
    public var cnsPercent: Double { cnsSum / DailyDiveTotals.dailyCNSLimit * 100 }

    public var isOTUExceeding: Bool { otuSum > DailyDiveTotals.dailyOTULimit }
    public var isCNSExceeding: Bool { cnsSum > DailyDiveTotals.dailyCNSLimit }

    /// Sonraki dalıştan önce önerilen bekleme (saniye).
    ///
    /// - Not: Yaklaşıktır — OTU ve CNS yarı ömürle söner varsayılır.
    public var recommendedRest: TimeInterval {
        rest(forOTUPercent: 50, cnsPercent: 50)
    }

    /// Belirli eşiklere inene kadar gereken süre (saniye).
    public func rest(forOTUPercent otuTarget: Double = 50,
                     cnsPercent cnsTarget: Double = 50) -> TimeInterval {
        var wait: TimeInterval = 0

        if otuSum > 0 {
            let target = max(0.1, DailyDiveTotals.dailyOTULimit * otuTarget / 100)
            if otuSum > target {
                let ratio = target / otuSum
                wait = max(wait, DailyDiveTotals.otuHalfLife * log2(1 / ratio))
            }
        }
        if cnsSum > 0 {
            let target = max(0.1, DailyDiveTotals.dailyCNSLimit * cnsTarget / 100)
            if cnsSum > target {
                let ratio = target / cnsSum
                wait = max(wait, DailyDiveTotals.cnsHalfLife * log2(1 / ratio))
            }
        }
        // 15 dakikaya yuvarlanır (kullanıcıya anlamlı bir süre)
        return (wait / 900).rounded(.up) * 900
    }

    /// Ekranda gösterilecek öneri metni.
    public func advice(afterRest: Bool = false) -> String {
        if isOTUExceeding && isCNSExceeding {
            return afterRest
                ? "OTU/CNS yüksek — bir süre daha kal (muhafazakâr dalış planla)"
                : "Günlük OTU ve CNS limiti aşıldı — bugün başka dalış önermiyoruz"
        }
        if isOTUExceeding {
            let rest = DurationFormatter.hoursMinutes(rest())
            return afterRest
                ? "OTU yüksek (\(Int(otuPercent))%) — \(rest) daha bekle"
                : "Günlük OTU limiti aşıldı — \(rest) ara ver"
        }
        if isCNSExceeding {
            let rest = DurationFormatter.hoursMinutes(rest())
            return afterRest
                ? "CNS yüksek (\(Int(cnsPercent))%) — \(rest) daha bekle"
                : "Günlük CNS limiti aşıldı — \(rest) ara ver"
        }
        return "Günlük OTU/CNS sınırları içinde (\(Int(otuPercent))% / \(Int(cnsPercent))%)"
    }
}

/// Günlük toplamların günlere göre gruplanmış hâli.
public enum DailyTotalsBuilder {
    /// Kayıtları güne göre gruplar (en yeni gün önce).
    public static func make(from dives: [LoggedDive]) -> [DailyDiveTotals] {
        var groups: [Date: DailyDiveTotals] = [:]
        for dive in dives {
            let key = Calendar.current.startOfDay(for: dive.startDate)
            if groups[key] == nil {
                groups[key] = DailyDiveTotals(day: key)
            }
            groups[key]?.add(dive)
        }
        return groups.values.sorted { $0.day > $1.day }
    }

    /// Belirli bir günün toplamları.
    public static func forDay(_ day: Date, from dives: [LoggedDive]) -> DailyDiveTotals {
        let key = Calendar.current.startOfDay(for: day)
        var totals = DailyDiveTotals(day: key)
        for dive in dives where Calendar.current.isDate(dive.startDate, inSameDayAs: key) {
            totals.add(dive)
        }
        return totals
    }
}

/// Tüm günlük için genel istatistikler.
public struct DiveStatistics: Equatable, Codable, Sendable {
    public var diveCount: Int
    public var totalDiveTime: TimeInterval
    public var deepestDive: Double
    public var longestDiveTime: TimeInterval
    public var averageDiveDepth: Double
    public var totalDecoTime: TimeInterval
    public var divesWithDeco: Int
    public var completedSafetyStops: Int
    public var bestGrade: DiveGrade
    public var totalCNS: Double
    public var totalOTU: Double
    public var firstDiveDate: Date?
    public var lastDiveDate: Date?
    /// Gaz kullanım sayıları (etiket → dalış sayısı)
    public var gasUsage: [String: Int]

    public init(diveCount: Int = 0, totalDiveTime: TimeInterval = 0,
                deepestDive: Double = 0, longestDiveTime: TimeInterval = 0,
                averageDiveDepth: Double = 0, totalDecoTime: TimeInterval = 0,
                divesWithDeco: Int = 0, completedSafetyStops: Int = 0,
                bestGrade: DiveGrade = .good, totalCNS: Double = 0, totalOTU: Double = 0,
                firstDiveDate: Date? = nil, lastDiveDate: Date? = nil,
                gasUsage: [String: Int] = [:]) {
        self.diveCount = diveCount
        self.totalDiveTime = totalDiveTime
        self.deepestDive = deepestDive
        self.longestDiveTime = longestDiveTime
        self.averageDiveDepth = averageDiveDepth
        self.totalDecoTime = totalDecoTime
        self.divesWithDeco = divesWithDeco
        self.completedSafetyStops = completedSafetyStops
        self.bestGrade = bestGrade
        self.totalCNS = totalCNS
        self.totalOTU = totalOTU
        self.firstDiveDate = firstDiveDate
        self.lastDiveDate = lastDiveDate
        self.gasUsage = gasUsage
    }

    /// Ortalama dalış derinliği (ağırlıklı süre yerine dalış başına).
    public static func make(from dives: [LoggedDive]) -> DiveStatistics {
        guard !dives.isEmpty else { return DiveStatistics() }

        let totalTime = dives.reduce(0) { $0 + $1.totalDiveTime }
        let depths = dives.map(\.maxDepth)
        let deepest = depths.max() ?? 0
        let longest = dives.map(\.totalDiveTime).max() ?? 0
        let averageDepth = depths.reduce(0, +) / Double(dives.count)

        var usage: [String: Int] = [:]
        for dive in dives {
            usage[dive.startGas.label, default: 0] += 1
        }

        return DiveStatistics(
            diveCount: dives.count,
            totalDiveTime: totalTime,
            deepestDive: deepest,
            longestDiveTime: longest,
            averageDiveDepth: averageDepth,
            totalDecoTime: dives.reduce(0) { $0 + $1.decoStops.reduce(0) { $0 + $1.duration } },
            divesWithDeco: dives.filter(\.hadDecoObligation).count,
            completedSafetyStops: dives.filter(\.safetyStopCompleted).count,
            bestGrade: dives.map(\.grade).min(by: { $0.stars < $1.stars }) ?? .good,
            totalCNS: dives.reduce(0) { $0 + $1.cnsPercent },
            totalOTU: dives.reduce(0) { $0 + $1.otuUnits },
            firstDiveDate: dives.map(\.startDate).min(),
            lastDiveDate: dives.map(\.startDate).max(),
            gasUsage: usage)
    }
}