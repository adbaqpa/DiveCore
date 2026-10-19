import Foundation

/// Yüzey aralığı sırasında doku yükünün çözülmesini takip eder.
///
/// ADIM 4 gereksinimi: "post-dive summary" ve uçuş yasağı geri sayımı.
/// Doku modeli kopyalanır ve yüzeyde (1 bar) ilerletilerek GF99 düşüşü,
/// desatürasyon ve uçuş yasağı kalan süresi hesaplanır.
public struct SurfaceIntervalManager: Equatable, Sendable {

    // MARK: - Ayarlar

    /// Uçuş yasası GF99 eşiği (%)
    public var noFlyGF99Limit: Double
    /// Uçuş yasası güvenlik payı (dakika)
    public var noFlyBufferMinutes: Double
    /// Simülasyon çözünürlüğü (saniye)
    public var resolution: TimeInterval
    /// Yüzeyde kullanılacak gaz (varsayılan: hava)
    public var surfaceGas: GasMix

    // MARK: - Durum

    /// Son dalışın bitiş zamanı
    public private(set) var lastDiveEnd: Date?
    /// Dalış sonu doku durumu
    public private(set) var tissues: TissueModel
    /// Dalış sonu gazları (yüzeyde CO₂ temizleme için)
    public private(set) var lastGas: GasMix
    /// Son dalıştan bu yana geçen süre (saniye)
    public private(set) var elapsed: TimeInterval = 0
    /// Uçuş yasasının **bitiş zamanı** (Date)
    public private(set) var noFlyEnd: Date?
    /// Desatürasyon (GF99 ≤ %20) bitiş zamanı
    public private(set) var desaturationEnd: Date?

    // MARK: - Oluşturucu

    public init(noFlyGF99Limit: Double = 20,
                noFlyBufferMinutes: Double = 60,
                resolution: TimeInterval = 60,
                surfaceGas: GasMix = .air,
                water: DivePhysics.WaterType = .salt) {
        self.noFlyGF99Limit = noFlyGF99Limit
        self.noFlyBufferMinutes = noFlyBufferMinutes
        self.resolution = resolution
        self.surfaceGas = surfaceGas
        self.tissues = TissueModel(gradientFactors: .conservative, water: water)
        self.lastGas = surfaceGas
    }

    /// Dalış bitti: mevcut doku/gaz durumunu yüzey takibine devret.
    public mutating func recordDiveEnd(at date: Date, tissues loaded: TissueModel, gas: GasMix) {
        self.tissues = loaded
        self.lastGas = gas
        self.lastDiveEnd = date
        self.elapsed = 0
        recomputeDeadlines(from: date)
    }

    /// `DiveSessionController.end()` sonucunu kaydet.
    public mutating func recordDiveEnd(at date: Date, log logEntry: LogEntry) {
        var restored = TissueModel(gradientFactors: logEntry.gradientFactors, water: logEntry.water)
        // Örnekleri sırayla oynatmak yüklemeyi doğru yeniden üretir.
        // (Tek adımda 30 dakikalık yükleme yapmak hızlı kompartmanlarda
        //  çok büyük gecikme hatası verir ve GF99 sıfır çıkar.)
        var previousElapsed: TimeInterval = 0
        for sample in logEntry.samples {
            let delta = sample.elapsed - previousElapsed
            guard delta > 0 else { continue }
            let gas = logEntry.gases.indices.contains(sample.gasIndex)
                ? logEntry.gases[sample.gasIndex] : logEntry.startGas
            restored.step(atDepth: sample.depth, duration: delta, gas: gas)
            previousElapsed = sample.elapsed
        }
        recordDiveEnd(at: date, tissues: restored, gas: logEntry.startGas)
    }

    /// Yeni yüzey aralığı başlat (kuru bekleme sona erdi gibi).
    public mutating func reset() {
        lastDiveEnd = nil
        tissues = TissueModel(gradientFactors: tissues.gradientFactors, water: tissues.water)
        elapsed = 0
        noFlyEnd = nil
        desaturationEnd = nil
    }

    // MARK: - Takip

    /// Belirli bir ana kadar ilerletir ve durumu döndürür.
    ///
    /// - Note: Kaba çözünürlükle (varsayılan 60 sn) çalışır; sık çağrılabilir,
    ///   çünkü yalnızca hedef ana kadar olan **farkı** işler.
    @discardableResult
    public mutating func update(to date: Date) -> SurfaceIntervalStatus {
        guard let end = lastDiveEnd else {
            return SurfaceIntervalStatus(elapsed: 0, gf99: 0, desaturationRemaining: 0,
                                        noFlyRemaining: 0, isNoFlyCleared: true,
                                        recommendation: "Dalış kaydı yok",
                                        statusDate: date)
        }

        let target = max(0, date.timeIntervalSince(end))
        while elapsed + resolution <= target {
            tissues.step(atDepth: 0, duration: resolution, gas: surfaceGas)
            elapsed += resolution
        }
        return status(at: date)
    }

    /// Durumu sorgular (takibi ilerletmeden).
    public func status(at date: Date = Date()) -> SurfaceIntervalStatus {
        let gf99 = tissues.gf99(atDepth: 0)
        let desatRemaining = max(0, (desaturationEnd ?? date).timeIntervalSince(date))
        let noFlyRemaining = max(0, (noFlyEnd ?? date).timeIntervalSince(date))
        return SurfaceIntervalStatus(
            elapsed: lastDiveEnd.map { max(0, date.timeIntervalSince($0)) } ?? 0,
            gf99: gf99,
            desaturationRemaining: desatRemaining,
            noFlyRemaining: noFlyRemaining,
            isNoFlyCleared: lastDiveEnd == nil || noFlyRemaining <= 0,
            recommendation: recommendation(gf99: gf99, noFlyRemaining: noFlyRemaining),
            statusDate: date)
    }

    // MARK: - Doku erişimi

    /// Dalış sonundan bu yana ilerletilmiş **artık doku durumu**.
    ///
    /// - Note: Tekrarlı dalış hesabı (`RepetitiveDiveCalculator`) bu durumu
    ///   kullanır; kopyalanır, motor değiştirilmez.
    public var residualTissues: TissueModel { tissues }

    /// Uçuş yasağı (kabin profiline göre).
    public func noFlyTime(cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel) -> TimeInterval {
        FlightAltitudeCalculator.noFlyTime(tissues: tissues, cabin: cabin)
    }

    /// Kabin profiline göre **tahmini** uçuş yasağı bitiş zamanı.
    ///
    /// - Note: `noFlyEnd` özelliği deniz seviyesi varsayımıyla, `update(to:)`
    ///   çağrıldığında güncellenir; bu metot kabin seçildiğinde kullanılır.
    public func predictedNoFlyEnd(cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel,
                                   at date: Date = Date()) -> Date? {
        guard let end = lastDiveEnd else { return nil }
        return end.addingTimeInterval(noFlyTime(cabin: cabin))
    }

    /// Arka planda bir sonraki kontrolün zamanı.
    public func nextBackgroundCheck(at date: Date = Date(),
                                    policy: BackgroundMonitoringPolicy = .standard,
                                    isDiving: Bool = false) -> Date? {
        let status = self.status(at: date)
        return policy.nextCheckDate(now: date,
                                     remainingNoFly: status.noFlyRemaining,
                                     remainingDesaturation: status.desaturationRemaining,
                                     isDiving: isDiving)
    }

    // MARK: - Dahili

    private mutating func recomputeDeadlines(from date: Date) {
        var scratch = tissues
        var waited: TimeInterval = 0
        var desaturation: TimeInterval?
        let maximum: TimeInterval = 24 * 3600

        while waited < maximum {
            scratch.step(atDepth: 0, duration: resolution, gas: surfaceGas)
            waited += resolution
            if desaturation == nil, scratch.gf99(atDepth: 0) <= noFlyGF99Limit {
                desaturation = waited
            }
            if waited >= noFlyBufferMinutes * 60, desaturation != nil { break }
        }
        // Uçuş yasağı: GF99 ≤ eşik + güvenlik payı, 15 dk'ya yuvarlanır
        let core = desaturation ?? maximum
        let buffered = core + noFlyBufferMinutes * 60
        let rounded = max(15 * 60, (buffered / 900).rounded(.up) * 900)

        desaturationEnd = date.addingTimeInterval(core)
        noFlyEnd = date.addingTimeInterval(rounded)
    }

    private func recommendation(gf99: Double, noFlyRemaining: TimeInterval) -> String {
        if lastDiveEnd == nil { return "Henüz dalış kaydı yok" }
        if noFlyRemaining > 0 {
            return "Uçuş yasağı \(DurationFormatter.clock(noFlyRemaining)) — yeni dalış için GF'ı düşür"
        }
        if gf99 <= 10 { return "Dokular temiz — serbest dalış GF'ı kullanabilirsin" }
        return "GF99 %\(Int(gf99.rounded())) — bir sonraki dalışta muhafazakâr GF seç"
    }
}

/// Yüzey aralığı durumu (ekran ve rapor için).
public struct SurfaceIntervalStatus: Equatable, Codable, Sendable {
    /// Son dalıştan bu yana geçen süre
    public let elapsed: TimeInterval
    /// Yüzeydeki GF99 (%)
    public let gf99: Double
    /// Desatürasyona kalan süre (GF99 ≤ %20)
    public let desaturationRemaining: TimeInterval
    /// Uçuş yasağına kalan süre
    public let noFlyRemaining: TimeInterval
    /// Uçuş yasağı bitti mi?
    public let isNoFlyCleared: Bool
    /// Kullanıcıya öneri metni
    public let recommendation: String

    /// Durumun ölçüldüğü zaman (doğrusal ilerletme için).
    public let statusDate: Date?

    public init(elapsed: TimeInterval, gf99: Double, desaturationRemaining: TimeInterval,
                noFlyRemaining: TimeInterval, isNoFlyCleared: Bool, recommendation: String,
                statusDate: Date? = nil) {
        self.elapsed = elapsed
        self.gf99 = gf99
        self.desaturationRemaining = desaturationRemaining
        self.noFlyRemaining = noFlyRemaining
        self.isNoFlyCleared = isNoFlyCleared
        self.recommendation = recommendation
        self.statusDate = statusDate
    }

    /// Yüzey aralığı metni ("2s 15dk").
    public var elapsedText: String { DurationFormatter.hoursMinutes(elapsed) }
    /// GF99 metni ("%23")
    public var gf99Text: String { "%\(Int(gf99.rounded()))" }

    /// Durumun alındığı zaman (yoksa `nil`).
    public var snapshotDate: Date? { statusDate }

    /// Durumu `date` anına **doğrusal olarak** ilerletir.
    ///
    /// - Note: Komplikasyon zaman çizelgesi gibi, gerçek doku
    ///   simülasyonu gerektirmeyen durumlar içindir. Doku bazlı doğru
    ///   hesap için `SurfaceIntervalManager.update(to:)` kullanılmalıdır.
    public func projected(to date: Date) -> SurfaceIntervalStatus {
        guard let origin = statusDate else { return self }
        let delta = date.timeIntervalSince(origin)
        guard delta > 0 else { return self }
        let total = max(0, noFlyRemaining - delta)

        // Kalan süre doğrusal azalır, yüzde de aynı oranda söner.
        let fraction = noFlyRemaining > 0
            ? min(1, max(0, noFlyRemaining - delta) / noFlyRemaining)
            : 0
        return SurfaceIntervalStatus(
            elapsed: elapsed + delta,
            gf99: gf99 * fraction,
            desaturationRemaining: max(0, desaturationRemaining - delta),
            noFlyRemaining: total,
            isNoFlyCleared: total <= 0,
            recommendation: recommendation)
    }
}