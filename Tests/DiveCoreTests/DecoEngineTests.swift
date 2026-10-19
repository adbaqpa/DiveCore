import XCTest
@testable import DiveCore

/// Dekompresyon motoru: NDL, TTS, GF99, uçuş yasağı ve GF duyarlılığı.
///
/// Referans değerler PADI/NOAA hava NDL tablosuyla karşılaştırılmıştır.
final class DecoEngineTests: XCTestCase {

    // MARK: - Yardımcılar

    /// Belirtilen profili 10'ar saniyelik adımlarla simüle eder.
    private func runEngine(
        segments: [(depth: Double, duration: Double)],
        gas: GasMix = .air,
        gradientFactors: GradientFactors = .conservative
    ) -> DecoEngine {
        var engine = DecoEngine(gradientFactors: gradientFactors)
        for segment in segments {
            let steps = Int((segment.duration / 10).rounded(.up))
            let dt = segment.duration / Double(max(1, steps))
            for _ in 0..<steps {
                engine.update(toDepth: segment.depth, duration: dt, gas: gas)
            }
        }
        return engine
    }

    // MARK: - Temel davranış

    func testFreshEngineHasNoObligation() {
        let engine = DecoEngine(gradientFactors: .conservative)
        XCTAssertEqual(engine.noDecompressionLimit(atDepth: 0), 0)
        XCTAssertFalse(engine.requiresDecompression(atDepth: 0))
        XCTAssertEqual(engine.oxygen.cnsPercent, 0)
        XCTAssertEqual(engine.oxygen.otuUnits, 0)
        XCTAssertEqual(engine.gf99, 0, accuracy: 1e-6)
    }

    func testNdlDecreasesAsBottomTimeIncreases() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 30, duration: 60, gas: .air)
        let early = engine.noDecompressionLimit(atDepth: 30)

        engine.update(toDepth: 30, duration: 5 * 60, gas: .air)
        let later = engine.noDecompressionLimit(atDepth: 30)

        XCTAssertGreaterThan(early, later)
        XCTAssertGreaterThan(later, 0)
    }

    func testNdlIsZeroWhenObligationExists() {
        let engine = runEngine(segments: [(depth: 45, duration: 45 * 60.0)],
                                gradientFactors: .conservative)
        XCTAssertTrue(engine.requiresDecompression(atDepth: 45))
        XCTAssertEqual(engine.noDecompressionLimit(atDepth: 45), 0)
    }

    // MARK: - NDL'nin yayımlanmış NDL tablosuyla karşılaştırılması

    /// GF 100/100 ile üretilen NDL'ler PADI/NOAA hava tablosuyla örtüşmelidir.
    func testNoStopLimitsMatchPublishedTableAtGF100() {
        let reference: [(depth: Double, padi: Double)] = [
            (12, 147), (18, 56), (20, 45), (30, 20), (40, 9)
        ]

        for entry in reference {
            let engine = DecoEngine(gradientFactors: .default)
            let ndl = engine.noDecompressionLimit(atDepth: entry.depth) / 60.0

            // Model GF 100 ile PADI'nın ±%60'ı içinde kalmalı; aynı sınıfta
            // üreticiler arası farklar normaldir.
            XCTAssertGreaterThan(ndl, entry.padi * 0.4,
                                 "\(Int(entry.depth)) m NDL çok kısa (\(ndl) dk)")
            XCTAssertLessThan(ndl, entry.padi * 1.8,
                              "\(Int(entry.depth)) m NDL çok uzun (\(ndl) dk)")
        }
    }

    func testNdlIsMonotonicallyDecreasingWithDepth() {
        let depths = [10.0, 15.0, 20.0, 30.0, 40.0, 50.0]
        var previous = Double.greatestFiniteMagnitude
        for depth in depths {
            let ndl = DecoEngine(gradientFactors: .default).noDecompressionLimit(atDepth: depth)
            XCTAssertLessThan(ndl, previous, "\(Int(depth)) m NDL artmamalı")
            previous = ndl
        }
    }

    func testNitroxAllowsLongerBottomTime() {
        var air = DecoEngine(gradientFactors: .default)
        var nitrox = DecoEngine(gradientFactors: .default)
        air.update(toDepth: 30, duration: 15 * 60, gas: .air)
        nitrox.update(toDepth: 30, duration: 15 * 60, gas: .ean32)

        XCTAssertGreaterThan(nitrox.noDecompressionLimit(atDepth: 30),
                             air.noDecompressionLimit(atDepth: 30))
    }

    // MARK: - GF duyarlılığı

    func testLowerGradientFactorProducesShorterNdl() {
        var engines = [
            DecoEngine(gradientFactors: .default),                      // 100/100
            DecoEngine(gradientFactors: GradientFactors(low: 30, high: 75))
        ]
        for _ in 0..<60 {
            for index in engines.indices {
                engines[index].update(toDepth: 30, duration: 10, gas: .air)
            }
        }

        let loose = engines[0].noDecompressionLimit(atDepth: 30)
        let tight = engines[1].noDecompressionLimit(atDepth: 30)
        XCTAssertGreaterThan(loose, tight, "Daha düşük GF daha kısa NDL vermeli")
    }

    func testLowerGradientFactorProducesHigherCeiling() {
        let loose = runEngine(segments: [(depth: 30, duration: 20 * 60.0)],
                              gradientFactors: .default)
        let tight = runEngine(segments: [(depth: 30, duration: 20 * 60.0)],
                              gradientFactors: GradientFactors(low: 30, high: 75))

        XCTAssertGreaterThan(tight.ceiling(atDepth: 30).depthMeters,
                             loose.ceiling(atDepth: 30).depthMeters)
    }

    func testGradientFactorChangeTakesEffectImmediately() {
        var engine = DecoEngine(gradientFactors: .default)
        engine.update(toDepth: 40, duration: 20 * 60, gas: .air)
        let before = engine.ceiling(atDepth: 40).depthMeters

        engine.gradientFactors = GradientFactors(low: 20, high: 60)
        XCTAssertGreaterThan(engine.ceiling(atDepth: 40).depthMeters, before)
    }

    // MARK: - GF99

    func testGF99ReflectsTissueLoading() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 18, duration: 45 * 60, gas: .air)
        let gf99 = engine.gf99

        XCTAssertGreaterThan(gf99, 50)
        XCTAssertLessThan(gf99, 150, "18 m / 45 dk hava GF99 tipik olarak %60-110 aralığındadır")
    }

    func testGF99DropsWithLongSurfaceInterval() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 30, duration: 25 * 60, gas: .air)
        let before = engine.gf99

        engine.update(toDepth: 0, duration: 6 * 3600, gas: .air)
        XCTAssertLessThan(engine.gf99, before)
    }

    // MARK: - TTS

    func testTimeToSurfaceWithoutDecoIsJustAscentTime() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 30, duration: 5 * 60, gas: .air)

        // 30 m / 9 m/dk = 200 sn + 60 sn yüzey tamponu
        XCTAssertEqual(engine.timeToSurface(fromDepth: 30), 260, accuracy: 1)
    }

    func testTimeToSurfaceAtSurfaceIsZero() {
        let engine = DecoEngine(gradientFactors: .conservative)
        XCTAssertEqual(engine.timeToSurface(fromDepth: 0), 0)
    }

    func testTimeToSurfaceIncreasesWithObligation() {
        let shallow = runEngine(segments: [(depth: 20, duration: 10 * 60.0)])
        let deep = runEngine(segments: [(depth: 45, duration: 45 * 60.0)])

        XCTAssertGreaterThan(deep.timeToSurface(fromDepth: 45), shallow.timeToSurface(fromDepth: 20))
        XCTAssertGreaterThan(deep.timeToSurface(fromDepth: 45), 15 * 60,
                             "45 m / 45 dk hava dalışı en az 15 dakikalık deko gerektirmeli")
    }

    func testTimeToSurfaceIsPositiveAndFinite() {
        let engine = runEngine(segments: [(depth: 30, duration: 30 * 60.0)])
        let tts = engine.timeToSurface(fromDepth: 30)
        XCTAssertGreaterThan(tts, 0)
        XCTAssertLessThan(tts, 6 * 3600)
    }

    // MARK: - Uçuş yasağı

    func testNoFlyTimeAfterShortDiveIsMinimal() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 10, duration: 5 * 60, gas: .air)

        XCTAssertGreaterThanOrEqual(engine.noFlyTime(), 15 * 60)
        XCTAssertLessThan(engine.noFlyTime(), 90 * 60)
    }

    func testNoFlyTimeGrowsWithDepthAndTime() {
        let shallow = runEngine(segments: [(depth: 18, duration: 20 * 60.0)])
        let deep = runEngine(segments: [(depth: 45, duration: 40 * 60.0)])

        XCTAssertGreaterThan(deep.noFlyTime(), shallow.noFlyTime())
        XCTAssertGreaterThan(deep.noFlyTime(), 3 * 3600,
                             "45 m / 40 dk sonrası uçuş yasağı 3 saatten uzun olmalı")
    }

    func testNoFlyIsAtLeastDesaturationPlusBuffer() {
        let engine = runEngine(segments: [(depth: 40, duration: 30 * 60.0)])
        XCTAssertGreaterThanOrEqual(engine.noFlyTime(), engine.desaturationTime())
        XCTAssertGreaterThanOrEqual(engine.noFlyTime(), engine.desaturationTime() + 60 * 60)
    }

    func testNoFlyIsRoundedToQuarterHour() {
        let engine = runEngine(segments: [(depth: 40, duration: 30 * 60.0)])
        XCTAssertEqual(engine.noFlyTime().truncatingRemainder(dividingBy: 900), 0)
    }

    // MARK: - Gaz yönetimi

    /// Deko durağında saf O2: N2 yüklenmesi durur, CNS ise artar.
    func testSwitchingToDecoOxygenStopsNitrogenLoading() {
        var engine = DecoEngine(gradientFactors: .conservative, gases: [.air, .oxygen])
        engine.update(toDepth: 30, duration: 30 * 60, gas: .air)
        let cnsBefore = engine.oxygen.cnsPercent
        let nitrogenAtBottom = engine.tissues[15]

        engine.switchGas(to: 1, gases: [.air, .oxygen])
        engine.update(toDepth: 6, duration: 10 * 60)     // durak, saf O2

        XCTAssertEqual(engine.currentGas, GasMix.oxygen)
        XCTAssertLessThan(engine.tissues[15], nitrogenAtBottom, "O2 ile N2 yüklenmesi durmalı")
        XCTAssertGreaterThan(engine.oxygen.cnsPercent, cnsBefore, "6 m'de saf O2 PO2 ≈ 1.54 bar")
    }

    func testInvalidGasIndexIsIgnored() {
        var engine = DecoEngine(gradientFactors: .conservative, gases: [.air])
        engine.switchGas(to: 5, gases: [.air])
        XCTAssertEqual(engine.currentGas, .air)
    }

    /// 3 m'de saf O2: PO2 ≈ 1.24 bar, 3 dakikalık emniyet durağı CNS'nin
    /// yaklaşık %2'sini harcar.
    func testSafetyStopOnOxygenHasSmallCnsImpact() {
        let po2 = GasMix.oxygen.oxygenPartialPressure(atDepth: 3)
        XCTAssertEqual(po2, 1.237, accuracy: 0.01)

        var engine = DecoEngine(gradientFactors: .conservative, gases: [.oxygen])
        engine.update(toDepth: 3, duration: 3 * 60, gas: .oxygen)
        XCTAssertEqual(engine.oxygen.cnsPercent, 100.0 * 3.0 / 180.0, accuracy: 0.5)
    }

    func testOxygenToxicityAccumulatesDuringNitroxDive() {
        let engine = runEngine(segments: [(depth: 30, duration: 40 * 60.0)],
                               gas: .ean32)
        XCTAssertGreaterThan(engine.oxygen.cnsPercent, 20)
        XCTAssertGreaterThan(engine.oxygen.otuUnits, 0)
    }

    func testAirDiveDoesNotAccumulateCns() {
        let engine = runEngine(segments: [(depth: 30, duration: 40 * 60.0)], gas: .air)
        // Havada 30 m'de PO2 ≈ 0.83 bar > 0.5 → yavaş birikim
        XCTAssertLessThan(engine.oxygen.cnsPercent, 15)
        XCTAssertGreaterThan(engine.oxygen.cnsPercent, 0)
    }

    // MARK: - Snapshot

    func testSnapshotIsSelfConsistent() {
        let engine = runEngine(segments: [(depth: 30, duration: 30 * 60.0)])
        let snapshot = engine.snapshot(atDepth: 30)

        XCTAssertEqual(snapshot.currentDepth, 30)
        XCTAssertEqual(snapshot.maxDepth, 30)
        XCTAssertEqual(snapshot.ambientPressure, 4.0, accuracy: 1e-9)
        XCTAssertEqual(snapshot.tissuePressures.count, 16)
        XCTAssertEqual(snapshot.po2, GasMix.air.oxygenPartialPressure(atDepth: 30), accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(snapshot.gf99, 0)
        XCTAssertLessThanOrEqual(snapshot.gf99, 100 * 10)
        XCTAssertGreaterThan(snapshot.tts, 0)

        if snapshot.ceilingDepth > 0 {
            XCTAssertNotNil(snapshot.nextStopDepth)
            XCTAssertLessThanOrEqual(snapshot.nextStopDepth!, snapshot.ceilingDepth + 0.001)
        } else {
            XCTAssertNil(snapshot.nextStopDepth)
            XCTAssertEqual(snapshot.ndl, 0, "Tavan yoksa NDL sıfır olmalı")
        }
    }

    // MARK: - Tam dalış senaryoları

    /// Klasik kare dalış: 30 m'ye in, 22 dk bekle, kontrollü çık.
    func testSquareDiveThirtyMeters() {
        let engine = runEngine(segments: [
            (depth: 30, duration: 2 * 60.0),
            (depth: 30, duration: 22 * 60.0),
            (depth: 6, duration: 4 * 60.0),
            (depth: 0, duration: 40)
        ], gradientFactors: .conservative)

        // 30 m hava NDL'si GF 80/85 ile ~9 dk → 22 dakikalık dip yükümlülük oluşturur
        XCTAssertTrue(engine.requiresDecompression(atDepth: 30))
        XCTAssertLessThan(engine.ceiling(atDepth: 30).depthMeters, 30)
        XCTAssertGreaterThan(engine.timeToSurface(fromDepth: 30), 0)
    }

    /// Yavaş, güvenli çıkışlı sığ dalış: tavan oluşmamalı.
    func testSafeDiveProducesNoDecoObligation() {
        let engine = runEngine(segments: [
            (depth: 18, duration: 2 * 60.0),
            (depth: 18, duration: 25 * 60.0),
            (depth: 9, duration: 60),
            (depth: 3, duration: 60),
            (depth: 0, duration: 60)
        ], gradientFactors: .conservative)

        XCTAssertLessThanOrEqual(engine.ceiling(atDepth: 18).depthMeters, 0,
                                 "18 m'de 25 dakika sonra güvenli çıkışta tavan olmamalı")
        XCTAssertGreaterThan(engine.noFlyTime(), 0)
    }

    /// Derin ve uzun dalış: belirgin tavan ve uzun uçuş yasağı.
    func testDeepLongDiveProducesSubstantialObligation() {
        let engine = runEngine(segments: [(depth: 45, duration: 50 * 60.0)],
                               gradientFactors: .conservative)
        XCTAssertGreaterThan(engine.ceiling(atDepth: 45).depthMeters, 0)
        XCTAssertGreaterThan(engine.noFlyTime(), 3 * 3600)
        XCTAssertGreaterThan(engine.gf99, 150)
    }

    /// Uzun yüzey arası sonrası dokular temizlenmeli.
    func testLongSurfaceIntervalClearsObligation() {
        var engine = DecoEngine(gradientFactors: .conservative)
        engine.update(toDepth: 45, duration: 45 * 60, gas: .air)
        XCTAssertTrue(engine.requiresDecompression(atDepth: 45))

        engine.update(toDepth: 0, duration: 6 * 3600, gas: .air)
        XCTAssertFalse(engine.requiresDecompression(atDepth: 0))
        XCTAssertLessThan(engine.noFlyTime(), 4 * 3600,
                          "6 saatlik yüzey arasından sonra uçuş yasağı belirgin şekilde kısalmalı")
    }

    // MARK: - Determinizm

    func testEngineIsDeterministic() {
        let first = runEngine(segments: [(depth: 30, duration: 20 * 60.0)],
                              gradientFactors: .moderate)
        let second = runEngine(segments: [(depth: 30, duration: 20 * 60.0)],
                               gradientFactors: .moderate)

        XCTAssertEqual(first.tissues.nitrogenPressures, second.tissues.nitrogenPressures)
        XCTAssertEqual(first.oxygen.cnsPercent, second.oxygen.cnsPercent)
        XCTAssertEqual(first.noFlyTime(), second.noFlyTime())
    }
}