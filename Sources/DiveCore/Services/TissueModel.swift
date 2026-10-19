import Foundation

/// Bühlmann **ZH-L16C** Dekompresyon Kuramı — doku (kompartman) modeli.
///
/// Saf matematiksel modül: Foundation dışında hiçbir bağımlılığı yoktur,
/// `Date`, `UserDefaults`, UI vb. içermez; bu sayede deterministik test edilir.
///
/// ## Kaynaklar
/// - A. A. Bühlmann, *Decompression / Decompression Sickness* (1984)
/// - Wikipedia: *Bühlmann decompression algorithm* (M-değeri ve katsayı tanımları)
/// - Subsurface `core/deco.c` (GF uygulaması ve durum yönetimi)
///
/// ## 1) Alveoler inert gaz basıncı
/// ```
/// P_alv = (P_amb − P_H2O) * Q        // Q = inert gaz oranı, P_H2O = 0.0627 bar
/// ```
///
/// ## 2) Doku yüklenmesi — Schreiner denklemi (sabit hızlı yükselme/alçalma)
/// ```
/// P_t(t) = P_alv(0) + R·(t − 1/k) − (P_alv(0) − P_t(0) − R/k)·e^(−k·t)
/// ```
///
/// ## 3) M-değeri (toleranslanan inert gaz basıncı) — mutlak basınçla
/// ```
/// P_igtol = a + P_amb / b
/// ```
///
/// ## 4) Gradient Factor ile tolerans — *toleranslanan ambient basıncı*
/// `gf` oranı (0...1), M-değeri ile ambient arasındaki farkın ne kadarına
/// izin verileceğini belirler. Tersine çözülürse bir dokunun çıkabileceği
/// en sığ ambient basıncı (bar) elde edilir:
/// ```
/// P_amb_tol = (P_tissue − gf·a) / (gf/b + 1 − gf)
/// ```
///
/// Tavan (ceiling) = tüm kompartmanların `P_amb_tol` değerlerinin **en büyüğü**,
/// yüzeyin altına indirilmez.
public struct TissueModel: Equatable, Codable, Sendable {

    // MARK: - ZH-L16C parametreleri

    /// N2 yarı ömürleri (**dakika**).
    public static let halfTimes: [Double] = [
        4.0, 8.0, 12.5, 18.5, 27.0, 38.3, 54.3, 77.0,
        109.0, 146.0, 187.0, 239.0, 305.0, 390.0, 498.0, 635.0
    ]

    /// ZH-L16C "a" katsayıları (bar).
    public static let aCoefficients: [Double] = [
        1.1696, 1.0000, 0.8618, 0.7562, 0.6200, 0.5043, 0.4410, 0.4000,
        0.3750, 0.3500, 0.3295, 0.3065, 0.2835, 0.2610, 0.2480, 0.2327
    ]

    /// ZH-L16C "b" katsayıları (boyutsuz).
    public static let bCoefficients: [Double] = [
        0.5578, 0.6514, 0.7222, 0.7825, 0.8126, 0.8434, 0.8693, 0.8910,
        0.9092, 0.9222, 0.9319, 0.9403, 0.9477, 0.9544, 0.9602, 0.9653
    ]

    public static let compartmentCount = 16

    // MARK: - Durum

    /// 16 kompartmanın N2 basınçları (bar, mutlak).
    public private(set) var nitrogenPressures: [Double]

    /// Bu modelin ait olduğu su tipi.
    public let water: DivePhysics.WaterType

    /// Kullanılan GF düzenlemesi.
    public var gradientFactors: GradientFactors

    /// Bu dalışta görülen **en derin tavan basıncı** (bar) — GF interpolasyonunun
    /// alt ucunu (GF Low) tanımlar. Subsurface'in `gf_low_pressure_this_dive` mantığı.
    public private(set) var deepestCeilingPressure: Double

    /// Toplam geçen süre (saniye).
    public private(set) var elapsed: TimeInterval

    /// İstatistik: takip edilen azami derinlik (m)
    public private(set) var maxDepth: Double

    // MARK: - Başlatıcılar

    /// Tüm dokular yüzey denge değerinde başlatılmış boş model.
    public init(
        gradientFactors: GradientFactors = .default,
        water: DivePhysics.WaterType = .salt
    ) {
        self.gradientFactors = gradientFactors
        self.water = water
        self.nitrogenPressures = Array(repeating: TissueModel.surfaceNitrogenPressure(water: water),
                                       count: TissueModel.compartmentCount)
        self.deepestCeilingPressure = DivePhysics.surfacePressure
        self.elapsed = 0
        self.maxDepth = 0
    }

    /// Belirli N2 basınçlarından model oluşturur (test / geri yükleme).
    public init(
        nitrogenPressures: [Double],
        gradientFactors: GradientFactors = .default,
        water: DivePhysics.WaterType = .salt,
        elapsed: TimeInterval = 0
    ) {
        precondition(nitrogenPressures.count == TissueModel.compartmentCount,
                     "ZH-L16C tam olarak \(TissueModel.compartmentCount) kompartman içerir.")
        self.nitrogenPressures = nitrogenPressures
        self.gradientFactors = gradientFactors
        self.water = water
        self.elapsed = elapsed
        self.maxDepth = 0
        self.deepestCeilingPressure = DivePhysics.surfacePressure
    }

    // MARK: - Yardımcı hesaplar

    /// Yüzeyde denge halindeki alveoler N2 basıncı (bar).
    public static func surfaceNitrogenPressure(
        water: DivePhysics.WaterType = .salt,
        gas: GasMix = .air
    ) -> Double {
        DivePhysics.alveolarNitrogenPressure(
            ambientPressure: DivePhysics.surfacePressure,
            nitrogenFraction: gas.nitrogenFraction)
    }

    /// Bir kompartmanın N2 basıncı.
    public subscript(index: Int) -> Double { nitrogenPressures[index] }

    /// M-değeri: verilen ambient basıncında toleranslanan inert gaz basıncı (bar).
    public static func mValue(compartment index: Int, ambientPressure: Double) -> Double {
        aCoefficients[index] + ambientPressure / bCoefficients[index]
    }

    /// Bir dokunun çıkabileceği en sığ ambient basıncı (bar).
    ///
    /// `P_amb_tol = (P_tissue − gf·a) / (gf/b + 1 − gf)`
    public static func toleratedAmbientPressure(
        tissueNitrogen: Double,
        compartment index: Int,
        gf: Double
    ) -> Double {
        let a = aCoefficients[index]
        let b = bCoefficients[index]
        let denominator = gf / b + 1.0 - gf
        guard abs(denominator) > 1e-12 else { return DivePhysics.surfacePressure }
        return (tissueNitrogen - gf * a) / denominator
    }

    // MARK: - GF interpolasyonu

    /// Derinlik (basınç) ile GF arasındaki lineer interpolasyon.
    ///
    /// - Yüzeyde (1 bar) `high`
    /// - Dalışın en derin tavanında `low`
    /// - Arada lineer
    public func gradientFactor(atPressure pressure: Double) -> Double {
        let lowValue = gradientFactors.deepValue
        let highValue = gradientFactors.surfaceValue

        if pressure >= deepestCeilingPressure || deepestCeilingPressure <= DivePhysics.surfacePressure + 0.001 {
            return lowValue
        }
        if pressure <= DivePhysics.surfacePressure { return highValue }

        let fraction = ((pressure - DivePhysics.surfacePressure)
                        / (deepestCeilingPressure - DivePhysics.surfacePressure)).clamped(to: 0...1)
        return lowValue + (highValue - lowValue) * fraction
    }

    // MARK: - Schreiner denklemi ile adımlama

    /// Gazla, verilen sürede derinliği `fromDepth` -> `toDepth` değiştirir.
    ///
    /// Derinlik değişimi aralık boyunca doğrusal (sabit hız) kabul edilir.
    ///
    /// - Parameters:
    ///   - fromDepth: Başlangıç derinliği (m)
    ///   - toDepth: Bitiş derinliği (m)
    ///   - duration: Geçen süre (saniye)
    ///   - gas: Solunan gaz karışımı
    public mutating func step(
        fromDepth: Double,
        toDepth: Double,
        duration: TimeInterval,
        gas: GasMix
    ) {
        guard duration > 0 else { return }

        let pAmbStart = DivePhysics.ambientPressure(depthMeters: fromDepth, water: water)
        let pAmbEnd = DivePhysics.ambientPressure(depthMeters: toDepth, water: water)

        let pnStart = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: pAmbStart, nitrogenFraction: gas.nitrogenFraction)
        let pnEnd = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: pAmbEnd, nitrogenFraction: gas.nitrogenFraction)

        // R: alveoler N2 basıncının değişim hızı (bar/saniye)
        let rate = (pnEnd - pnStart) / duration

        for i in 0..<TissueModel.compartmentCount {
            nitrogenPressures[i] = TissueModel.schreiner(
                initialTissuePressure: nitrogenPressures[i],
                inspiredPressure: pnStart,
                rate: rate,
                halfTimeSeconds: TissueModel.halfTimes[i] * 60,
                time: duration)
        }

        elapsed += duration
        maxDepth = Swift.max(maxDepth, fromDepth, toDepth)
        updateDeepestCeilingPressure()
    }

    /// Sabit derinlikte `duration` saniye geçirir.
    public mutating func step(atDepth depth: Double, duration: TimeInterval, gas: GasMix) {
        step(fromDepth: depth, toDepth: depth, duration: duration, gas: gas)
    }

    /// Sabit **ambient basınçta** `duration` saniye geçirir (bar).
    ///
    /// - Note: Uçuş yasağı hesabında kabin basıncı deniz seviyesinden düşük
    ///   olabilir; derinlikle ifade edilemez (`depth ≤ 0` yüzey basıncına
    ///   döner). Bu yüzden doğrudan basınçla çalışılır.
    public mutating func step(atAmbientPressure pressure: Double,
                              duration: TimeInterval,
                              gas: GasMix) {
        step(fromAmbientPressure: pressure, toAmbientPressure: pressure,
             duration: duration, gas: gas)
    }

    /// Ambient basınçtan başka bir basınca geçerek `duration` saniye geçirir.
    public mutating func step(fromAmbientPressure start: Double,
                              toAmbientPressure end: Double,
                              duration: TimeInterval,
                              gas: GasMix) {
        guard duration > 0 else { return }

        let pnStart = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: start, nitrogenFraction: gas.nitrogenFraction)
        let pnEnd = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: end, nitrogenFraction: gas.nitrogenFraction)
        let rate = (pnEnd - pnStart) / duration

        for i in 0..<TissueModel.compartmentCount {
            nitrogenPressures[i] = TissueModel.schreiner(
                initialTissuePressure: nitrogenPressures[i],
                inspiredPressure: pnStart,
                rate: rate,
                halfTimeSeconds: TissueModel.halfTimes[i] * 60,
                time: duration)
        }
        elapsed += duration
        updateDeepestCeilingPressure()
    }

    /// Saf Schreiner denklemi.
    ///
    /// `P(t) = P_alv(0) + R·(t − 1/k) − (P_alv(0) − P_t(0) − R/k)·e^(−k·t)`
    ///
    /// - `halfTimeSeconds`: yarı ömür (saniye). `k = ln2 / halfTime`.
    public static func schreiner(
        initialTissuePressure p0: Double,
        inspiredPressure pi0: Double,
        rate: Double,
        halfTimeSeconds: Double,
        time t: TimeInterval
    ) -> Double {
        guard t > 0 else { return p0 }
        let k = log(2.0) / halfTimeSeconds
        return pi0 + rate * (t - 1.0 / k) - (pi0 - p0 - rate / k) * exp(-k * t)
    }

    /// Modeli yüzey denge durumuna sıfırlar.
    public mutating func reset(gas: GasMix = .air) {
        nitrogenPressures = Array(repeating: TissueModel.surfaceNitrogenPressure(water: water, gas: gas),
                                  count: TissueModel.compartmentCount)
        deepestCeilingPressure = DivePhysics.surfacePressure
        elapsed = 0
        maxDepth = 0
    }

    // MARK: - Tolerans / tavan (ceiling) hesabı

    /// Her kompartmanın toleranslanan ambient basıncı (bar).
    public func toleratedPressures(atDepth depth: Double) -> [Double] {
        let gf = gradientFactor(atPressure: DivePhysics.ambientPressure(depthMeters: depth, water: water))
        return nitrogenPressures.enumerated().map { index, pn in
            TissueModel.toleratedAmbientPressure(tissueNitrogen: pn, compartment: index, gf: gf)
        }
    }

    /// Mevcut derinlikteki **en yüksek tavan (ceiling)**.
    ///
    /// Tüm kompartmanların tolerans basınçlarından türetilir, yüzeyin altına inmez.
    public func ceiling(atDepth depth: Double) -> Ceiling {
        let pressures = toleratedPressures(atDepth: depth)
        let pAmb = DivePhysics.ambientPressure(depthMeters: depth, water: water)

        var bestIndex = 0
        var bestPressure = DivePhysics.surfacePressure
        for (index, value) in pressures.enumerated() where value > bestPressure {
            bestPressure = value
            bestIndex = index
        }

        let rawDepth = DivePhysics.depthMeters(ambientPressure: bestPressure, water: water)
        return Ceiling(
            depthMeters: max(0, rawDepth),
            rawDepthMeters: rawDepth,
            compartment: bestIndex,
            tolerancePressure: bestPressure,
            ambientPressure: pAmb,
            isAboveSurface: rawDepth < 0)
    }

    /// Sabit bir GF ile tavan basıncı (bar) — GF Low ile "en derin tavan" takibi için.
    private func lowestCeilingPressure(gf: Double) -> Double {
        var best = DivePhysics.surfacePressure
        for (index, pn) in nitrogenPressures.enumerated() {
            best = Swift.max(best, TissueModel.toleratedAmbientPressure(
                tissueNitrogen: pn, compartment: index, gf: gf))
        }
        return best
    }

    /// Bu dalıştaki en derin tavanı (GF Low ile) günceller.
    private mutating func updateDeepestCeilingPressure() {
        let candidate = lowestCeilingPressure(gf: gradientFactors.deepValue)
        if candidate > deepestCeilingPressure {
            deepestCeilingPressure = candidate
        }
    }

    /// 3 metrelik durağa yuvarlanmış tavan (m); tavan yoksa `nil`.
    public func nextStopDepth(atDepth depth: Double) -> Double? {
        let ceiling = ceiling(atDepth: depth).depthMeters
        guard ceiling > 0 else { return nil }
        return TissueModel.roundToStopInterval(ceiling)
    }

    /// Derinliği 3 m'lik dekompresyon durağı ızgarasına **aşağı** yuvarlar.
    public static func roundToStopInterval(_ depth: Double,
                                           interval: Double = DiveSafetyLimits.decoStopInterval) -> Double {
        guard depth > 0 else { return 0 }
        return (depth / interval).rounded(.down) * interval
    }

    /// Sabit GF ile tavan derinliği (m) — GF duyarlılığı analizi için.
    public func ceilingDepth(atDepth depth: Double, gf: Double) -> Double {
        let best = lowestCeilingPressure(gf: gf)
        return max(0, DivePhysics.depthMeters(ambientPressure: best, water: water))
    }

    // MARK: - GF99

    /// **GF99 (%)**: En yavaş temizlenen kompartmanın yüzeyde %100 GF'ye
    /// göre ifade edilen aşırı doygunluğu.
    ///
    /// `GF99 = (P_tissue − P_surface) / (P_igtol(P_surface) − P_surface)`
    /// GF99 (%) — **yüzeye göre** tanımlıdır.
    ///
    /// - Note: GF99 tanımı gereği daima *yüzey* referansıdır: "şimdi
    ///   yüzeye çıksaydım tavanım yüzeyin altında kalır mıydı?" sorusuna
    ///   karşılık gelir ve dalış bilgisayarlarında gösterilen değer budur.
    ///   Derinlikte "anlık" GF değeri ise `ceiling(atDepth:)` içindeki
    ///   interpolasyonla bulunur.
    public func gf99(atDepth depth: Double) -> Double {
        gf99(atAmbientPressure: DivePhysics.surfacePressure)
    }

    /// Verilen bir **referans ambient basıncına** göre GF99 (%).
    ///
    /// - Parameters:
    ///   - pressure: Referans basınç (bar). Yüzey GF99 için 1.0; uçuş yasağı
    ///     kabin basıncında hesaplanırken kabin basıncı verilir.
    ///
    /// - Note: Uçuş yasağı kabin basıncında hesaplanırken referans da kabin
    ///   basıncı olmalıdır; aksi halde yavaş çözünen dokular olduğundan
    ///   kısa süre hesaplanır.
    public func gf99(atAmbientPressure pressure: Double) -> Double {
        let reference = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: pressure, nitrogenFraction: DivePhysics.nitrogenFractionOfAir)
        var worst = 0.0

        for index in 0..<TissueModel.compartmentCount {
            let mValue = TissueModel.mValue(compartment: index, ambientPressure: pressure)
            let denominator = mValue - reference
            // Yüzey doygunluğu koruması: tolerans edilen basınç referansın
            // altındaysa kompartman doymuş sayılır ve GF Low değeri kullanılır.
            guard denominator > 1e-9 else {
                worst = Swift.max(worst, gradientFactors.deepValue)
                continue
            }
            let value = (nitrogenPressures[index] - reference) / denominator
            worst = Swift.max(worst, value)
        }

        return Swift.max(0, Swift.min(worst, 10.0)) * 100.0
    }

    // MARK: - Desatürasyon

    /// Yüzeyde tam boşalma süresi (saniye) — verilen GF ölçütüyle.
    public func desaturationTime(gas: GasMix = .air,
                                 gf: Double = 1.0,
                                 resolution: TimeInterval = 10) -> TimeInterval {
        timeUntilCondition(maximumWait: 24 * 3600,
                           resolution: resolution,
                           advance: { model, dt in
                               model.step(atDepth: 0, duration: dt, gas: gas)
                           },
                           condition: { model in
                               model.ceilingDepth(atDepth: 0, gf: gf) <= 0
                           })
    }

    // MARK: - Bisection tabanlı süre arama

    /// Bir koşul sağlanana kadar geçen süreyi bulur.
    ///
    /// ## Neden bisection?
    /// Doku basınçları zamanla **monoton** değişir (yüklenir veya boşalır),
    /// dolayısıyla "koşul sağlandı mı?" yanıtı monoton bir fonksiyondur.
    /// Doğrusal tarama, 24 saatlik bir desatürasyon için
    /// 24·3600/çözünürlük adım gerektirir; **iki kat büyüyen adımla** kaba
    /// bir çerçeve bulunup ardından ikili arama yapıldığında aynı doğruluk
    /// ~40 adımda elde edilir (60–100 kat hızlanma).
    ///
    /// ADIM 12'de bulundu: sığ suda uzun dalışlarda her sensör okuması
    /// (1–2 Hz) saniyeler süren ileri simülasyon çalıştırıyordu.
    ///
    /// - Parameters:
    ///   - maximumWait: Arama üst sınırı (saniye)
    ///   - resolution: Sonuç hassasiyeti (saniye)
    ///   - advance: Modeli verilen süre kadar ilerleten adım
    ///   - condition: Sağlandığında `true` dönen monoton koşul
    /// - Returns: Koşulun sağlandığı süre; sınır içinde sağlanmazsa
    ///   `maximumWait`.
    public func timeUntilCondition(maximumWait: TimeInterval,
                                   resolution: TimeInterval,
                                   advance: (inout TissueModel, _ dt: TimeInterval) -> Void,
                                   condition: (TissueModel) -> Bool) -> TimeInterval {
        // 1) Kaba çerçeve: adımı iki kat büyüterek ilk sağlanma noktasını bul
        var scratch = self
        var elapsed: TimeInterval = 0
        var step = Swift.max(resolution, 60)
        var lower: TimeInterval = 0
        var upper: TimeInterval = maximumWait
        var found = false

        while elapsed < maximumWait {
            let dt = Swift.min(step, maximumWait - elapsed)
            advance(&scratch, dt)
            elapsed += dt
            if condition(scratch) {
                upper = elapsed
                lower = elapsed - dt
                found = true
                break
            }
            lower = elapsed
            step = Swift.min(step * 2, maximumWait - elapsed)
            if step < resolution { step = resolution }
        }

        guard found else { return maximumWait }

        // 2) İkili arama ile hassasiyete indir
        while upper - lower > resolution {
            let middle = (lower + upper) / 2
            var probe = self
            advance(&probe, middle)
            if condition(probe) {
                upper = middle
            } else {
                lower = middle
            }
        }
        return upper
    }

    /// En fazla dolu olan kompartmanın N₂ basıncı (bar).
    public var leadingNitrogenPressure: Double {
        nitrogenPressures.max() ?? TissueModel.surfaceNitrogenPressure(water: water)
    }

    /// Kompartman N₂ basınçlarını verilen artana **yukarıdan** yuvarlar
    /// ("rounded-off" / deep stop yöntemi).
    ///
    /// - Not: Derin durak algoritmasının çekirdeği. Yuvarlama, hızlı
    ///   kompartmanların dipte "kendiliğinden" çözülmesini engelleyerek
    ///   yüzey çıkışında N₂ kaybı yaratır.
    public func roundedOff(incrementPressure increment: Double) -> TissueModel {
        guard increment > 0 else { return self }
        let rounded = nitrogenPressures.map { pressure in
            guard pressure > increment else { return pressure }
            return (pressure / increment).rounded(.up) * increment
        }
        return TissueModel(nitrogenPressures: rounded,
                           gradientFactors: gradientFactors,
                           water: water,
                           elapsed: elapsed)
    }

    /// En fazla dolu olan kompartmanın yarı ömrü (dakika).
    public var leadingCompartmentHalfTime: Double {
        let index = nitrogenPressures.indices.max { nitrogenPressures[$0] < nitrogenPressures[$1] } ?? 0
        return TissueModel.halfTimes[index]
    }
}

// MARK: - Ceiling

/// Tavan (ceiling) hesabının sonucu.
public struct Ceiling: Equatable, Codable, Sendable {
    /// Tavan derinliği (m) — yüzeyin altına inmez.
    public let depthMeters: Double
    /// Sınırlandırılmamış ham değer.
    public let rawDepthMeters: Double
    /// Tavanı belirleyen kompartman indeksi (0...15).
    public let compartment: Int
    /// Toleranslanan ambient basıncı (bar).
    public let tolerancePressure: Double
    /// Mevcut ambient basınç (bar).
    public let ambientPressure: Double
    /// Dokuların yüzeyin üzerinde olduğunu gösterir.
    public let isAboveSurface: Bool

    public var hasDecoObligation: Bool { depthMeters > 0 }

    /// Tavanın 3 m'lik ızgaraya yuvarlanmış hali (duruş derinliği).
    public var stopDepth: Double { TissueModel.roundToStopInterval(depthMeters) }
}