import Foundation

/// Mevcut doku durumundan hesaplanan **dekompresyon durağı planı**.
///
/// ADIM 4 gereksinimi: dalgıç hangi durada ne kadar kalacak? Bu plan
/// 3 m'lik ızgaraya yuvarlanmış durakları, varış/durma/kalkış sürelerini ve
/// toplam yüzeye çıkış süresini (TTS) verir.
public struct DecoStopPlan: Equatable, Codable, Sendable {

    /// Tek bir planlanmış dura��.
    public struct Stop: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        /// Durağın derinliği (m) — 3 m'lik ızgara
        public let depth: Double
        /// Başlangıç anından varış süresi (saniye)
        public let arrivalTime: TimeInterval
        /// Bu durakta kalınacak süre (saniye)
        public let holdTime: TimeInterval
        /// Kalkış anı (başlangıçtan itibaren, saniye)
        public var departureTime: TimeInterval { arrivalTime + holdTime }
        /// Bu durakta hangi gaz kullanılır (6 m'den sığ → saf O2)
        public let gas: GasMix
        /// Emniyet durağı mı (isteğe bağlı, eğer tavan yoksa planlanır)
        public let isSafetyStop: Bool

        public init(id: UUID = UUID(), depth: Double,
                    arrivalTime: TimeInterval, holdTime: TimeInterval,
                    gas: GasMix, isSafetyStop: Bool = false) {
            self.id = id
            self.depth = depth
            self.arrivalTime = arrivalTime
            self.holdTime = holdTime
            self.gas = gas
            self.isSafetyStop = isSafetyStop
        }

        /// "6 m · 02:30" gibi kısa etiket.
        public var label: String {
            "\(Int(depth)) m · \(DurationFormatter.clock(holdTime))"
        }

        /// Durak tamamen atlanabilir mi (kalkış anında tavan bu derinliğin
        /// üstündeyse)?
        public var isOptional: Bool { holdTime <= 0 }
    }

    /// Planlanan duraklar (yüzey hariç, derinlemeden yüzeye).
    public let stops: [Stop]
    /// Derin duraklar (ADIM 6) — derinlemeden yüzeye
    public let deepStops: [DeepStopCalculator.DeepStop]
    /// Mevcut derinlikten ilk durağa çıkış süresi (saniye)
    public let ascentTime: TimeInterval
    /// Yüzeye varış süresi (saniye) — `DiveState.timeToSurface` ile tutarlı
    public let totalTime: TimeInterval
    /// Planın üretildiği anlık tavan (m)
    public let ceilingDepth: Double
    /// Kullanılan çıkış hızı (m/dk)
    public let ascentRate: Double
    /// Deko zorunluluğu var mı?
    public var hasDecoObligation: Bool { !stops.isEmpty && stops.contains { !$0.isSafetyStop } }

    /// Canlı (yapılması gereken) derin durak sayısı.
    public var liveDeepStopCount: Int { DeepStopCalculator.liveStopCount(deepStops) }

    /// Derin duraklarda geçirilecek toplam süre (saniye).
    public var deepStopHoldTime: TimeInterval { DeepStopCalculator.totalHoldTime(deepStops) }

    public init(stops: [Stop], deepStops: [DeepStopCalculator.DeepStop] = [],
                ascentTime: TimeInterval, totalTime: TimeInterval,
                ceilingDepth: Double, ascentRate: Double) {
        self.stops = stops
        self.deepStops = deepStops
        self.ascentTime = ascentTime
        self.totalTime = totalTime
        self.ceilingDepth = ceilingDepth
        self.ascentRate = ascentRate
    }

    /// İlk (en derin) durağın derinliği.
    public var firstStopDepth: Double? { stops.first?.depth }

    /// Toplam durak süresi (saniye).
    public var totalHoldTime: TimeInterval { stops.reduce(0) { $0 + $1.holdTime } }

    /// Derinlikten yüzeye toplam tırmanış mesafesi (m).
    public var totalAscentDistance: Double { stops.reduce(0) { $0 + $1.depth } }

    /// Yüzeye varış zaman damgası (başlangıç tarihinden).
    public func surfaceTime(from start: Date) -> Date {
        start.addingTimeInterval(totalTime)
    }

    // MARK: - Hesaplama

    /// Mevcut doku durumundan plan üretir.
    ///
    /// - Parameters:
    ///   - engine: Mevcut dekompresyon durumu (değiştirilmez)
    ///   - currentDepth: Bulunulan derinlik (m)
    ///   - ascentRate: Çıkış hızı (m/dk)
    ///   - safetyStopDepth: Emniyet durağı derinliği (tavan yoksa planlanır)
    ///   - includeSafetyStop: Emniyet durağı planlansın mı
    ///   - resolution: Simülasyon çözünürlüğü (saniye)
    public static func make(from engine: DecoEngine,
                            currentDepth: Double,
                            ascentRate: Double = DiveSafetyLimits.recommendedAscentRate,
                            safetyStopDepth: Double = DiveSafetyLimits.safetyStopDepth,
                            includeSafetyStop: Bool = true,
                            resolution: TimeInterval = 10,
                            minimumHold: TimeInterval = 120,
                            surfaceBuffer: TimeInterval = 60,
                            deepStopSettings: DeepStopCalculator.Settings = .disabled) -> DecoStopPlan {
        var tissues = engine.tissues
        let safeRate = max(0.1, ascentRate)
        let ceiling = engine.ceiling(atDepth: currentDepth).depthMeters

        // 1) İlk durak: tavanın 3 m'lik ızgaraya aşağı yuvarlanmış hâli.
        //    Tavan yoksa isteğe bağlı emniyet durağı planlanır.
        var scratchDepth = currentDepth
        var nextStop = tissues.nextStopDepth(atDepth: currentDepth) ?? 0
        var isSafetyStop = false
        if nextStop <= 0 {
            nextStop = includeSafetyStop ? safetyStopDepth : 0
            isSafetyStop = nextStop > 0
        }

        var stops: [Stop] = []
        var clock: TimeInterval = 0
        var count = 0
        let maximumStops = 20
        let maximumHold: TimeInterval = 60 * 60

        // 2) Durakları sırayla gez (motorun TTS hesabıyla aynı yöntem)
        while nextStop > 0, count < maximumStops {
            // Durak derinliğine çıkış
            if nextStop < scratchDepth {
                let ascent = (scratchDepth - nextStop) / safeRate * 60
                tissues.step(fromDepth: scratchDepth, toDepth: nextStop,
                             duration: ascent, gas: engine.currentGas)
                clock += ascent
                scratchDepth = nextStop
            }

            // Durakta tavan bir üst kademeye çıkana kadar bekle.
            // Simülasyon **saf O₂** ile yapılır (motorun TTS hesabıyla aynı),
            // böylece plan süresi TTS ile birebir örtüşür. Dalgıca önerilen gaz
            // ise 6 m'den sığda O₂, derinde mevcut gazdır.
            let simulationGas: GasMix = .oxygen
            let recommendedGas: GasMix = nextStop <= 6 ? .oxygen : engine.currentGas
            var held: TimeInterval = 0
            while held < maximumHold {
                tissues.step(atDepth: nextStop, duration: resolution, gas: simulationGas)
                held += resolution
                let cleared = tissues.nextStopDepth(atDepth: nextStop).map { $0 < nextStop } ?? true
                if held >= minimumHold && cleared { break }
            }
            clock += held
            stops.append(Stop(depth: nextStop,
                              arrivalTime: clock - held,
                              holdTime: held,
                              gas: recommendedGas,
                              isSafetyStop: isSafetyStop))
            isSafetyStop = false
            count += 1

            // Sonraki kademe
            let newStop = tissues.nextStopDepth(atDepth: nextStop)
            nextStop = min(newStop ?? 0, nextStop - DiveSafetyLimits.decoStopInterval)
            if nextStop < 0 { nextStop = 0 }
        }

        // 3) Son duraktan (veya doğrudan) yüzeye çıkış + nörolojik tampon
        if scratchDepth > 0 {
            let finalAscent = scratchDepth / safeRate * 60
            tissues.step(fromDepth: scratchDepth, toDepth: 0,
                         duration: finalAscent, gas: engine.currentGas)
            clock += finalAscent
        }
        clock += surfaceBuffer

        // Derin duraklar (dalışın azami derinliği ve ilk deko durağından)
        let deepStops = DeepStopCalculator.deepStops(
            tissues: engine.tissues,
            maxDepth: engine.tissues.maxDepth,
            firstDecoStopDepth: TissueModel.roundToStopInterval(ceiling),
            gradientFactors: engine.gradientFactors,
            settings: deepStopSettings)

        return DecoStopPlan(stops: stops, deepStops: deepStops,
                            ascentTime: stops.first?.arrivalTime ?? clock,
                            totalTime: clock, ceilingDepth: ceiling, ascentRate: safeRate)
    }

    /// Planı metin olarak üretir (dalış planı / ADIM 5 dökümü).
    public func describe(includingSurface: Bool = true) -> String {
        var lines: [String] = []
        for deep in deepStops where deep.isLive {
            lines.append("\(Int(deep.depth)) m — derin durak (isteğe bağlı)")
        }
        for stop in stops {
            let tag = stop.isSafetyStop ? " (emniyet)" : ""
            lines.append("\(Int(stop.depth)) m — \(DurationFormatter.clock(stop.holdTime))\(tag), \(stop.gas.label)")
        }
        if includingSurface {
            lines.append("Yüzey — \(DurationFormatter.clock(totalTime)) toplam")
        }
        return lines.joined(separator: "\n")
    }
}