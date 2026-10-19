import Foundation

/// Çıkış/iniş hızı takipçisi.
///
/// Ham derinlik farkından hesaplanan hız gürültülüdür (nefes, akıntı, sensör
/// hatası); bu sınıf üstel yumuşatma (EMA) uygular ve ihlali **süreklilik**
/// koşuluyla doğrular — böylece tek bir spike alarm üretmez.
public struct AscentRateMonitor: Sendable {

    // MARK: - Ayarlar

    /// Yumuşatma katsayısı (0...1). Küçük değer = daha duyarlı, daha gürültülü.
    public var smoothingFactor: Double
    /// Hız sınırı (m/dk)
    public var limit: Double
    /// Dikkat seviyesi eşiği (m/dk)
    public var cautionThreshold: Double
    /// Alarm üretilmesi için hızın bu süre boyunca (saniye) sınırın üstünde
    /// kalması gerekir.
    public var violationHoldTime: TimeInterval
    /// Gerilim/titreşim tekrarı için bekleme (saniye)
    public var alarmCooldown: TimeInterval

    // MARK: - Durum

    /// Yumuşatılmış hız (m/dk, pozitif = yukarı)
    public private(set) var smoothedRate: Double = 0
    /// Ham (anlık) hız (m/dk)
    public private(set) var instantaneousRate: Double = 0
    /// Hızın sınırın üzerinde geçirdiği kesintisiz süre (saniye)
    public private(set) var violationDuration: TimeInterval = 0
    /// Son alarmın verildiği zaman (saniye)
    public private(set) var lastAlarmAt: TimeInterval?
    /// Toplam yükselen mesafe (m) — istatistik için
    public private(set) var totalAscent: Double = 0
    /// Toplam inilen mesafe (m)
    public private(set) var totalDescent: Double = 0

    private var previousReading: DepthReading?

    // MARK: - Oluşturucu

    public init(smoothingFactor: Double = 0.25,
                limit: Double = DiveSafetyLimits.maximumAscentRate,
                cautionThreshold: Double = DiveSafetyLimits.cautionAscentRate,
                violationHoldTime: TimeInterval = 4,
                alarmCooldown: TimeInterval = 8) {
        self.smoothingFactor = smoothingFactor.clamped(to: 0.05...1.0)
        self.limit = limit
        self.cautionThreshold = cautionThreshold
        self.violationHoldTime = violationHoldTime
        self.alarmCooldown = alarmCooldown
    }

    // MARK: - Güncelleme

    /// Yeni okumayı işler ve anlık durumu döndürür.
    @discardableResult
    public mutating func update(with reading: DepthReading) -> AscentRateUpdate {
        defer { previousReading = reading }

        guard let previous = previousReading else {
            // İlk okuma: hız 0 kabul edilir
            instantaneousRate = 0
            smoothedRate = 0
            violationDuration = 0
            return currentUpdate(reading: reading, exceeded: false, alarmDue: false)
        }

        let dt = reading.elapsed - previous.elapsed
        guard dt > 0 else {
            // Saat sıfırlanması (yüzey aralığı / yeniden başlatma)
            if dt < 0 {
                smoothedRate = 0
                instantaneousRate = 0
                violationDuration = 0
            }
            return currentUpdate(reading: reading, exceeded: false, alarmDue: false)
        }

        let delta = reading.depth - previous.depth
        // **İşaret kuralı:** pozitif = yukarı (çıkış). Dalış bilgisayarı
        // geleneğinde `ascentRate` pozitif değer yukarı çıkışı gösterir.
        let raw = -delta / dt * 60.0        // m/dk
        instantaneousRate = raw
        smoothedRate = smoothingFactor * raw + (1 - smoothingFactor) * smoothedRate

        // Toplam mesafe: derinlik artışı = iniş
        if delta > 0 { totalDescent += delta } else { totalAscent += -delta }

        // Yüzeydeyken hız hesabı anlamlı değil
        let isValid = !reading.isAtSurface && !previous.isAtSurface && abs(smoothedRate) < 60

        if isValid && smoothedRate > limit {
            violationDuration += dt
        } else {
            violationDuration = 0
        }

        let exceeded = violationDuration >= violationHoldTime
        let sinceAlarm = lastAlarmAt.map { reading.elapsed - $0 } ?? .infinity
        let alarmDue = exceeded && sinceAlarm >= alarmCooldown
        if alarmDue { lastAlarmAt = reading.elapsed }

        return currentUpdate(reading: reading, exceeded: exceeded, alarmDue: alarmDue)
    }

    private func currentUpdate(reading: DepthReading,
                               exceeded: Bool,
                               alarmDue: Bool) -> AscentRateUpdate {
        AscentRateUpdate(
            reading: reading,
            instantaneousRate: instantaneousRate,
            smoothedRate: smoothedRate,
            status: AscentRateStatus.evaluate(rate: smoothedRate, depth: reading.depth),
            exceededLimit: exceeded,
            alarmDue: alarmDue,
            violationDuration: violationDuration,
            totalAscent: totalAscent,
            totalDescent: totalDescent)
    }

    /// Takipçiyi sıfırlar (yeni dalış veya uzun yüzey arası).
    public mutating func reset() {
        smoothedRate = 0
        instantaneousRate = 0
        violationDuration = 0
        lastAlarmAt = nil
        totalAscent = 0
        totalDescent = 0
        previousReading = nil
    }

    /// Yüzeyde geçirilen uzun bir süreden sonra (ör. 60 sn) sıfırlama yapar.
    public mutating func resetIfSurface(duration: TimeInterval = 60) {
        guard let previous = previousReading else { return }
        if previous.depth <= 0.3 { reset() }
    }
}

/// Tek bir güncellemeden çıkan hız durumu.
public struct AscentRateUpdate: Equatable, Sendable {
    public let reading: DepthReading
    /// Anlık (gürültülü) hız (m/dk)
    public let instantaneousRate: Double
    /// Yumuşatılmış hız (m/dk)
    public let smoothedRate: Double
    /// Renk/gösterge durumu
    public let status: AscentRateStatus
    /// Sınır süresince aşıldı mı?
    public let exceededLimit: Bool
    /// Bu anda alarm tetiklenmeli mi? (cooldown dahil)
    public let alarmDue: Bool
    /// İhlalin süreklilik süresi (saniye)
    public let violationDuration: TimeInterval
    public let totalAscent: Double
    public let totalDescent: Double

    /// Yumuşatılmış hızın m/dk olarak yuvarlanmış gösterimi.
    public var displayRate: String { String(format: "%.1f", smoothedRate) }
}