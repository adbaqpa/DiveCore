import Foundation

/// Dalış oturumu yöneticisi.
///
/// Sorumlulukları:
/// 1. Sensör okumalarını dekompresyon motoruna aktarmak (1 Hz ritimde),
/// 2. Anlık `DiveState` üretmek (derinlik, süre, NDL/tavan, hız, sıcaklık, ...),
/// 3. Çıkış hızı ihlalini izlemek ve alarm üretmek,
/// 4. Emniyet durağı sayacını yönetmek,
/// 5. Profil örneklerini ve işaretleri toplamak,
/// 6. Dalış sonunda `LogEntry` üretmek.
///
/// Saf Swift'tir; platform API'si içermez. `@MainActor` olduğu için SwiftUI
/// ile doğrudan gözlenebilir ve dokunsal geri bildirim `HapticEngine`
/// protokolü üzerinden enjekte edilir.
@MainActor
public final class DiveSessionController {

    // MARK: - Yayınlar

    /// Durum her değiştiğinde çağrılır (ADIM 3'teki SwiftUI ekranı bunu dinler).
    public var onStateChange: ((DiveState) -> Void)?
    /// Yeni alarmlar oluştuğunda çağrılır.
    public var onAlarms: (([AlarmAction]) -> Void)?

    // MARK: - Durum

    public private(set) var configuration: DiveConfiguration
    public private(set) var state: DiveState
    public private(set) var samples: [DiveSample] = []
    public private(set) var markers: [DiveMarker] = []
    /// Son üretilen alarm eylemleri
    public private(set) var lastAlarms: [AlarmAction] = []
    /// Dalış sonu raporu (`end()` sonrası dolar)
    public private(set) var lastReport: DiveReport?
    /// Tüm dalış boyunca üretilen alarm sayısı (istatistik)
    public private(set) var alarmCount: Int = 0

    public private(set) var isRunning = false
    public private(set) var isFinished = false

    /// Dekompresyon motoru (ADIM 3/4'te doğrudan sorgulanabilir)
    public private(set) var engine: DecoEngine
    /// Hız takipçisi (ADIM 3'te gösterge için)
    public private(set) var rateMonitor: AscentRateMonitor

    private var alarms: AlarmCoordinator
    private let haptic: HapticEngine?
    /// Çıkış rehberi (tavan tamponu, sonraki dura, talimat)
    private let advisor: AscentAdvisor

    // MARK: - Dahili durum

    private var startDate: Date?
    private var endDate: Date?
    private var lastElapsed: TimeInterval = 0
    private var previousReading: DepthReading?
    private var depthIntegral: Double = 0        // ortalama derinlik için
    private var lastSampleElapsed: TimeInterval = -1e9
    private var activeWarnings: [DiveWarning.Kind: DiveWarning] = [:]
    private var maxGF99: Double = 0
    private var maxPO2: Double = 0
    private var minNDL: TimeInterval = .greatestFiniteMagnitude
    private var safetyStop: SafetyStopState
    private var gasIndex: Int
    private var wasInSafetyZone = false
    private var safetyStopCompletionMarked = false

    // ADIM 12: "öneri" değerlerinin önbelleği (performans)
    //
    // NDL, TTS, desatürasyon ve uçuş yasağı **ileri simülasyonla**
    // hesaplanır (NDL için 6 saate, desatürasyon için 24 saate kadar adım).
    // Değerler saniyeler içinde yalnızca birkaç saniyelik farkla değişir;
    // her sensör okumasında (1–2 Hz) yeniden hesaplamak her okumada
    // binlerce doku adımı demektir.
    //
    // Güvenlik açısından önemli olan değerler (tavan, GF99, PO₂, gaz) **her
    // zaman tam** hesaplanır; yalnızca *görüntüleme* amaçlı bu dört değer
    // kısıtlanır. Deko yükümlülüğü başlayıp bittiğinde ve gaz değiştiğinde
    // önbellek anında geçersiz kılınır.
    public var advisoryRefreshInterval: TimeInterval = 10
    private var advisoryCache: AdvisoryValues?
    private var advisoryObligation = false
    private var advisoryGasIndex = -1

    /// Önbelleklenen öneri değerleri.
    public struct AdvisoryValues: Equatable, Sendable {
        public let ndl: TimeInterval
        public let tts: TimeInterval
        public let desaturation: TimeInterval
        public let noFly: TimeInterval
        public let computedAtElapsed: TimeInterval
    }

    // ADIM 4: dalış istatistikleri ve zorunlu deko durakları
    private var extremes = DiveExtremes()
    private var decoStops: [DecoStopRecord] = []
    private var currentDecoStopDepth: Double?
    private var currentDecoStopArrival: TimeInterval = 0
    private var leftSurfaceAtLeastOnce = false

    // MARK: - Oluşturucu

    public init(configuration: DiveConfiguration = .recreational,
                haptic: HapticEngine? = nil) {
        self.configuration = configuration
        self.haptic = haptic
        self.gasIndex = configuration.startGasIndex

        self.engine = DecoEngine(
            gradientFactors: configuration.gradientFactors,
            water: configuration.water,
            gases: configuration.gases,
            gasCylinderIndex: configuration.startGasIndex)
        self.rateMonitor = AscentRateMonitor(
            limit: configuration.maxAscentRate,
            cautionThreshold: configuration.cautionAscentRate,
            violationHoldTime: configuration.rateViolationHoldTime)
        self.alarms = AlarmCoordinator(
            cooldown: configuration.alarmCooldown,
            fullScreenAlertsEnabled: configuration.fullScreenAlertsEnabled)
        self.advisor = AscentAdvisor(
            maximumAscentRate: configuration.maxAscentRate,
            cautionAscentRate: configuration.cautionAscentRate,
            safetyStopDepth: configuration.safetyStopZoneDepth)
        self.safetyStop = SafetyStopState(
            requiredDepth: configuration.safetyStopZoneDepth,
            requiredDuration: configuration.safetyStopRequiredDuration)
        self.safetyStopCompletionMarked = false

        self.state = DiveState(
            phase: .preDive,
            currentDepth: 0,
            water: configuration.water,
            gas: configuration.startGas,
            gases: configuration.gases,
            gasIndex: configuration.startGasIndex,
            oxygenPartialPressure: configuration.startGas
                .oxygenPartialPressure(atDepth: 0, water: configuration.water),
            maximumOperatingDepth: configuration.startGas
                .maximumOperatingDepth(maxPO2: configuration.maxPO2, water: configuration.water),
            gradientFactors: configuration.gradientFactors,
            safetyStop: safetyStop)
    }

    // MARK: - Yaşam döngüsü

    /// Dalışı başlatır. İlk `ingest` çağrısından önce çağrılmalıdır.
    public func start(at date: Date = Date()) {
        guard !isRunning else { return }
        isRunning = true
        isFinished = false
        startDate = date
        endDate = nil
        lastElapsed = 0
        previousReading = nil
        depthIntegral = 0
        lastSampleElapsed = -1e9
        invalidateAdvisoryCache()
        maxGF99 = 0
        maxPO2 = 0
        minNDL = .greatestFiniteMagnitude
        samples.removeAll()
        markers.removeAll()
        lastAlarms.removeAll()
        lastReport = nil
        alarmCount = 0
        activeWarnings.removeAll()
        wasInSafetyZone = false
        safetyStopCompletionMarked = false
        extremes = DiveExtremes()
        decoStops.removeAll()
        currentDecoStopDepth = nil
        leftSurfaceAtLeastOnce = false
        rateMonitor.reset()
        alarms.reset()
        safetyStop = SafetyStopState(
            requiredDepth: configuration.safetyStopZoneDepth,
            requiredDuration: configuration.safetyStopRequiredDuration)

        state = DiveState(
            phase: .preDive,
            startDate: date,
            water: configuration.water,
            gas: configuration.startGas,
            gases: configuration.gases,
            gasIndex: configuration.startGasIndex,
            oxygenPartialPressure: configuration.startGas
                .oxygenPartialPressure(atDepth: 0, water: configuration.water),
            maximumOperatingDepth: configuration.startGas
                .maximumOperatingDepth(maxPO2: configuration.maxPO2, water: configuration.water),
            gradientFactors: configuration.gradientFactors,
            safetyStop: safetyStop)
        onStateChange?(state)
    }

    /// Dalışı sonlandırır ve `LogEntry` üretir.
    @discardableResult
    public func end(at date: Date = Date()) -> LogEntry? {
        guard isRunning, let start = startDate else { return nil }
        isRunning = false
        isFinished = true
        endDate = date

        // Son okumadan gelen uyarıları kalıcılaştır
        let finalWarnings = Array(activeWarnings.values)
        markers.append(DiveMarker(kind: .end,
                                  elapsed: lastElapsed,
                                  depth: state.currentDepth,
                                  timestamp: date,
                                  label: "Dalış sonu"))

        state = buildState(phase: .ended,
                           reading: nil,
                           rate: nil,
                           warnings: finalWarnings,
                           endDate: date)

        let log = LogEntry(
            startDate: start,
            endDate: date,
            gases: configuration.gases,
            startGasIndex: gasIndex,
            samples: samples,
            maxDepth: state.maxDepth,
            averageDepth: state.averageDepth,
            totalDiveTime: state.diveTime,
            waterTemperatureStart: state.surfaceTemperature,
            waterTemperatureEnd: state.waterTemperature,
            waterTemperatureMin: samples.map(\.temperature).min() ?? state.waterTemperature,
            waterTemperatureMax: samples.map(\.temperature).max() ?? state.waterTemperature,
            cnsPercent: state.cnsPercent,
            otuUnits: state.otuUnits,
            maxPO2: maxPO2,
            maxGF99: maxGF99,
            minimumNoDecompressionLimit: minNDL == .greatestFiniteMagnitude ? 0 : minNDL,
            gradientFactors: configuration.gradientFactors,
            water: configuration.water,
            hadDecoObligation: samples.contains { $0.ceiling > 0 },
            safetyStopCompleted: safetyStop.isComplete,
            safetyStopAccumulated: safetyStop.accumulated,
            noFlyTime: state.noFlyTime,
            recommendedSurfaceInterval: max(state.noFlyTime, 2 * 3600))
        onStateChange?(state)
        lastReport = makeReport(log: log)
        return log
    }

    /// Dalışı iptal eder (veri kaydedilmez).
    public func cancel() {
        isRunning = false
        isFinished = true
    }

    // MARK: - Sensör besleme

    /// Tek bir okumayı işler. Canlı uygulamada **1 Hz** ile çağrılmalıdır.
    public func ingest(_ reading: DepthReading) {
        guard isRunning else { return }

        // Zaman sıfırlanırsa (yüzey aralığı sonrası) takipçiyi tazele
        if reading.elapsed < lastElapsed {
            rateMonitor.reset()
            previousReading = nil
            lastSampleElapsed = -1e9
        }

        let dt = max(0, reading.elapsed - lastElapsed)
        lastElapsed = reading.elapsed

        // 1) Hız takibi (alarm tespiti)
        let rate = rateMonitor.update(with: reading)

        // 2) Dekompresyon motorunu ilerlet
        if dt > 0 {
            engine.update(toDepth: reading.depth,
                          duration: dt,
                          temperature: reading.temperature ?? state.waterTemperature)
            depthIntegral += reading.depth * dt
        }

        // 3) Anlık hesaplar
        //
        // Tavan/GF99/PO₂ her okumada tam hesaplanır; NDL, TTS, desatürasyon
        // ve uçuş yasağı önbellekten gelir (bkz. `advisoryValues`).
        let snapshot = engine.snapshot(atDepth: reading.depth)
        let advisory = advisoryValues(atDepth: reading.depth,
                                      ceilingDepth: snapshot.ceilingDepth,
                                      elapsed: reading.elapsed)
        let gas = configuration.gases.indices.contains(gasIndex)
            ? configuration.gases[gasIndex] : configuration.startGas
        let po2 = gas.oxygenPartialPressure(atDepth: reading.depth, water: configuration.water)
        let mod = gas.maximumOperatingDepth(maxPO2: configuration.maxPO2, water: configuration.water)

        maxGF99 = max(maxGF99, snapshot.gf99)
        maxPO2 = max(maxPO2, po2)
        if advisory.ndl > 0 { minNDL = min(minNDL, advisory.ndl) }
        else if snapshot.ceilingDepth > 0 { minNDL = 0 }

        if reading.depth > 0.5 { leftSurfaceAtLeastOnce = true }

        // Uç değerler (dalış sonu raporu için)
        if rate.smoothedRate > extremes.maxAscentRate { extremes.maxAscentRate = rate.smoothedRate }
        if -rate.smoothedRate > extremes.maxDescentRate { extremes.maxDescentRate = -rate.smoothedRate }
        if let temperature = reading.temperature {
            extremes.minimumTemperature = min(extremes.minimumTemperature, temperature)
            extremes.maximumTemperature = max(extremes.maximumTemperature, temperature)
        }

        // Zorunlu deko durağı takibi
        trackDecoStop(nextStop: snapshot.nextStopDepth, reading: reading, rate: rate)

        // 4) Emniyet durağı sayacı
        updateSafetyStop(depth: reading.depth, dt: dt, timestamp: reading.timestamp, rate: rate)

        // 5) Uyarılar + alarmlar
        let warnings = generateWarnings(reading: reading,
                                        rate: rate,
                                        snapshot: snapshot,
                                        po2: po2,
                                        mod: mod)
        let actions = alarms.actions(for: warnings, elapsed: reading.elapsed)
        lastAlarms = actions
        alarmCount += actions.count
        if !actions.isEmpty {
            haptic?.perform(actions)
            onAlarms?(actions)
        }

        // 6) Faz belirleme + durum yayını
        let phase = determinePhase(reading: reading, rate: rate, snapshot: snapshot)
        state = buildState(phase: phase,
                           reading: reading,
                           rate: rate,
                           snapshot: snapshot,
                           advisory: advisory,
                           warnings: Array(activeWarnings.values))
        previousReading = reading
        onStateChange?(state)

        // 7) Profil örneği kaydı
        recordSampleIfNeeded(reading: reading, snapshot: snapshot, po2: po2)
    }

    /// Bir dizi okumayı sırayla işler (simülatör/senkronizasyon için).
    // MARK: - Öneri değer önbelleği

    /// Önbellekten gelen ya da gerektiğinde yeniden hesaplanan öneri değerler.
    private func advisoryValues(atDepth depth: Double,
                                ceilingDepth: Double,
                                elapsed: TimeInterval) -> AdvisoryValues {
        let obligated = ceilingDepth > 0
        let gasChanged = gasIndex != advisoryGasIndex
        let stale = advisoryCache == nil
            || obligated != advisoryObligation
            || gasChanged
            || elapsed - (advisoryCache?.computedAtElapsed ?? 0) >= advisoryRefreshInterval
            || elapsed < (advisoryCache?.computedAtElapsed ?? 0)   // saat sıfırlandıysa

        if !stale, let cache = advisoryCache {
            return cache
        }

        let values = AdvisoryValues(
            ndl: engine.noDecompressionLimit(atDepth: depth),
            tts: engine.timeToSurface(fromDepth: depth),
            desaturation: engine.desaturationTimeUntilGF99(),
            noFly: engine.noFlyTime(),
            computedAtElapsed: elapsed)
        advisoryCache = values
        advisoryObligation = obligated
        advisoryGasIndex = gasIndex
        return values
    }

    /// Öneri önbelleğini temizler (yeni dalış, gaz değişimi, ayar değişimi).
    public func invalidateAdvisoryCache() {
        advisoryCache = nil
    }

    public func ingest(_ readings: [DepthReading]) {
        for reading in readings { ingest(reading) }
    }

    /// ADIM 11 — **dinamik örnekleme** ile okuma.
    ///
    /// Okuma yalnızca `AdaptiveSampler` izin verirse işlenir; dekompresyon
    /// motoru ve alarmlar bu şekilde pil dostu hale gelir. Güvenlik
    /// durumlarında (deko yükümlülüğü, kritik alarm, ani derinlik değişimi)
    /// örnekleyici **her okumayı** işletir.
    ///
    /// - Returns: Okuma işlendiyse `true`.
    @discardableResult
    public func ingest(_ reading: DepthReading, sampler: inout AdaptiveSampler) -> Bool {
        let context = AdaptiveSamplingPolicy.Context(state: state)
        let accepted = sampler.shouldProcess(context: context, elapsed: reading.elapsed)
        if accepted {
            ingest(reading)
        } else {
            // Reddedilen okumalar yüzey referansını ve zamanı yine de
            // ilerletir ki sıfırlama algılanabilsin.
            if reading.elapsed < lastElapsed {
                lastElapsed = reading.elapsed
            }
        }
        return accepted
    }

    /// Yön bilgisi güncellemesi (CoreLocation/CMMotion'dan).
    public func updateHeading(_ degrees: Double?) {
        state.heading = degrees
    }

    // MARK: - Gaz ve işaretler

    /// Silindir değiştirir.
    public func switchGas(to index: Int) {
        invalidateAdvisoryCache()
        guard configuration.gases.indices.contains(index) else { return }
        gasIndex = index
        engine.switchGas(to: index, gases: configuration.gases)
        state.gasIndex = index
        state.gas = configuration.gases[index]

        let gas = configuration.gases[index]
        state.maximumOperatingDepth = gas.maximumOperatingDepth(
            maxPO2: configuration.maxPO2, water: configuration.water)

        markers.append(DiveMarker(kind: .gasChange,
                                  elapsed: lastElapsed,
                                  depth: state.currentDepth,
                                  timestamp: lastTimestamp,
                                  label: "Gaz değişikliği → \(gas.label)"))
    }

    /// Yer imi ekler (Action Button).
    public func addMarker(label: String = "İşaret") {
        markers.append(DiveMarker(kind: .marker,
                                  elapsed: lastElapsed,
                                  depth: state.currentDepth,
                                  timestamp: lastTimestamp,
                                  label: label))
    }

    private var lastTimestamp: Date {
        previousReading?.timestamp ?? startDate ?? Date()
    }

    // MARK: - Emniyet durağı

    /// Emniyet durağı bölgesine girmiş mi?
    ///
    /// Kurallar:
    /// 1. Dalgıç önce bölgenin **altında** bulunmuş olmalı (iniş sırasındaki
    ///    sığ geçiş sayacı tetiklemez),
    /// 2. Sualtında ve **aşağı inmiyor** olmalı,
    /// 3. Bölgeden çıkarken 1 m histerezis uygulanır (5↔6 m salınımı tekrar
    ///    tetiklemez).
    private func updateSafetyStop(depth: Double,
                                  dt: TimeInterval,
                                  timestamp: Date,
                                  rate: AscentRateUpdate) {
        let zone = configuration.safetyStopZoneDepth
        // Tolerans bandı: nefes salınımı ve ölçüm gürültüsü (±0.1 m) sayacın
        // yarısını atlatmasın. Gerçek bilgisayarlar da benzer bir bant kullanır.
        let tolerance = 0.5
        let exitZone = zone + 1.5
        let hasBeenBelowZone = state.maxDepth > zone + 0.5
        let descending = rate.smoothedRate < -2.0

        let inZone = depth > 0.3 && depth <= zone + tolerance
            && hasBeenBelowZone && !descending
        // Durağı yukarıdan terk etmek: bölgeden belirgin şekilde sığa çıkıldı
        let leaving = wasInSafetyZone && (depth > exitZone || depth < zone - 1.0)

        if inZone {
            if !wasInSafetyZone {
                wasInSafetyZone = true
                markers.append(DiveMarker(kind: .safetyStopStart,
                                          elapsed: lastElapsed,
                                          depth: depth,
                                          timestamp: timestamp,
                                          label: "Emniyet durağı \(Int(zone)) m"))
            }
            safetyStop.isActive = true
            if !safetyStop.isComplete { safetyStop.accumulated += dt }
            if safetyStop.isComplete && !safetyStopCompletionMarked {
                safetyStopCompletionMarked = true
                markers.append(DiveMarker(kind: .safetyStopComplete,
                                          elapsed: lastElapsed,
                                          depth: depth,
                                          timestamp: timestamp,
                                          label: "Emniyet durağı tamamlandı"))
            }
        } else if leaving {
            wasInSafetyZone = false
            safetyStop.isActive = false
            if !safetyStop.isComplete { safetyStop.wasAbandoned = true }
        } else if depth <= 0.3 {
            // Yüzeye çıkıldı: süre dolmadıysa emniyet durağı atlanmıştır
            if wasInSafetyZone && !safetyStop.isComplete { safetyStop.wasAbandoned = true }
            wasInSafetyZone = false
            safetyStop.isActive = false
        }
        state.safetyStop = safetyStop
    }

    // MARK: - Uyarı üretimi

    private func generateWarnings(reading: DepthReading,
                                  rate: AscentRateUpdate,
                                  snapshot: DecoEngine.Snapshot,
                                  po2: Double,
                                  mod: Double) -> [DiveWarning] {
        var result: [DiveWarning.Kind: DiveWarning] = [:]
        let elapsed = reading.elapsed
        let depth = reading.depth

        func add(_ kind: DiveWarning.Kind,
                 _ severity: DiveWarning.Severity,
                 _ message: String) {
            result[kind] = DiveWarning(kind: kind, severity: severity,
                                       message: message, raisedAtElapsed: elapsed)
        }

        // 1) Hızlı çıkış (en yüksek öncelik)
        if rate.alarmDue || rate.exceededLimit {
            add(.fastAscent, .critical,
                String(format: "ÇIKIŞ HIZI FAZLA! %.1f m/dk (sınır %.0f m/dk)",
                       rate.smoothedRate, configuration.maxAscentRate))
        }
        // Dikkat bandı (7-10 m/dk) yalnızca görsel gösterge olarak sunulur
        // (DiveState.ascentRateStatus); önerilen 9 m/dk çıkışta titreşim üretmek
        // yanlış olurdu.

        // 2) Tavan ihlali
        if snapshot.ceilingDepth > 0 && depth < snapshot.ceilingDepth - 0.5 {
            add(.ceilingViolation, .critical,
                String(format: "TAVAN İHLALİ! %.1f m'nin üzerine çıkmayın", snapshot.ceilingDepth))
        }

        // 3) NDL doldu
        if snapshot.ndl <= 0 && snapshot.ceilingDepth > 0 {
            add(.noDecoLimitReached, .warning, "NDL doldu — dekompresyon zorunlu")
        }

        // 4) Oksijen
        if po2 > configuration.maxPO2 {
            add(.oxygenWarning, .critical,
                String(format: "PO2 %.2f bar — sınır %.1f bar aşıldı!", po2, configuration.maxPO2))
        } else if po2 > configuration.maxPO2 * 0.9 {
            add(.oxygenWarning, .caution,
                String(format: "PO2 %.2f bar — sınıra yakın", po2))
        }
        if engine.oxygen.cnsPercent >= configuration.oxygenWarningPercent {
            add(.cnsLimit, .warning,
                String(format: "CNS %%%.0f — sınıra ulaşıldı", engine.oxygen.cnsPercent))
        }
        if engine.oxygen.otuPercent >= configuration.oxygenWarningPercent {
            add(.otuLimit, .warning,
                String(format: "OTU günlük limitin %%%.0f'i", engine.oxygen.otuPercent))
        }

        // 5) MOD aşımı
        if depth > mod + 0.5 && mod > 0 {
            add(.depthExceeded, .warning,
                String(format: "MOD aşıldı: %.1f m > %.1f m", depth, mod))
        }

        // 6) Emniyet durağı atlandı
        if safetyStop.wasAbandoned {
            add(.safetyStopSkipped, .caution,
                String(format: "Emniyet durağı tamamlanmadı (%@)",
                       DurationFormatter.clock(safetyStop.accumulated)))
        }

        // 7) Gaz değişimi (bilgi)
        if let last = markers.last, last.kind == .gasChange,
           abs(last.elapsed - elapsed) < 2 {
            add(.gasSwitch, .info, "Gaz değişti: \(state.gas.label)")
        }

        // Aktif uyarıları güncelle (kapananlar listeden düşer)
        activeWarnings = result
        return Array(result.values)
    }

    // MARK: - Faz

    private func determinePhase(reading: DepthReading,
                                rate: AscentRateUpdate,
                                snapshot: DecoEngine.Snapshot) -> DivePhase {
        let depth = reading.depth

        // Henüz yüzeyden ayrılmadıysak dalış başlamamıştır
        guard leftSurfaceAtLeastOnce else { return .preDive }

        // Yüzeye çıkıldı
        if depth <= 0.3 { return .surfaced }

        // Emniyet durağı sayacı işliyorsa
        if safetyStop.isActive { return .safetyStop }

        // Zorunlu deko durağında
        if let stop = snapshot.nextStopDepth, abs(depth - stop) < 0.7 { return .decoStop }

        // Histerezis bandı (±1.5 m/dk): dalış sırasındaki mikro salınımlar
        // fazı sürekli değiştirmesin.
        if rate.smoothedRate > 1.5 { return .ascending }
        if rate.smoothedRate < -1.5 { return .descending }
        return .bottom
    }

    // MARK: - Durum üretimi

    private func buildState(phase: DivePhase,
                            reading: DepthReading?,
                            rate: AscentRateUpdate?,
                            snapshot: DecoEngine.Snapshot? = nil,
                            advisory: AdvisoryValues? = nil,
                            warnings: [DiveWarning],
                            endDate: Date? = nil) -> DiveState {
        let snap = snapshot ?? engine.snapshot(atDepth: reading?.depth ?? state.currentDepth)
        // Öneri değerleri önbellekten gelir; yoksa hesaplanır (ör. dalış
        // bitiminde tek seferlik).
        let adv = advisory ?? AdvisoryValues(
            ndl: snap.ndl, tts: snap.tts, desaturation: snap.desaturation,
            noFly: snap.noFly, computedAtElapsed: lastElapsed)
        let depth = reading?.depth ?? state.currentDepth
        let diveTime = max(0, lastElapsed)

        let temperature = reading?.temperature ?? state.waterTemperature
        let gas = configuration.gases.indices.contains(gasIndex)
            ? configuration.gases[gasIndex] : configuration.startGas

        let ascentRate = rate?.smoothedRate ?? 0
        let descentRate = rate.map { $0.smoothedRate < 0 ? -$0.smoothedRate : 0 } ?? 0

        return DiveState(
            phase: phase,
            startDate: startDate,
            endDate: endDate,
            currentDepth: depth,
            maxDepth: max(state.maxDepth, depth, engine.tissues.maxDepth),
            averageDepth: diveTime > 0 ? depthIntegral / diveTime : 0,
            ambientPressure: DivePhysics.ambientPressure(depthMeters: depth, water: configuration.water),
            diveTime: diveTime,
            surfaceInterval: 0,
            previousSurfaceInterval: 0,
            waterTemperature: temperature,
            surfaceTemperature: samples.first?.temperature ?? temperature,
            water: configuration.water,
            ascentRate: ascentRate,
            descentRate: descentRate,
            heading: state.heading,
            gas: gas,
            gases: configuration.gases,
            gasIndex: gasIndex,
            oxygenPartialPressure: gas.oxygenPartialPressure(atDepth: depth, water: configuration.water),
            maximumOperatingDepth: gas.maximumOperatingDepth(maxPO2: configuration.maxPO2, water: configuration.water),
            noDecompressionLimit: adv.ndl,
            ceilingDepth: snap.ceilingDepth,
            nextStopDepth: snap.nextStopDepth,
            timeToSurface: adv.tts,
            gf99: snap.gf99,
            gradientFactors: configuration.gradientFactors,
            leadingTissuePressure: engine.leadingTissuePressure,
            cnsPercent: engine.oxygen.cnsPercent,
            otuUnits: engine.oxygen.otuUnits,
            otuPercent: engine.oxygen.otuPercent,
            safetyStop: safetyStop,
            ascentRateStatus: rate?.status ?? .surface,
            warnings: warnings.sorted { $0.severity > $1.severity },
            desaturationRemaining: adv.desaturation,
            noFlyTime: adv.noFly)
    }

    // MARK: - Profil kaydı

    private func recordSampleIfNeeded(reading: DepthReading,
                                      snapshot: DecoEngine.Snapshot,
                                      po2: Double) {
        guard reading.elapsed - lastSampleElapsed >= configuration.profileSampleInterval else { return }
        lastSampleElapsed = reading.elapsed

        let sample = DiveSample(
            elapsed: reading.elapsed,
            depth: reading.depth,
            temperature: reading.temperature ?? state.waterTemperature,
            ambientPressure: reading.ambientPressure,
            po2: po2,
            ascentRate: rateMonitor.smoothedRate,
            gasIndex: gasIndex,
            gf99: snapshot.gf99,
            ceiling: snapshot.ceilingDepth,
            leadingTissuePressure: engine.leadingTissuePressure)
        samples.append(sample)
    }

    // MARK: - Deko durağı takibi (ADIM 4)

    /// Zorunlu deko duraklarını kaydeder: varış anı, kalış süresi, gaz.
    ///
    /// - Important: Tavan oluştuğu an değil, dalgıç **gerçekten duraktan
    ///   ayrılmadığı** anda kayıt açılır. Aksi halde dibe oturmuş bir dalgıç
    ///   için "3 m'de 16 dk bekledi" gibi anlamsız kayıtlar oluşurdu.
    private func trackDecoStop(nextStop: Double?,
                              reading: DepthReading,
                              rate: AscentRateUpdate) {
        /// Durağa yerleşme toleransı (m)
        let tolerance = 1.5

        guard let stop = nextStop, stop > 0 else {
            closeDecoStop(at: reading.elapsed)
            return
        }

        // Yükseliyorken (durağa doğru gidiyor) veya durağa yerleşmişken
        let ascending = rate.smoothedRate > 1.0
        let atStop = abs(reading.depth - stop) <= tolerance && !ascending

        if atStop {
            // Farklı bir durağa geçiş: öncekini kapat
            if let current = currentDecoStopDepth, abs(current - stop) > 0.5 {
                closeDecoStop(at: reading.elapsed)
            }
            if currentDecoStopDepth == nil {
                currentDecoStopDepth = stop
                currentDecoStopArrival = reading.elapsed
                markers.append(DiveMarker(kind: .decoStop,
                                          elapsed: reading.elapsed,
                                          depth: reading.depth,
                                          timestamp: reading.timestamp,
                                          label: "Deko durağı \(Int(stop)) m"))
            }
        } else if let current = currentDecoStopDepth,
                  abs(reading.depth - current) > tolerance {
            // Durağın dışına çıkıldı (yukarı veya daha derine)
            closeDecoStop(at: reading.elapsed)
        }
    }

    private func closeDecoStop(at elapsed: TimeInterval) {
        guard let depth = currentDecoStopDepth else { return }
        let duration = max(0, elapsed - currentDecoStopArrival)
        // 20 saniyeden kısa "dokunma"lar kaydedilmez (gürültü)
        if duration >= 20 {
            decoStops.append(DecoStopRecord(depth: depth,
                                            arrivalElapsed: currentDecoStopArrival,
                                            duration: duration,
                                            departureElapsed: elapsed,
                                            gas: configuration.startGas))
        }
        currentDecoStopDepth = nil
    }

    // MARK: - ADIM 4 sorguları

    /// Dalış sonu raporunu üretir (dalış sürerken de çağrılabilir).
    public func makeReport(log: LogEntry? = nil) -> DiveReport {
        var report = DiveReport.analyze(state: state, log: log,
                                        decoStops: decoStops, extremes: extremes.resolved,
                                        config: configuration)
        report.markerCount = markers.filter { $0.kind == .marker }.count
        report.gasChangeCount = markers.filter { $0.kind == .gasChange }.count
        return report
    }

    /// Mevcut doku durumundan deko durağı planı.
    public func decoPlan() -> DecoStopPlan {
        DecoStopPlan.make(from: engine,
                          currentDepth: state.currentDepth,
                          ascentRate: DiveSafetyLimits.recommendedAscentRate,
                          safetyStopDepth: configuration.safetyStopZoneDepth)
    }

    /// Çıkış rehberi (tavan tamponu, sonraki dura, talimat).
    public var guidance: AscentAdvisor.Guidance {
        advisor.evaluate(state)
    }

    /// Kaydedilen zorunlu deko durakları.
    public var recordedDecoStops: [DecoStopRecord] { decoStops }

    /// Dalış boyunca ölçülen uç değerler.
    public var measuredExtremes: DiveExtremes { extremes.resolved }

    /// Oksijen riski anlık değerlendirmesi.
    public var oxygenStatus: OxygenStatus {
        OxygenStatus.evaluate(state: state,
                              maxPO2: configuration.maxPO2,
                              warningPercent: configuration.oxygenWarningPercent,
                              dailyOTULimit: configuration.dailyOTULimit)
    }

    // MARK: - Sorgular (ADIM 3 arayüzü için)

    /// Kalibrasyon/test amaçlı mevcut tavan.
    public var ceilingDepth: Double { engine.ceiling(atDepth: state.currentDepth).depthMeters }

    /// Anlık çıkış hızı (m/dk)
    public var ascentRate: Double { rateMonitor.smoothedRate }

    /// Emniyet durağı tamamlandı mı?
    public var isSafetyStopComplete: Bool { safetyStop.isComplete }

    /// Dalışın toplam tırmanışı (m)
    public var totalAscent: Double { rateMonitor.totalAscent }
}