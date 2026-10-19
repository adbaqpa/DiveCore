import Foundation

/// Derin durak (deep stop) hesabı — GUE/Subsurface tarzı "rounded-off" yaklaşımı.
///
/// ## Neden derin durak?
/// Klasik Bühlmann dekompresyonunda tavan yalnızca **3 m ızgarasındaki**
/// durakları gösterir. Hızlı kompartmanlar (5–20 dk yarı ömür) dipte bu kadar
/// beklenmeden çözülür; bu da "no-stop time"ın hesaplanmasına yol açar.
/// Derin duraklar bu kompartmanların dipte **kontrollü** çözülmesini sağlar ve
/// derin dalışlarda (N₂ kaybı) yüzey çıkış süresini kısaltır.
///
/// ## Algoritma (basitleştirilmiş GUE)
/// 1. Dalış sonundaki doku durumu alınır ve ilk deko durağına (tavan) çıkılır.
/// 2. İlk durağın **derinindeki** her aralık (varsayılan 3 m, GUE'da 1 ft) için:
///    dokuların N₂ basıncı **yuvarlanır** (`roundOff`, artan değere yukarıdan),
///    tavan yeniden hesaplanır; tavan bu derinliğin **üstüne** çıkıyorsa
///    durak "canlı" (live) demektir ve yapılmalıdır.
/// 3. Canlı duraklar derinlik artan sırayla listelenir.
///
/// - Note: Bu, GUE'nin tam Pyle-dalgası benzetiminin sadeleştirilmiş hâlidir:
///   doğrudan Bühlmann doku simülasyonu kullanılır, Pyle dalgalanması
///   modellenmez. Üretim öncesi Shearwater/Subsurface ile çapraz doğrulama
///   gerekir.
public enum DeepStopCalculator {

    /// Derin durak aralığı (m). GUE 1 ft (0.3 m) kullanır; 3 m pratik bir
    /// yaklaşımdır ve hesaplama maliyetini düşürür.
    public static let standardInterval: Double = 3.0

    /// Bir derin durak.
    public struct DeepStop: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        /// Durak derinliği (m)
        public let depth: Double
        /// Durak "canlı" mı (yuvarlama sonrası tavan bu derinliğe ulaşıyor mu)
        public let isLive: Bool
        /// Yuvarlanmış N₂ basıncı (bar) — açıklama/izleme amaçlı
        public let roundedPressure: Double
        /// Bu durakta geçirilmesi gereken süre (saniye)
        public let holdTime: TimeInterval

        public init(id: UUID = UUID(), depth: Double, isLive: Bool,
                    roundedPressure: Double, holdTime: TimeInterval = 0) {
            self.id = id
            self.depth = depth
            self.isLive = isLive
            self.roundedPressure = roundedPressure
            self.holdTime = holdTime
        }

        public var label: String { "\(Int(depth)) m" }
    }

    /// Derin durak hesaplama ayarları.
    public struct Settings: Equatable, Codable, Sendable {
        /// Derin duraklar açık mı
        public var isEnabled: Bool
        /// Aralık (m)
        public var interval: Double
        /// En sığ derin durak (m) — bunun altında durak gösterilmez
        public var firstStopDepth: Double
        /// En derin durak (m) — bunun altında hesaplanmaz
        public var lastStopDepth: Double

        public init(isEnabled: Bool = false,
                    interval: Double = DeepStopCalculator.standardInterval,
                    firstStopDepth: Double = 6,
                    lastStopDepth: Double = 45) {
            self.isEnabled = isEnabled
            self.interval = max(0.5, interval)
            self.firstStopDepth = firstStopDepth
            self.lastStopDepth = lastStopDepth
        }

        public static let disabled = Settings(isEnabled: false)
        public static let standard = Settings(isEnabled: true)

        /// Geçerli aralıkta bir derinlik var mı?
        public var hasRoom: Bool { lastStopDepth > firstStopDepth + interval }
    }

    // MARK: - Hesaplama

    /// Derin durakları hesaplar.
    ///
    /// - Parameters:
    ///   - tissues: Dalış sonundaki doku durumu (`DecoEngine.tissues`)
    ///   - maxDepth: Dalışın azami derinliği (m)
    ///   - firstDecoStopDepth: İlk zorunlu deko durağı (tavan) (m)
    ///   - gradientFactors: GF ayarı (tavan hesabı için)
    ///   - settings: Ayarlar
    ///   - resolution: Çıkış simülasyonu çözünürlüğü (saniye)
    /// - Returns: Derinlemeden yüzeye doğru sıralı derin duraklar
    public static func deepStops(tissues: TissueModel,
                                 maxDepth: Double,
                                 firstDecoStopDepth: Double,
                                 gradientFactors: GradientFactors? = nil,
                                 settings: Settings = .standard,
                                 resolution: TimeInterval = 10) -> [DeepStop] {
        guard settings.isEnabled, settings.hasRoom else { return [] }
        // Deko yükümlülüğü yoksa derin durak için bir "ilk deko durağı"
        // referansı da yoktur → hesap yapılmaz.
        guard firstDecoStopDepth > 0 else { return [] }

        var scratch = tissues
        if let gradientFactors {
            scratch = TissueModel(nitrogenPressures: scratch.nitrogenPressures,
                                  gradientFactors: gradientFactors,
                                  water: scratch.water)
        }

        // 1) En sığ derin duraktan başlayarak ilk deko durağına yüksel
        let shallowest = min(settings.lastStopDepth, maxDepth)
        guard shallowest > firstDecoStopDepth + settings.interval else { return [] }
        let ascentDuration = (shallowest - firstDecoStopDepth) / DiveSafetyLimits.recommendedAscentRate * 60
        scratch.step(fromDepth: maxDepth, toDepth: shallowest,
                     duration: ascentDuration, gas: .air)

        // 2) Sığdan derine doğru her adımda: dokular yuvarlanır, tavan yeniden
        //    hesaplanır. Tavan bu derinliğe ulaşıyorsa durak **canlıdır** ve
        //    tavan derinliğin üstüne çıkana kadar burada beklenir.
        var stops: [DeepStop] = []
        // İlk aday: ilk deko durağının bir aralık **altı** (yani daha derin),
        // ızgaraya yukarı yuvarlanmış.
        var depth = ((firstDecoStopDepth + settings.interval) / settings.interval)
            .rounded(.up) * settings.interval

        // Not: Alt sınır `firstDecoStopDepth`'dir — bu değerin altına inilmez
        // (aksi halde döngü sonlanmazdı: eksi derinliklerde koşul hep doğru kalır).
        while depth > firstDecoStopDepth + 0.001, depth <= shallowest + 0.001 {
            var rounded = scratch.roundedOff(incrementPressure: settings.incrementPressure(atDepth: depth))
            let ceiling = rounded.ceiling(atDepth: depth).depthMeters
            // Durak "canlıdır" eğer tavan bu kademeye (bir aralık toleransla)
            // ulaşıyorsa: yani o derinlikte beklenmeden tavan bir üst kademeye
            // çıkıyor demektir. `ceiling > 0` şartı, deko yükümlülüğü olmayan
            // dalışlarda sahte durak üretilmesini engeller.
            let isLive = ceiling > 0.5 && ceiling >= depth - settings.interval

            var held: TimeInterval = 0
            if isLive {
                // Üst sınır: 10 dk. Bekleme normalde 1-10 dk sürer; uzun beklemeler
                // tavan hesabında bir hata işaretidir ve dalışı gerekçesiz uzatır.
                let maximumHold: TimeInterval = 10 * 60
                while held < maximumHold {
                    rounded.step(atDepth: depth, duration: resolution, gas: .air)
                    held += resolution
                    if rounded.ceiling(atDepth: depth).depthMeters < depth - settings.interval { break }
                }
                stops.append(DeepStop(depth: depth, isLive: true,
                                      roundedPressure: rounded.leadingNitrogenPressure,
                                      holdTime: held))
                // Durak yapıldı kabul edilir: sonraki hesaplar bu durumdan yürür
                scratch = rounded
            }
            depth -= settings.interval
        }

        // Tabloda derinlemeden yüzeye sırala (okuma kolaylığı)
        return stops.reversed()
    }

    /// Derin duraklarda geçirilecek toplam süre (saniye).
    public static func totalHoldTime(_ stops: [DeepStop]) -> TimeInterval {
        stops.filter(\.isLive).reduce(0) { $0 + $1.holdTime }
    }

    /// Canlı durak sayısı.
    public static func liveStopCount(_ stops: [DeepStop]) -> Int {
        stops.filter(\.isLive).count
    }
}

extension DeepStopCalculator.Settings {
    /// Derinlik kademesine karşılık gelen basınç artanı (bar).
    ///
    /// GUE yaklaşımında artan sabittir (≈ 0.3 bar); burada derinlikle orantılı
    /// ölçeklenir ki derin duraklar sığ ve derin dalışlarda aynı "basınç
    /// adımına" denk gelsin.
    public func incrementPressure(atDepth depth: Double) -> Double {
        // Denizde ≈ 0.1 bar/m; 3 m'lik aralık ≈ 0.3 bar → 3'e bölerek 0.1 bar
        let barPerMeter = DivePhysics.WaterType.salt.barPerMeter
        return max(0.15, interval * barPerMeter / 3.0)
    }
}