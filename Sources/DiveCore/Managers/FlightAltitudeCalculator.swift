import Foundation

/// Uçuş (kabin) yüksekliğine göre uçuş yasağı hesabı.
///
/// ## Neden gerekli?
/// Kabin 8000 ft'e (~2440 m) ayarlandığında bir uçak yolcusu deniz seviyesindeki
/// atmosfer basıncına yakın bir basınçta bulunur — ama **daha kuru** ve tam
/// olarak deniz seviyesi değildir. Bühlmann'ın uçuş yasağı ölçütü (GF99 ≤ %20)
/// kabin yüksekliğine göre farklılaşır:
///
/// - **Deniz seviyesi uçuşu:** mevcut GF99 ölçütü doğrudan geçerlidir.
/// - **Yüksek kabin (8000 ft):** dokuların çözülmesi *daha yavaştır* (düşük
///   atmosfer basıncı), bu yüzden güvenli bekleme süresi uzar.
///
/// Model: kabin basıncı deniz seviyesi basıncının `cabinFactor` katı olarak
/// alınır ve dokular bu basınçta bekletilir. `cabinFactor` = 1.0 deniz seviyesi,
/// ≈ 0.75 tipik 8000 ft kabin basıncı.
public enum FlightAltitudeCalculator {

    /// Deniz seviyesinde atmosfer basıncı (bar).
    public static let seaLevelPressure: Double = DivePhysics.surfacePressure

    /// Kabin yüksekliği için tipik ayarlar.
    public struct CabinProfile: Equatable, Codable, Sendable, Identifiable {
        public let id: String
        /// Kabin içi basınç etkeni (1.0 = deniz seviyesi)
        public let cabinFactor: Double
        /// Etiket ("Deniz seviyesi uçuşu")
        public let title: String

        public init(id: String, cabinFactor: Double, title: String) {
            self.id = id
            self.cabinFactor = cabinFactor
            self.title = title
        }

        /// Deniz seviyesi (kabin ayarı yok).
        public static let seaLevel = CabinProfile(id: "sea", cabinFactor: 1.0,
                                                  title: "Deniz seviyesi")
        /// Standart ticari uçuş (8000 ft kabin basıncı).
        public static let standardFlight = CabinProfile(id: "flight8000", cabinFactor: 0.75,
                                                        title: "Standart uçuş (8000 ft)")
        /// Yüksek irtifa uçuşu (9000+ ft kabin).
        public static let highAltitudeFlight = CabinProfile(id: "flight9000", cabinFactor: 0.70,
                                                            title: "Yüksek irtifa (9000 ft)")

        public static let all: [CabinProfile] = [.seaLevel, .standardFlight, .highAltitudeFlight]
    }

    /// Kabin basıncı (bar).
    public static func cabinPressure(for profile: CabinProfile) -> Double {
        seaLevelPressure * profile.cabinFactor
    }

    /// Bir doku durumunun GF99 ölçütüne inmesi için gereken süre, **kabin
    /// basıncında** bekletilerek hesaplanır (saniye).
    ///
    /// - Note: `tissues` değiştirilmez (saf hesap).
    public static func timeToSafeGF99(tissues: TissueModel,
                                       cabin: CabinProfile,
                                       targetGF99: Double = 20,
                                       gas: GasMix = .air,
                                       resolution: TimeInterval = 60,
                                       maximumWait: TimeInterval = 24 * 3600) -> TimeInterval {
        guard targetGF99 > 0 else { return 0 }
        var scratch = tissues
        // Kabin basıncı doğrudan basınç olarak kullanılır (derinlikle
        // ifade edilemez: 0.74 bar deniz seviyesinin *altındadır*).
        let pressure = cabinPressure(for: cabin)

        var waited: TimeInterval = 0
        while waited < maximumWait {
            scratch.step(atAmbientPressure: pressure, duration: resolution, gas: gas)
            waited += resolution
            if scratch.gf99(atAmbientPressure: pressure) <= targetGF99 { return waited }
        }
        return maximumWait
    }

    /// Uçuş yasağı (kabin profiline göre, güvenlik payı dahil).
    public static func noFlyTime(tissues: TissueModel,
                                  cabin: CabinProfile = .seaLevel,
                                  bufferMinutes: Double = 60,
                                  gas: GasMix = .air,
                                  resolution: TimeInterval = 60) -> TimeInterval {
        let core = timeToSafeGF99(tissues: tissues, cabin: cabin, gas: gas, resolution: resolution)
        let buffered = core + bufferMinutes * 60
        return max(15 * 60, (buffered / 900).rounded(.up) * 900)
    }

    /// Uçuş yasağının biteceği zaman (kabin profili ile).
    public static func noFlyEnd(tissues: TissueModel,
                                diveEnd: Date,
                                cabin: CabinProfile = .seaLevel,
                                bufferMinutes: Double = 60,
                                gas: GasMix = .air) -> Date {
        diveEnd.addingTimeInterval(noFlyTime(tissues: tissues, cabin: cabin,
                                             bufferMinutes: bufferMinutes, gas: gas))
    }

    /// `to` profili seçildiğinde beklenen **ek bekleme** yüzdesi.
    ///
    /// - Note: Negatif değer `to` profilinin daha kısa (daha az temkinli)
    ///   süre verdiğini gösterir; pratikte bu durum oluşmaz.
    public static func additionalWaitPercent(from: CabinProfile, to: CabinProfile,
                                             tissues: TissueModel, gas: GasMix = .air) -> Double {
        let baseline = noFlyTime(tissues: tissues, cabin: from, gas: gas)
        let alternative = noFlyTime(tissues: tissues, cabin: to, gas: gas)
        guard baseline > 0 else { return 0 }
        return (alternative - baseline) / baseline * 100
    }
}

/// Arka planda çalışma zamanlaması — dalış bittikten sonra dokuların çözülmesini
/// izlemek için yapılacak kontrollerin zaman planı.
///
/// ## Neden zamanlama gerekiyor?
/// watchOS'ta uygulama arka planda sürekli çalışamaz; `WKExtendedRuntimeSession`
/// kısa pencerelerde, `HKWorkout` ise tek bir oturum boyunca aktiftir. Bu yüzden
/// geri sayım için **bir sonraki kontrolün ne zaman** yapılması gerektiği
/// önceden hesaplanır ve `BGTaskScheduler`/`Timer` ile planlanır.
///
/// Uygulama yeniden açıldığında da (`update(to:)`) durum doğrudan hesaplanır;
/// zamanlama yalnızca "kullanıcı ekrana bakmıyorken" tazelik sağlar.
public struct BackgroundMonitoringPolicy: Equatable, Codable, Sendable {

    /// Kontroller arası en uzun aralık (saniye) — pil dostu
    public var maximumInterval: TimeInterval
    /// Kontroller arası en kısa aralık (saniye) — geri sayım çözünürlüğü
    public var minimumInterval: TimeInterval
    /// Toplam kontrol bütçesi — uygulamayı uyandıran sayı sınırlıdır
    public var maximumChecks: Int
    /// Uçuş yasası bitince izlemeyi durdur
    public var stopWhenNoFlyCleared: Bool

    public init(maximumInterval: TimeInterval = 900,   // 15 dk
                minimumInterval: TimeInterval = 60,
                maximumChecks: Int = 60,
                stopWhenNoFlyCleared: Bool = true) {
        self.maximumInterval = max(minimumInterval, maximumInterval)
        self.minimumInterval = minimumInterval
        self.maximumChecks = max(1, maximumChecks)
        self.stopWhenNoFlyCleared = stopWhenNoFlyCleared
    }

    /// Pil dostu varsayılan (en fazla 60 kontrol).
    public static let standard = BackgroundMonitoringPolicy()

    /// Sık kontrol (önceki gün uçuşu planlanıyorsa).
    public static let frequent = BackgroundMonitoringPolicy(maximumInterval: 300,
                                                            minimumInterval: 60,
                                                            maximumChecks: 120)

    /// Bir sonraki kontrolün zamanı.
    ///
    /// - Parameters:
    ///   - now: Şu an
    ///   - remainingNoFly: Kalan uçuş yasağı (saniye)
    ///   - remainingDesaturation: Kalan desatürasyon (saniye)
    ///   - isDiving: Dalış sürüyor mu (1 Hz örnekleme gerekir)
    ///   - usedChecks: Şimdiye kadar yapılan kontrol sayısı (bütçe için)
    public func nextCheckDate(now: Date,
                              remainingNoFly: TimeInterval,
                              remainingDesaturation: TimeInterval,
                              isDiving: Bool = false,
                              usedChecks: Int = 0) -> Date? {
        if isDiving { return now.addingTimeInterval(minimumInterval) }

        let remaining = min(remainingNoFly, remainingDesaturation)
        if stopWhenNoFlyCleared, remaining <= 0 { return nil }

        // Bütçe tükendiyse tek bir kapanış kontrolü yapılır.
        if usedChecks >= maximumChecks {
            return now.addingTimeInterval(max(minimumInterval, remaining))
        }

        let interval = checkInterval(remaining: remaining, usedChecks: usedChecks)
        return now.addingTimeInterval(min(interval, max(minimumInterval, remaining)))
    }

    /// Verilen kalan süre ve harcanmış kontrol sayısı için kontrol aralığı.
    ///
    /// İki kısıt birlikte uygulanır:
    ///
    /// 1. **Faz kuralı** — geri sayım sonuna yaklaştıkça sıklaşır
    ///    (>1 saat: 15 dk, 15-60 dk: 5 dk, <15 dk: 1 dk).
    /// 2. **Bütçe kuralı** — kalan süre, kalan kontrol sayısına eşit
    ///    dağıtılacak şekilde aralık uzatılır (pil dostu).
    public func checkInterval(remaining: TimeInterval, usedChecks: Int = 0) -> TimeInterval {
        let phase: TimeInterval
        if remaining <= 15 * 60 {
            phase = minimumInterval
        } else if remaining <= 60 * 60 {
            phase = max(minimumInterval, maximumInterval / 3)
        } else {
            phase = maximumInterval
        }

        let remainingBudget = max(1, maximumChecks - usedChecks)
        let budget = remaining / Double(remainingBudget)
        return max(minimumInterval, min(maximumInterval, max(phase, budget)))
    }

    /// Toplam izleme penceresi sayısı (tahmini enerji bütçesi).
    public func expectedCheckCount(remainingNoFly: TimeInterval) -> Int {
        guard remainingNoFly > 0 else { return 0 }
        var remaining = remainingNoFly
        var used = 0
        while remaining > 0 && used < maximumChecks {
            remaining -= checkInterval(remaining: remaining, usedChecks: used)
            used += 1
        }
        return min(used, maximumChecks)
    }
}