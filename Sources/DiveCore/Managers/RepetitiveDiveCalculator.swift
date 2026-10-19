import Foundation

/// **Tekrar dalış hesaplayıcısı** — artık gaz yükünü (residual N₂) hesaba katar.
///
/// ADIM 8 gereksinimi: "Tekrar Dalış Hesaplayıcısı — tekrarlı dalışlar için
/// artık gaz yükünü hesaplayan ekran".
///
/// Senaryo: 09:00'da 30 m/25 dk dalışı yapıldı, 10:30'da tekrar 30 m'e inilecek.
/// İkinci dalışın NDL'si ilk dalışın bıraktığı doku yükü nedeniyle **daha
/// kısadır**. Bu hesaplayıcı ikinci dalışın tamamını önceden simüle eder:
///
/// - Kalan NDL (mevcut derinlikte, mevcut doku durumuyla),
/// - Zorunlu deko planı,
/// - Toplam emniyet durağı ve deko süresi,
/// - Uçuş yasağı (dalış sonunda),
/// - Önerilen gaz (MOD'a göre).
public struct RepetitiveDiveCalculator {

    /// Tekrarlı dalış sonucu.
    public struct Result: Equatable, Sendable {
        /// Hedef derinlik (m)
        public let targetDepth: Double
        /// Planlanan süre (saniye)
        public let plannedDuration: TimeInterval
        /// Gerçekçi NDL (artık yük düşülerek)
        public let effectiveNDL: TimeInterval
        /// Sıfırdan başlayan NDL (referans — fark görülebilir)
        public let freshNDL: TimeInterval
        /// Artık yükün NDL'ye etkisi (saniye, negatif = kısalma)
        public let ndlPenalty: TimeInterval
        /// Deko zorunluluğu var mı
        public let hasDecoObligation: Bool
        /// Planlanan deko durakları
        public let plan: DecoStopPlan
        /// Dalış sonundaki uçuş yasağı (saniye)
        public let noFlyTime: TimeInterval
        /// Önerilen gaz (MOD'a göre)
        public let suggestedGas: GasMix
        /// Uyarı notları
        public let warnings: [String]
        /// Planlanan dalışın **bitiş dokuları** (deko tamamlanmış hâliyle)
        ///
        /// - Note: Bir sonraki dalışın veya kabin basıncı hesabının girdisidir.
        public let endTissues: TissueModel

        public init(targetDepth: Double, plannedDuration: TimeInterval,
                    effectiveNDL: TimeInterval, freshNDL: TimeInterval,
                    hasDecoObligation: Bool, plan: DecoStopPlan,
                    noFlyTime: TimeInterval, suggestedGas: GasMix, warnings: [String],
                    endTissues: TissueModel = TissueModel()) {
            self.targetDepth = targetDepth
            self.plannedDuration = plannedDuration
            self.effectiveNDL = effectiveNDL
            self.freshNDL = freshNDL
            self.ndlPenalty = effectiveNDL - freshNDL
            self.hasDecoObligation = hasDecoObligation
            self.plan = plan
            self.noFlyTime = noFlyTime
            self.suggestedGas = suggestedGas
            self.warnings = warnings
            self.endTissues = endTissues
        }

        /// Yüzde olarak ne kadar kısaldı?
        public var ndlLossPercent: Double {
            guard freshNDL > 0 else { return 0 }
            return max(0, -ndlPenalty / freshNDL * 100)
        }
    }

    // MARK: - Hesaplama

    /// Tekrarlı dalış hesabı.
    ///
    /// - Parameters:
    ///   - tissues: Önceki dalıştan kalan doku durumu
    ///   - targetDepth: Hedef derinlik (m)
    ///   - plannedDuration: Planlanan süre (saniye)
    ///   - gradientFactors: GF ayarı
    ///   - gas: Kullanılacak gaz
    ///   - maxPO2: Azami PO₂
    ///   - water: Su tipi
    ///   - includeSafetyStop: Emniyet durağı planlansın mı
    ///   - deepStops: Derin durak ayarı
    public static func calculate(tissues: TissueModel,
                                 targetDepth: Double,
                                 plannedDuration: TimeInterval,
                                 gradientFactors: GradientFactors = .conservative,
                                 gas: GasMix = .air,
                                 maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                 water: DivePhysics.WaterType = .salt,
                                 includeSafetyStop: Bool = true,
                                 deepStops: DeepStopCalculator.Settings = .disabled) -> Result {
        var warnings: [String] = []

        // 1) Mevcut (artık) yükle NDL — mevcut dokularla, hedef derinlikte
        var residualEngine = DecoEngine(gradientFactors: gradientFactors,
                                        gases: [gas, .oxygen], gasCylinderIndex: 0)
        residualEngine.restore(tissues: tissues)
        let effectiveNDL = residualEngine.noDecompressionLimit(atDepth: targetDepth)

        // 2) Referans: sıfırdan başlayan NDL
        let freshEngine = DecoEngine(gradientFactors: gradientFactors,
                                     gases: [gas, .oxygen], gasCylinderIndex: 0)
        let freshNDL = freshEngine.noDecompressionLimit(atDepth: targetDepth)

        // 3) Dalışı tam olarak simüle et (iniş + dibe bekleme)
        var engine = residualEngine
        let descentTime = targetDepth / DiveSafetyLimits.recommendedDescentRate * 60
        engine.update(toDepth: targetDepth, duration: descentTime, gas: gas)
        if plannedDuration > 0 {
            engine.update(toDepth: targetDepth, duration: plannedDuration, gas: gas)
        }

        // 4) Deko planı (artık yükle gösterilerek)
        let plan = DecoStopPlan.make(from: engine,
                                     currentDepth: targetDepth,
                                     includeSafetyStop: includeSafetyStop,
                                     deepStopSettings: deepStops)

        // 5) Dalış sonu uçuş yasağı (deko tamamlandıktan sonraki dokularla)
        var exitEngine = engine
        if engine.ceiling(atDepth: 0).depthMeters > 0 {
            exitEngine.update(toDepth: 0,
                              duration: max(0, engine.timeToSurface(fromDepth: targetDepth)),
                              gas: engine.currentGas)
            exitEngine.update(toDepth: 0, duration: plan.totalTime, gas: .oxygen)
        }
        let noFly = exitEngine.noFlyTime()

        // 6) Gaz önerisi (MOD'a göre)
        let suggested = GasMix.nitrox(
            NitroxPicker.recommendedPercent(targetDepth: targetDepth, maxPO2: maxPO2, water: water))
            ?? .air

        // 7) Uyarılar
        if effectiveNDL < freshNDL * 0.5 {
            warnings.append("Artık yük nedeniyle NDL yarıdan az kaldı")
        }
        if effectiveNDL <= 0 {
            warnings.append("Bu derinlikte artık deko zorunluluğu var")
        }
        if plan.hasDecoObligation {
            warnings.append("Planlı süre deko üretiyor: \(DurationFormatter.clock(plan.totalHoldTime)) durak süresi")
        }
        if gas.maximumOperatingDepth(maxPO2: maxPO2, water: water) < targetDepth {
            warnings.append("\(gas.label) bu derinlikte kullanılamaz → \(suggested.label) önerilir")
        }
        if tissues.leadingNitrogenPressure > TissueModel.surfaceNitrogenPressure(water: water) + 1.0 {
            warnings.append("Ciddi artık yük — yüzey aralığını uzat")
        }

        return Result(targetDepth: targetDepth, plannedDuration: plannedDuration,
                      effectiveNDL: effectiveNDL, freshNDL: freshNDL,
                      hasDecoObligation: plan.hasDecoObligation, plan: plan,
                      noFlyTime: noFly, suggestedGas: suggested, warnings: warnings,
                      endTissues: exitEngine.tissues)
    }

    /// Bir gün içindeki dalışları sırayla hesaplayan **çoklu dalış** planlayıcı.
    ///
    /// - Note: Her dalış kendi deko çıkışıyla tamamlanır; yüzey aralığı dokuları
    ///   serbest bırakır (böylece "aşırı yükleme" senaryosu modellenmez).
    public static func sequence(dives: [(depth: Double, duration: TimeInterval)],
                                startTissues: TissueModel = TissueModel(),
                                surfaceInterval: TimeInterval = 2 * 3600,
                                gradientFactors: GradientFactors = .conservative,
                                gas: GasMix = .air,
                                maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                water: DivePhysics.WaterType = .salt) -> [Result] {
        var tissues = startTissues
        var results: [Result] = []

        for dive in dives {
            let result = calculate(tissues: tissues,
                                   targetDepth: dive.depth,
                                   plannedDuration: dive.duration,
                                   gradientFactors: gradientFactors,
                                   gas: gas, maxPO2: maxPO2, water: water)

            // Dalış sonrası dokular: çıkış + yüzey aralığı
            var engine = DecoEngine(gradientFactors: gradientFactors,
                                    gases: [gas, .oxygen], gasCylinderIndex: 0)
            engine.restore(tissues: tissues)
            engine.update(toDepth: dive.depth,
                          duration: dive.depth / DiveSafetyLimits.recommendedDescentRate * 60, gas: gas)
            engine.update(toDepth: dive.depth, duration: dive.duration, gas: gas)
            var after = engine
            after.update(toDepth: 0, duration: result.plan.totalTime, gas: .oxygen)
            after.update(toDepth: 0, duration: surfaceInterval, gas: gas)
            tissues = after.tissues

            results.append(result)
        }
        return results
    }
}

extension DiveSafetyLimits {
    /// Önerilen iniş hızı (m/dk) — hesaplamaların simülasyonu için.
    public static let recommendedDescentRate: Double = 15
}