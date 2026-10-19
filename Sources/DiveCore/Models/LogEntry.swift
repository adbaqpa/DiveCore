import Foundation

/// Dalış profilinin tek bir zaman noktası.
///
/// Uygulama içinde **en fazla 10 saniyede bir** kaydedilir (pil/veri dengesi),
/// ADIM 2'deki simülatör ve ADIM 3'teki UI aynı `DiveSample` üzerinden çalışır.
public struct DiveSample: Codable, Equatable, Sendable, Identifiable {

    /// Dalış başlangıcından itibaren geçen süre (saniye).
    public var elapsed: TimeInterval
    /// Anlık derinlik (m)
    public var depth: Double
    /// Su sıcaklığı (°C)
    public var temperature: Double
    /// Ambient basınç (bar)
    public var ambientPressure: Double
    /// Solunan PO2 (bar)
    public var po2: Double
    /// Çıkış hızı (m/dk)
    public var ascentRate: Double
    /// Kullanılan gazın dizini
    public var gasIndex: Int
    /// GF99 (%)
    public var gf99: Double
    /// Tavan (ceiling) (m)
    public var ceiling: Double
    /// En baskın kompartmanın N2 basıncı (bar) — gaz yükü grafiği için.
    public var leadingTissuePressure: Double
    /// Enlem (derece) — GPS rotası için; yoksa `nil`.
    public var latitude: Double?
    /// Boylam (derece) — GPS rotası için; yoksa `nil`.
    public var longitude: Double?

    public var id: Int { Int(elapsed) }

    public init(
        elapsed: TimeInterval,
        depth: Double,
        temperature: Double,
        ambientPressure: Double,
        po2: Double,
        ascentRate: Double = 0,
        gasIndex: Int = 0,
        gf99: Double = 0,
        ceiling: Double = 0,
        leadingTissuePressure: Double = 0.79,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.elapsed = elapsed
        self.depth = depth
        self.temperature = temperature
        self.ambientPressure = ambientPressure
        self.po2 = po2
        self.ascentRate = ascentRate
        self.gasIndex = gasIndex
        self.gf99 = gf99
        self.ceiling = ceiling
        self.leadingTissuePressure = leadingTissuePressure
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - LogEntry

/// Tamamlanmış dalışın kalıcı kaydı.
///
/// `Codable` + `Sendable` olduğu için:
/// - SwiftData `@Model` ile sarmalanabilir (ADIM 5),
/// - `WatchConnectivity` ile iPhone'a aktarılabilir,
/// - JSON olarak dışa aktarılabilir.
///
/// Not: SwiftUI/Foundation dışında hiçbir bağımlılığı yoktur; saf veri tipidir.
public struct LogEntry: Codable, Equatable, Sendable, Identifiable {

    // MARK: Kimlik ve zaman

    public let id: UUID
    public var startDate: Date
    public var endDate: Date?
    /// Dalış sitesi adı / GPS etiketi
    public var location: String?
    /// Cihaz seri veya kullanıcı etiketi
    public var computerSerial: String?

    // MARK: Gazlar

    /// Kullanılan gazların sırası (geçiş dahil)
    public var gases: [GasMix]
    /// Başlangıç gazının indeksi
    public var startGasIndex: Int

    // MARK: Profil

    /// Zaman serisi — her biri zaman, derinlik, sıcaklık ve gaz yükü içerir.
    public var samples: [DiveSample]

    // MARK: Özet

    public var maxDepth: Double
    public var averageDepth: Double
    public var totalDiveTime: TimeInterval
    public var waterTemperatureStart: Double
    public var waterTemperatureEnd: Double
    public var waterTemperatureMin: Double
    public var waterTemperatureMax: Double

    public var cnsPercent: Double
    public var otuUnits: Double
    public var maxPO2: Double
    public var maxGF99: Double
    public var minimumNoDecompressionLimit: TimeInterval

    public var gradientFactors: GradientFactors
    public var water: DivePhysics.WaterType
    public var hadDecoObligation: Bool
    public var safetyStopCompleted: Bool
    public var safetyStopAccumulated: TimeInterval

    /// Dalış sonundaki tahmini uçuş yasağı (saniye)
    public var noFlyTime: TimeInterval
    /// Yüzeye çıktıktan sonra önerilen yüzey aralığı (saniye)
    public var recommendedSurfaceInterval: TimeInterval

    public var rating: Int          // 1...5 yıldız
    public var notes: String

    // MARK: - Oluşturucu

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        location: String? = nil,
        computerSerial: String? = nil,
        gases: [GasMix] = [.air],
        startGasIndex: Int = 0,
        samples: [DiveSample] = [],
        maxDepth: Double = 0,
        averageDepth: Double = 0,
        totalDiveTime: TimeInterval = 0,
        waterTemperatureStart: Double = 20,
        waterTemperatureEnd: Double = 20,
        waterTemperatureMin: Double = 20,
        waterTemperatureMax: Double = 20,
        cnsPercent: Double = 0,
        otuUnits: Double = 0,
        maxPO2: Double = 0.21,
        maxGF99: Double = 0,
        minimumNoDecompressionLimit: TimeInterval = 0,
        gradientFactors: GradientFactors = .conservative,
        water: DivePhysics.WaterType = .salt,
        hadDecoObligation: Bool = false,
        safetyStopCompleted: Bool = false,
        safetyStopAccumulated: TimeInterval = 0,
        noFlyTime: TimeInterval = 0,
        recommendedSurfaceInterval: TimeInterval = 0,
        rating: Int = 0,
        notes: String = ""
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.computerSerial = computerSerial
        self.gases = gases
        self.startGasIndex = startGasIndex
        self.samples = samples
        self.maxDepth = maxDepth
        self.averageDepth = averageDepth
        self.totalDiveTime = totalDiveTime
        self.waterTemperatureStart = waterTemperatureStart
        self.waterTemperatureEnd = waterTemperatureEnd
        self.waterTemperatureMin = waterTemperatureMin
        self.waterTemperatureMax = waterTemperatureMax
        self.cnsPercent = cnsPercent
        self.otuUnits = otuUnits
        self.maxPO2 = maxPO2
        self.maxGF99 = maxGF99
        self.minimumNoDecompressionLimit = minimumNoDecompressionLimit
        self.gradientFactors = gradientFactors
        self.water = water
        self.hadDecoObligation = hadDecoObligation
        self.safetyStopCompleted = safetyStopCompleted
        self.safetyStopAccumulated = safetyStopAccumulated
        self.noFlyTime = noFlyTime
        self.recommendedSurfaceInterval = recommendedSurfaceInterval
        self.rating = rating
        self.notes = notes
    }

    // MARK: - Türetilmiş diziler (grafikler için)

    /// Derinlik dizisi — istenen alan 1'i `DiveSample` kopyalarından türetir.
    public var depthSeries: [Double] { samples.map(\.depth) }
    /// Sıcaklık dizisi (°C)
    public var temperatureSeries: [Double] { samples.map(\.temperature) }
    /// Zaman dizisi (saniye)
    public var timeSeries: [TimeInterval] { samples.map(\.elapsed) }
    /// PO2 dizisi (bar)
    public var po2Series: [Double] { samples.map(\.po2) }
    /// GF99 dizisi (%)
    public var gf99Series: [Double] { samples.map(\.gf99) }
    /// Bühlmann gaz yükü (en baskın kompartman N2 basıncı) dizisi (bar)
    public var tissueLoadSeries: [Double] { samples.map(\.leadingTissuePressure) }

    /// Başlangıç gazı
    public var startGas: GasMix { gases.indices.contains(startGasIndex) ? gases[startGasIndex] : .air }

    /// Toplam inen/çıkan mesafe (m)
    public var totalVerticalDistance: Double {
        guard samples.count > 1 else { return maxDepth }
        var total: Double = 0
        for index in 1..<samples.count {
            total += abs(samples[index].depth - samples[index - 1].depth)
        }
        return total
    }

    /// Yüzeye çıkışta son derinlik (m) — genellikle 0.
    public var exitDepth: Double { samples.last?.depth ?? 0 }

    /// Dalışta geçirilen toplam süre (saniye).
    public var duration: TimeInterval {
        endDate.map { $0.timeIntervalSince(startDate) } ?? totalDiveTime
    }

    /// Yüzeye çıkışta görülen gaz.
    public var exitGas: GasMix { gases.last ?? .air }

    /// İlk gazın etiketi
    public var startGasLabel: String { startGas.label }
    /// Son gazın etiketi
    public var exitGasLabel: String { exitGas.label }

    /// Başlık: "30.2 m · 24dk · EAN32"
    public var summaryLine: String {
        "\(String(format: "%.1f", maxDepth)) m · \(DurationFormatter.hoursMinutes(totalDiveTime)) · \(exitGasLabel)"
    }

    /// Uçuş yasağının bittiği tahmini zaman (dalış başlangıcına göre).
    public var estimatedNoFlyClearance: Date? {
        guard let end = endDate else { return nil }
        return end.addingTimeInterval(noFlyTime)
    }
}