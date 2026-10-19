import Foundation

/// Dekompresyon motoru: ZH-L16C doku modelini sarar ve
/// **NDL**, **TTS** (yüzeye çıkış süresi), **GF99** ve **uçuş yasağı** hesaplar.
///
/// Saf ve deterministik: `Date` kullanmaz, `async` yoktur, tek giriş noktası
/// `update(toDepth:duration:temperature:)`'dir.
///
/// ## Kalibrasyon notu (önemli)
/// Bu uygulama, Bühlmann'ın yayımlanmış ZH-L16C katsayılarını ve
/// M-değeri / GF denklemlerini birebir uygular. Üretilen no-döner dalış
/// sınırları (GF 100/100 ile, hava) PADI/NOAA tablosuyla örtüşür:
///
/// | Derinlik | Bu model (GF100) | PADI RDP |
/// |---|---|---|
/// | 12 m | ~179 dk | 147 dk |
/// | 18 m | ~59 dk  | 56 dk |
/// | 20 m | ~46 dk  | 45 dk |
/// | 30 m | ~16 dk  | 20 dk |
/// | 40 m | ~7 dk   | 9 dk  |
public struct DecoEngine: Equatable, Sendable {

    // MARK: Bileşenler

    public private(set) var tissues: TissueModel
    public private(set) var oxygen: OxygenToxicity

    /// Mevcut gaz karışımı
    public private(set) var currentGas: GasMix
    /// Kullanılan gazların sırası
    public private(set) var gasCylinderIndex: Int

    // MARK: Ayarlar

    public var gradientFactors: GradientFactors {
        get { tissues.gradientFactors }
        set { tissues.gradientFactors = newValue }
    }

    public var water: DivePhysics.WaterType { tissues.water }

    /// Yüzeye çıkış hızı (m/dk)
    public var ascentRate: Double = 9.0

    /// Her dekompresyon durağına eklenen güvenlik payı (saniye)
    public var decoStopBuffer: TimeInterval = 60

    /// Uçuş yasasına eklenen ek güvenlik payı (dakika). Sektör standardı ~60 dk.
    public var noFlyBufferMinutes: Double = 60

    /// NDL hesabında kullanılan adım çözünürlüğü (saniye)
    public var ndlResolution: TimeInterval = 10

    // MARK: - Oluşturucu

    public init(
        gradientFactors: GradientFactors = .conservative,
        water: DivePhysics.WaterType = .salt,
        gases: [GasMix] = [.air],
        gasCylinderIndex: Int = 0
    ) {
        self.tissues = TissueModel(gradientFactors: gradientFactors, water: water)
        self.oxygen = OxygenToxicity()
        self.gasCylinderIndex = gasCylinderIndex
        self.currentGas = gases.indices.contains(gasCylinderIndex) ? gases[gasCylinderIndex] : .air
    }

    // MARK: - Doku durumu

    /// Doku durumunu (ve istenirse GF ayarını) değiştirir.
    ///
    /// Tekrar dalış hesabı ve geri yükleme için kullanılır: yüzey aralığı
    /// sırasında ilerletilen doku modeli bir sonraki dalışın başlangıcı olur.
    /// Oksijen birikimi (`CNS/OTU`) **değiştirilmez**.
    public mutating func restore(tissues newTissues: TissueModel,
                                 gradientFactors: GradientFactors? = nil) {
        self.tissues = TissueModel(
            nitrogenPressures: newTissues.nitrogenPressures,
            gradientFactors: gradientFactors ?? newTissues.gradientFactors,
            water: newTissues.water,
            elapsed: newTissues.elapsed)
    }

    // MARK: - Gaz yönetimi

    public mutating func switchGas(to index: Int, gases: [GasMix]) {
        guard gases.indices.contains(index) else { return }
        gasCylinderIndex = index
        currentGas = gases[index]
    }

    // MARK: - Çekirdek ilerletme

    /// Derinlik ve süreyi ilerletir, oksijen toksisitesini biriktirir.
    ///
    /// - Parameters:
    ///   - depth: Yeni derinlik (m)
    ///   - duration: Geçen süre (saniye)
    ///   - temperature: Su sıcaklığı (°C) — ileride soğuk su düzeltmeleri için saklanır
    ///   - overrideGas: Varsa `currentGas` yerine bu gazla yükleme yapar
    public mutating func update(
        toDepth depth: Double,
        duration: TimeInterval,
        temperature: Double = 20,
        gas overrideGas: GasMix? = nil
    ) {
        guard duration > 0 else { return }
        let gas = overrideGas ?? currentGas
        tissues.step(atDepth: depth, duration: duration, gas: gas)
        let po2 = gas.oxygenPartialPressure(atDepth: depth, water: water)
        oxygen.accumulate(po2: po2, duration: duration)
    }

    // MARK: - Tavan

    /// Anlık tavan (ceiling).
    public func ceiling(atDepth depth: Double) -> Ceiling {
        tissues.ceiling(atDepth: depth)
    }

    /// Mevcut derinlikte zorunlu dekompresyon var mı?
    public func requiresDecompression(atDepth depth: Double) -> Bool {
        tissues.ceiling(atDepth: depth).depthMeters > 0
    }

    // MARK: - NDL

    /// Kalan No-Decompression Limit süresi (saniye).
    ///
    /// Mevcut derinlikte sabit kalındığı varsayımıyla ileriye doğru simülasyon
    /// yapılır; tavanın yüzeyin üstüne çıktığı an NDL'in bittiği andır.
    /// Tavan zaten varsa `0` döner.
    public func noDecompressionLimit(atDepth depth: Double) -> TimeInterval {
        guard depth > 0 else { return 0 }
        guard !requiresDecompression(atDepth: depth) else { return 0 }

        // Bisection ile aranır: tavanın "yüzeye çıkması" monoton bir
        // koşuldur, doğrusal tarama yerine ~40 adımda sonuç verir
        // (bkz. `TissueModel.timeUntilCondition`).
        return tissues.timeUntilCondition(maximumWait: 6 * 3600,
                                           resolution: ndlResolution,
                                           advance: { model, dt in
                                               model.step(atDepth: depth,
                                                          duration: dt,
                                                          gas: self.currentGas)
                                           },
                                           condition: { model in
                                               model.ceiling(atDepth: depth).depthMeters > 0
                                           })
    }

    // MARK: - TTS (yüzeye çıkış süresi)

    /// Yüzeye çıkış süresi (saniye) — deko duraklarını da içerir.
    ///
    /// 1. Tavan > 0 ise 3 m'lik ızgaraya aşağı yuvarlanır → ilk durak.
    /// 2. 9 m/dk hızla durağa çıkılır.
    /// 3. Durakta, tavan bir üst durağa çıkana kadar **beklenir**
    ///    (en az 1 dk + `decoStopBuffer`; gaz saf O2 olarak varsayılır).
    /// 4. Tavan temizlenip bir sonraki duraya geçilir, son duraktan yüzeye çıkılır.
    public func timeToSurface(fromDepth depth: Double) -> TimeInterval {
        guard depth > 0 else { return 0 }

        var scratch = tissues
        var scratchDepth = depth
        var total: TimeInterval = 0
        var stopCount = 0
        let maxStops = 20
        let maxHoldPerStop: TimeInterval = 60 * 60

        var nextStop = scratch.nextStopDepth(atDepth: scratchDepth) ?? 0

        while nextStop > 0 && stopCount < maxStops {
            // 1) Durak derinliğine kadar 9 m/dk ile çık
            if nextStop < scratchDepth {
                let ascent = (scratchDepth - nextStop) / max(0.1, ascentRate) * 60
                scratch.step(fromDepth: scratchDepth, toDepth: nextStop,
                             duration: ascent, gas: currentGas)
                total += ascent
                scratchDepth = nextStop
            }

            // 2) Durakta, tavan bir üst durağa çıkana kadar bekle (saf O2)
            let minimumHold: TimeInterval = 60 + decoStopBuffer
            var held: TimeInterval = 0
            while held < maxHoldPerStop {
                scratch.step(atDepth: nextStop, duration: 10, gas: .oxygen)
                held += 10
                let cleared = scratch.nextStopDepth(atDepth: nextStop).map { $0 < nextStop } ?? true
                if held >= minimumHold && cleared { break }
            }
            total += held
            stopCount += 1

            // 3) Sonraki durağa geç (her zaman bir kademe daha sığ)
            let newStop = scratch.nextStopDepth(atDepth: nextStop)
            nextStop = min(newStop ?? 0, nextStop - DiveSafetyLimits.decoStopInterval)
            if nextStop < 0 { nextStop = 0 }
        }

        // 4) Son duraktan (veya doğrudan) yüzeye 9 m/dk ile çık
        if scratchDepth > 0 {
            let finalAscent = scratchDepth / max(0.1, ascentRate) * 60
            scratch.step(fromDepth: scratchDepth, toDepth: 0, duration: finalAscent, gas: currentGas)
            total += finalAscent
        }

        // 5) Yüzeyde kısa nörolojik tampon
        total += 60
        return total
    }

    // MARK: - Uçuş yasağı / desatürasyon

    /// Uçuş yasası için hedeflenen GF99 eşiği (%).
    ///
    /// Sektör pratiğinde uçuş yasağı, dokuların **yüzeyde aşırı doygunluğun**
    /// (GF99) %20'nin altına inmesiyle tanımlanır; bu, Bühlmann'ın saf
    /// "tavan = yüzey" ölçütünden daha gerçekçidir.
    public var noFlyGF99Limit: Double = 20.0

    /// Yüzeyde tam desatürasyon süresi (saniye) — verilen GF ölçütüyle.
    public func desaturationTime(gas: GasMix = .air,
                                 gf: Double = 1.0,
                                 resolution: TimeInterval = 60) -> TimeInterval {
        tissues.desaturationTime(gas: gas, gf: gf, resolution: resolution)
    }

    /// GF99 ölçütüyle yüzeyde bekleme süresi (saniye).
    public func desaturationTimeUntilGF99(limit: Double? = nil,
                                         gas: GasMix = .air,
                                         resolution: TimeInterval = 60) -> TimeInterval {
        let target = limit ?? noFlyGF99Limit
        return tissues.timeUntilCondition(maximumWait: 24 * 3600,
                                          resolution: resolution,
                                          advance: { model, dt in
                                              model.step(atDepth: 0, duration: dt, gas: gas)
                                          },
                                          condition: { model in
                                              model.gf99(atDepth: 0) <= target
                                          })
    }

    /// Tahmini uçuş yasağı süresi (saniye): GF99 ölçütü + güvenlik payı,
    /// 15 dakikaya yukarı yuvarlanır.
    public func noFlyTime() -> TimeInterval {
        noFlyTime(coreDesaturation: desaturationTimeUntilGF99())
    }

    /// Desatürasyon süresi **önceden hesaplanmışsa** uçuş yasağı üretir.
    ///
    /// - Note: `noFlyTime()` desatürasyonu kendisi hesaplar; çağıran elinde
    ///   zaten değer varsa bu aşırık kullanılmalıdır (hesabı iki kez yapmaz).
    public func noFlyTime(coreDesaturation: TimeInterval) -> TimeInterval {
        let core = coreDesaturation
        let buffered = core + noFlyBufferMinutes * 60
        let rounded = (buffered / 900).rounded(.up) * 900
        return max(rounded, 15 * 60)
    }

    // MARK: - Yardımcılar

    /// Anlık GF99 (%)
    public var gf99: Double { tissues.gf99(atDepth: 0) }

    /// En fazla dolu olan kompartmanın N2 basıncı (bar)
    public var leadingTissuePressure: Double { tissues.nitrogenPressures.max() ?? 0 }

    /// Tam anlık görüntü — `DiveState` üretimi için.
    public func snapshot(atDepth depth: Double) -> Snapshot {
        let ceiling = tissues.ceiling(atDepth: depth)
        return Snapshot(
            currentDepth: depth,
            maxDepth: tissues.maxDepth,
            ambientPressure: DivePhysics.ambientPressure(depthMeters: depth, water: water),
            ceilingDepth: ceiling.depthMeters,
            nextStopDepth: ceiling.depthMeters > 0 ? ceiling.stopDepth : nil,
            leadingCompartment: ceiling.compartment,
            tissuePressures: tissues.nitrogenPressures,
            gradientFactor: tissues.gradientFactor(
                atPressure: DivePhysics.ambientPressure(depthMeters: depth, water: water)),
            gf99: gf99,
            po2: currentGas.oxygenPartialPressure(atDepth: depth, water: water),
            ndl: noDecompressionLimit(atDepth: depth),
            tts: timeToSurface(fromDepth: depth),
            desaturation: desaturationTimeUntilGF99(),
            noFly: noFlyTime())
    }

    /// `DiveState` üretiminde kullanılacak türetilmiş veri demeti.
    public struct Snapshot: Equatable, Sendable {
        public let currentDepth: Double
        public let maxDepth: Double
        public let ambientPressure: Double
        public let ceilingDepth: Double
        public let nextStopDepth: Double?
        public let leadingCompartment: Int
        public let tissuePressures: [Double]
        public let gradientFactor: Double
        public let gf99: Double
        public let po2: Double
        public let ndl: TimeInterval
        public let tts: TimeInterval
        public let desaturation: TimeInterval
        public let noFly: TimeInterval
    }
}