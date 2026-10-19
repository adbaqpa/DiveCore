import Foundation

/// Kalıcılık ve senkronizasyondan bağımsız dalış kaydı.
///
/// ADIM 5: hem SwiftData modeline hem de WatchConnectivity teline çevrilebilir
/// tek veri modeli. `LogEntry` + `DiveReport` analizinden üretilir.
public struct LoggedDive: Codable, Equatable, Sendable, Identifiable {

    public var id: UUID
    /// Dalış başlangıcı (eşsizlik anahtarı olarak da kullanılır)
    public var startDate: Date
    public var endDate: Date

    // Profil özeti
    public var totalDiveTime: TimeInterval
    public var maxDepth: Double
    public var averageDepth: Double
    public var bottomTime: TimeInterval
    public var minimumTemperature: Double
    public var maximumTemperature: Double
    public var maxAscentRate: Double
    public var maxDescentRate: Double

    // Gaz / oksijen
    public var gases: [GasMix]
    public var startGasIndex: Int
    public var maxPO2: Double
    public var maxGF99: Double
    public var cnsPercent: Double
    public var otuUnits: Double

    // Deko / güvenlik
    public var hadDecoObligation: Bool
    public var decoStops: [DecoStopRecord]
    public var safetyStopCompleted: Bool
    public var safetyStopAccumulated: TimeInterval
    public var noFlyTime: TimeInterval

    // Değerlendirme
    public var score: Int
    public var grade: DiveGrade
    public var penalties: [DivePenalty]
    public var markerCount: Int

    // Profil örnekleri (grafik ve detay ekranı için)
    public var samples: [DiveSample]

    /// Kaynağın güncellenme zamanı — senkronizasyonda çakışma çözümü için
    public var updatedAt: Date

    /// Bu kaydın bu cihazda üretilip üretilmediği (WatchConnectivity)
    public var originDevice: String

    /// Kayıt sürümü (gelecekteki şema değişiklikleri için)
    public var schemaVersion: Int = 1

    public init(id: UUID = UUID(),
                startDate: Date, endDate: Date,
                totalDiveTime: TimeInterval, maxDepth: Double, averageDepth: Double,
                bottomTime: TimeInterval,
                minimumTemperature: Double, maximumTemperature: Double,
                maxAscentRate: Double, maxDescentRate: Double,
                gases: [GasMix], startGasIndex: Int,
                maxPO2: Double, maxGF99: Double, cnsPercent: Double, otuUnits: Double,
                hadDecoObligation: Bool, decoStops: [DecoStopRecord],
                safetyStopCompleted: Bool, safetyStopAccumulated: TimeInterval,
                noFlyTime: TimeInterval,
                score: Int, grade: DiveGrade, penalties: [DivePenalty],
                markerCount: Int, samples: [DiveSample],
                updatedAt: Date, originDevice: String) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.totalDiveTime = totalDiveTime
        self.maxDepth = maxDepth
        self.averageDepth = averageDepth
        self.bottomTime = bottomTime
        self.minimumTemperature = minimumTemperature
        self.maximumTemperature = maximumTemperature
        self.maxAscentRate = maxAscentRate
        self.maxDescentRate = maxDescentRate
        self.gases = gases.isEmpty ? [.air] : gases
        self.startGasIndex = startGasIndex
        self.maxPO2 = maxPO2
        self.maxGF99 = maxGF99
        self.cnsPercent = cnsPercent
        self.otuUnits = otuUnits
        self.hadDecoObligation = hadDecoObligation
        self.decoStops = decoStops
        self.safetyStopCompleted = safetyStopCompleted
        self.safetyStopAccumulated = safetyStopAccumulated
        self.noFlyTime = noFlyTime
        self.score = score
        self.grade = grade
        self.penalties = penalties
        self.markerCount = markerCount
        self.samples = samples
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    // MARK: - Oluşturucular

    /// `LogEntry` + `DiveReport` çiftinden kayıt üretir.
    ///
    /// - Important: `id`, `startDate`'e özgü **kararlı** bir UUID üretir
    ///   (`stableID`), böylece aynı dalış iki cihazda da aynı kimliğe sahip
    ///   olur ve senkronizasyonda kopya oluşmaz.
    public static func make(log: LogEntry, report: DiveReport, originDevice: String = "watch") -> LoggedDive {
        LoggedDive(
            id: stableID(for: log.startDate, device: originDevice),
            startDate: log.startDate,
            endDate: log.endDate ?? log.startDate.addingTimeInterval(log.totalDiveTime),
            totalDiveTime: log.totalDiveTime,
            maxDepth: log.maxDepth,
            averageDepth: log.averageDepth,
            bottomTime: report.bottomTime,
            minimumTemperature: log.waterTemperatureMin,
            maximumTemperature: log.waterTemperatureMax,
            maxAscentRate: report.maxAscentRate,
            maxDescentRate: report.maxDescentRate,
            gases: log.gases,
            startGasIndex: log.startGasIndex,
            maxPO2: log.maxPO2,
            maxGF99: log.maxGF99,
            cnsPercent: log.cnsPercent,
            otuUnits: log.otuUnits,
            hadDecoObligation: log.hadDecoObligation,
            decoStops: report.decoStops,
            safetyStopCompleted: log.safetyStopCompleted,
            safetyStopAccumulated: log.safetyStopAccumulated,
            noFlyTime: log.noFlyTime,
            score: report.score,
            grade: report.grade,
            penalties: report.penalties,
            markerCount: report.markerCount,
            samples: log.samples,
            updatedAt: Date(),
            originDevice: originDevice)
    }

    /// Dalış başlangıcına ve cihaza göre kararlı kimlik (aynı dalışın kopyasını
    /// engeller).
    public static func stableID(for date: Date, device: String = "watch") -> UUID {
        let seconds = Int(date.timeIntervalSince1970.rounded())
        let bytes = Array(String(format: "%010d", seconds).utf8) + Array(device.utf8)
        // Basit FNV-1a → 16 bayt
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        // UUID 16 bayttan oluşur: 8 bayt karma + 8 bayt sabit (türetilmiş zaman damgası)
        var result = [UInt8]()
        var value = hash
        for _ in 0..<16 {
            if value == 0 && result.count >= 8 {
                // Kalan baytlar sabit (aynı girdi → aynı UUID)
                result.append(UInt8(truncatingIfNeeded: 0xA5 &+ UInt8(result.count)))
            } else {
                result.append(UInt8(truncatingIfNeeded: value & 0xff))
                value >>= 8
            }
        }
        // Sürüm/variant baytları (RFC 4122 v4-benzeri)
        result[6] = (result[6] & 0x0f) | 0x40
        result[8] = (result[8] & 0x3f) | 0x80
        return UUID(uuid: (result[0], result[1], result[2], result[3],
                           result[4], result[5], result[6], result[7],
                           result[8], result[9], result[10], result[11],
                           result[12], result[13], result[14], result[15]))
    }

    // MARK: - Türetilmiş

    /// Başlangıç gazı
    public var startGas: GasMix {
        gases.indices.contains(startGasIndex) ? gases[startGasIndex] : .air
    }

    /// Gaz etiketleri ("Air / EAN32")
    public var gasLabels: String {
        gases.map(\.label).joined(separator: " / ")
    }

    /// "24 dk" biçiminde süre.
    public var durationText: String { DurationFormatter.hoursMinutes(totalDiveTime) }

    /// Tam nitelikli ad (arama/filtre için): "30.0 m · 24 dk · Air"
    public var displayTitle: String {
        String(format: "%.1f m · %@ · %@", maxDepth, durationText, startGas.label)
    }

    /// Günlük anahtar (yerel takvim günü başlangıcı).
    public var dayKey: Date { Calendar.current.startOfDay(for: startDate) }

    /// Kayıt değişikliği var mı?
    public func isNewer(than other: LoggedDive) -> Bool {
        updatedAt > other.updatedAt
    }
}