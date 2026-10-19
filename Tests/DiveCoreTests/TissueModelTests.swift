import XCTest
@testable import DiveCore

/// ZH-L16C katsayıları, Schreiner denklemi ve tavan (ceiling) hesabı.
final class TissueModelTests: XCTestCase {

    // MARK: - Katsayılar

    func testSixteenCompartments() {
        XCTAssertEqual(TissueModel.compartmentCount, 16)
        XCTAssertEqual(TissueModel.halfTimes.count, 16)
        XCTAssertEqual(TissueModel.aCoefficients.count, 16)
        XCTAssertEqual(TissueModel.bCoefficients.count, 16)
    }

    /// Yarı ömürler **dakika** cinsinden ve monoton artmalıdır.
    func testPublishedZhl16cHalfTimes() {
        XCTAssertEqual(TissueModel.halfTimes.first, 4.0)     // dakika
        XCTAssertEqual(TissueModel.halfTimes.last, 635.0)
        XCTAssertEqual(TissueModel.halfTimes, TissueModel.halfTimes.sorted())
    }

    /// ZH-L16C "a" katsayıları (bar).
    func testPublishedZhl16cACoefficients() {
        XCTAssertEqual(TissueModel.aCoefficients[0], 1.1696, accuracy: 1e-9)
        XCTAssertEqual(TissueModel.aCoefficients[1], 1.0000, accuracy: 1e-9)
        XCTAssertEqual(TissueModel.aCoefficients[15], 0.2327, accuracy: 1e-9)
        XCTAssertEqual(TissueModel.aCoefficients, TissueModel.aCoefficients.sorted(by: >))
    }

    /// ZH-L16C "b" katsayıları (boyutsuz, 0 < b < 1, artan).
    func testPublishedZhl16cBCoefficients() {
        XCTAssertEqual(TissueModel.bCoefficients[0], 0.5578, accuracy: 1e-9)
        XCTAssertEqual(TissueModel.bCoefficients[15], 0.9653, accuracy: 1e-9)
        XCTAssertEqual(TissueModel.bCoefficients, TissueModel.bCoefficients.sorted())
        XCTAssertTrue(TissueModel.bCoefficients.allSatisfy { $0 > 0 && $0 < 1 })
    }

    /// M-değeri denklemi: `P_igtol = a + P_amb / b`
    func testMValueEquation() {
        // 1. bar'da 1. kompartman: 1.1696 + 1/0.5578 = 2.962
        XCTAssertEqual(TissueModel.mValue(compartment: 0, ambientPressure: 1.0), 2.962, accuracy: 0.005)
        // 4. kompartman, 1 bar: 0.7562 + 1/0.7825 = 2.034
        XCTAssertEqual(TissueModel.mValue(compartment: 3, ambientPressure: 1.0), 2.034, accuracy: 0.005)
        // 4 bar'da 16. kompartman: 0.2327 + 4/0.9653 = 4.377
        XCTAssertEqual(TissueModel.mValue(compartment: 15, ambientPressure: 4.0), 4.377, accuracy: 0.005)
    }

    // MARK: - Başlangıç durumu

    func testInitialStateIsSurfaceEquilibrium() {
        let model = TissueModel(gradientFactors: .default)
        let expected = TissueModel.surfaceNitrogenPressure()

        // Havada: (1.0 - 0.0627) * 0.79 = 0.7404 bar
        XCTAssertEqual(expected, 0.7404, accuracy: 1e-4)
        for index in 0..<16 {
            XCTAssertEqual(model[index], expected, accuracy: 1e-9,
                           "Kompartman \(index) yüzey dengesiyle başlamalı")
        }
    }

    func testNoCeilingOnSurfaceAtStart() {
        let model = TissueModel(gradientFactors: .conservative)
        XCTAssertEqual(model.ceiling(atDepth: 0).depthMeters, 0)
        XCTAssertFalse(model.ceiling(atDepth: 0).hasDecoObligation)
    }

    // MARK: - Schreiner denklemi

    func testSchreinerIsExactAtZeroTime() {
        let p = TissueModel.schreiner(initialTissuePressure: 1.2, inspiredPressure: 2.0,
                                      rate: 0.01, halfTimeSeconds: 600, time: 0)
        XCTAssertEqual(p, 1.2, accuracy: 1e-12)
    }

    /// Temel doku fiziği kuralı: bir yarı ömür sonunda dokunun, hedefe olan
    /// mesafesinin **yarısı** kapanmış olmalıdır.
    func testSchreinerHalvesDistanceInOneHalfTime() {
        let start = 1.0, inspired = 3.0, halfTime = 600.0

        let afterOne = TissueModel.schreiner(initialTissuePressure: start,
                                             inspiredPressure: inspired, rate: 0,
                                             halfTimeSeconds: halfTime, time: halfTime)
        XCTAssertEqual(afterOne, (start + inspired) / 2, accuracy: 1e-9)

        let afterTwo = TissueModel.schreiner(initialTissuePressure: start,
                                             inspiredPressure: inspired, rate: 0,
                                             halfTimeSeconds: halfTime, time: 2 * halfTime)
        XCTAssertEqual(afterTwo, start + (inspired - start) * 0.75, accuracy: 1e-9)
    }

    func testSchreinerConvergesAsymptotically() {
        var value = 1.0
        for _ in 0..<60 {   // 60 yarı ömür
            value = TissueModel.schreiner(initialTissuePressure: value, inspiredPressure: 3.0,
                                          rate: 0, halfTimeSeconds: 600, time: 600)
        }
        XCTAssertEqual(value, 3.0, accuracy: 1e-6)
    }

    /// Hızlı değişimlerde sayısal kararlılık: tek büyük adım, aynı süredeki
    /// 60 adımlık bölünmüş hesapla (doğrusal solunan basınç artışıyla) örtüşmeli.
    func testSchreinerLargeStepMatchesManySmallSteps() {
        let rate = 0.02          // bar/s
        let big = TissueModel.schreiner(initialTissuePressure: 0.8, inspiredPressure: 1.0,
                                        rate: rate, halfTimeSeconds: 600, time: 60)

        var small = 0.8
        for step in 0..<60 {
            let inspiredNow = 1.0 + rate * Double(step)
            small = TissueModel.schreiner(initialTissuePressure: small,
                                          inspiredPressure: inspiredNow,
                                          rate: rate, halfTimeSeconds: 600, time: 1)
        }
        XCTAssertEqual(big, small, accuracy: 0.02)
    }

    // MARK: - Adımlama

    func testConstantDepthConvergesToAlveolarNitrogen() {
        var model = TissueModel(gradientFactors: .default)
        let depth = 30.0
        model.step(atDepth: depth, duration: 3600, gas: .air)

        let expected = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: DivePhysics.ambientPressure(depthMeters: depth),
            nitrogenFraction: GasMix.air.nitrogenFraction)

        // 4 dk yarı ömrlü 1. kompartman 1 saatte tamamen dengeye ulaşır.
        XCTAssertEqual(model[0], expected, accuracy: 0.001)
        // 27 dk yarı ömrlü 5. kompartman 2.2 yarı ömür = ~%77 dolu
        let expected5 = DivePhysics.alveolarNitrogenPressure(
            ambientPressure: DivePhysics.ambientPressure(depthMeters: depth),
            nitrogenFraction: GasMix.air.nitrogenFraction)
        let filled = 1 - pow(2, -3600.0 / (27.0 * 60))   // 3600 sn / 1620 sn = 2.22 yarı ömür
        XCTAssertEqual(model[4], TissueModel.surfaceNitrogenPressure()
                       + (expected5 - TissueModel.surfaceNitrogenPressure()) * filled,
                       accuracy: 0.01)
        // 635 dk yarı ömrlü 16. kompartman henüz uzaktır
        XCTAssertLessThan(model[15], expected5)
        XCTAssertGreaterThan(model[15], TissueModel.surfaceNitrogenPressure())
    }

    func testFastCompartmentsLoadFasterThanSlowOnes() {
        var model = TissueModel(gradientFactors: .default)
        let surface = TissueModel.surfaceNitrogenPressure()
        model.step(atDepth: 40, duration: 300, gas: .air)

        XCTAssertGreaterThan(model[0] - surface, model[15] - surface)
    }

    /// Hızlı iniş/çıkışlarda küçük adımlar kullanılmalıdır (uygulamada 1-4 sn).
    ///
    /// Schreiner denklemi sabit hızlı solunan basınç değişimi varsayar; hızlı
    /// inişlerde hızlı kompartmanlar dengeye ulaşmadan "gecikmeli" kalır.
    func testDescentDwellAndAscent() {
        var model = TissueModel(gradientFactors: .default)

        // 1) 0 -> 30 m, 3 dakikada (10 m/dk)
        for step in 1...18 {
            model.step(fromDepth: Double(step - 1) * (30.0 / 18.0),
                       toDepth: Double(step) * (30.0 / 18.0),
                       duration: 10, gas: .air)
        }
        // Hızlı kompartman yüklenmiştir ama gecikme nedeniyle dengeyi tam
        // yakalayamamıştır (Schreiner'in hız bağımlı gecikmesi).
        XCTAssertGreaterThan(model[0], TissueModel.surfaceNitrogenPressure())
        XCTAssertLessThan(model[0], DivePhysics.alveolarNitrogenPressure(
            ambientPressure: 4.0, nitrogenFraction: 0.79))

        // 2) 20 dakika dibte
        model.step(atDepth: 30, duration: 20 * 60, gas: .air)
        // 5 yarı ömür sonra hızlı kompartman dengeye çok yakındır
        XCTAssertGreaterThan(model[0], 3.0)
        XCTAssertLessThan(model[0], 3.1104)
        // 635 dk yarı ömrlü kompartman 23 dakikada henüz çok az yüklenir
        XCTAssertLessThan(model[15], 1.0)

        // 3) 30 m -> 0 m, 10 dakikada yavaş çıkış (3 m/dk)
        for step in 1...60 {
            model.step(fromDepth: 30.0 - Double(step - 1) * 0.5,
                       toDepth: 30.0 - Double(step) * 0.5,
                       duration: 10, gas: .air)
        }
        let afterAscent = model.nitrogenPressures

        // 4) Yüzeyde 10 dakika: tüm dokular boşalır
        model.step(atDepth: 0, duration: 600, gas: .air)
        for index in 0..<16 {
            XCTAssertLessThan(model[index], afterAscent[index],
                              "Kompartman \(index) yüzey aralığında boşalmalı")
        }
        // Hızlı kompartmanlar neredeyse tamamen temizlenir
        XCTAssertLessThan(model[0], 1.0)
        // Orta/yavaş dokular 10 dakikalık yüzey aralığında hâlâ yüklüdür
        XCTAssertGreaterThan(model[4], 1.0)
        XCTAssertGreaterThan(model[15], TissueModel.surfaceNitrogenPressure())
    }

    func testElapsedAndMaxDepthTracking() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 10, duration: 60, gas: .air)
        model.step(atDepth: 24, duration: 30, gas: .air)
        XCTAssertEqual(model.elapsed, 90)
        XCTAssertEqual(model.maxDepth, 24)
    }

    func testZeroDurationIsNoOp() {
        var model = TissueModel(gradientFactors: .default)
        let before = model.nitrogenPressures
        model.step(atDepth: 30, duration: 0, gas: .air)
        XCTAssertEqual(model.nitrogenPressures, before)
    }

    func testResetReturnsToSurfaceEquilibrium() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 40, duration: 600, gas: .ean32)
        model.reset()

        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(model.maxDepth, 0)
        XCTAssertEqual(model.nitrogenPressures,
                       Array(repeating: TissueModel.surfaceNitrogenPressure(), count: 16))
    }

    // MARK: - Tolerans ve tavan

    /// GF 100'de toleranslanan ambient basıncı `(P − a)·b` olmalıdır.
    func testToleratedAmbientPressureAtFullGradient() {
        let expected = (2.0 - TissueModel.aCoefficients[5]) * TissueModel.bCoefficients[5]
        XCTAssertEqual(TissueModel.toleratedAmbientPressure(tissueNitrogen: 2.0,
                                                           compartment: 5, gf: 1.0),
                       expected, accuracy: 1e-12)
    }

    func testLowerGradientFactorRaisesToleratedPressure() {
        let loose = TissueModel.toleratedAmbientPressure(tissueNitrogen: 2.5, compartment: 10, gf: 1.0)
        let tight = TissueModel.toleratedAmbientPressure(tissueNitrogen: 2.5, compartment: 10, gf: 0.5)
        XCTAssertGreaterThan(tight, loose, "Daha düşük GF daha yüksek tavan = daha muhafazakâr")
    }

    func testLowerGradientFactorRaisesCeiling() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 30, duration: 25 * 60, gas: .air)

        let loose = model.ceilingDepth(atDepth: 30, gf: 1.0)
        let tight = model.ceilingDepth(atDepth: 30, gf: 0.3)
        XCTAssertGreaterThan(tight, loose)
    }

    func testCeilingNeverNegative() {
        let model = TissueModel(gradientFactors: .conservative)
        let ceiling = model.ceiling(atDepth: 0)
        XCTAssertGreaterThanOrEqual(ceiling.depthMeters, 0)
    }

    func testCeilingRoundsDownToThreeMeterStops() {
        XCTAssertEqual(TissueModel.roundToStopInterval(5.9), 3.0)
        XCTAssertEqual(TissueModel.roundToStopInterval(11.7), 9.0)
        XCTAssertEqual(TissueModel.roundToStopInterval(2.9), 0.0)
        XCTAssertEqual(TissueModel.roundToStopInterval(0), 0.0)
    }

    func testNoCeilingOnShortShallowDive() {
        var model = TissueModel(gradientFactors: .conservative)
        model.step(fromDepth: 0, toDepth: 12, duration: 60, gas: .air)
        model.step(atDepth: 12, duration: 10 * 60, gas: .air)

        XCTAssertEqual(model.ceiling(atDepth: 12).depthMeters, 0, accuracy: 0.001)
    }

    /// 30 m'de 25 dakika hava dalışı: GF 100'de küçük, GF 30'da belirgin tavan.
    func testCeilingOnOverlongDeepDive() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 30, duration: 25 * 60, gas: .air)

        let loose = model.ceiling(atDepth: 30).depthMeters
        XCTAssertGreaterThan(loose, 0, "30 m / 25 dk hava GF100'de tavan oluşturmalı")
        XCTAssertLessThan(loose, 12, "GF 100'de tavan sığ olmalı")

        let tight = model.ceilingDepth(atDepth: 30, gf: 0.3)
        XCTAssertGreaterThan(tight, loose)
        XCTAssertLessThanOrEqual(tight, 30)
    }

    func testNextStopDepthOnlyWhenDecoRequired() {
        var model = TissueModel(gradientFactors: .conservative)
        model.step(atDepth: 12, duration: 10 * 60, gas: .air)
        XCTAssertNil(model.nextStopDepth(atDepth: 12))

        model.step(atDepth: 30, duration: 40 * 60, gas: .air)
        let stop = model.nextStopDepth(atDepth: 30)
        XCTAssertNotNil(stop)
        XCTAssertGreaterThan(stop!, 0)
        XCTAssertEqual(stop!.truncatingRemainder(dividingBy: DiveSafetyLimits.decoStopInterval), 0, accuracy: 1e-9)
    }

    // MARK: - GF99

    func testGF99IsZeroAtSurfaceAtStart() {
        let model = TissueModel(gradientFactors: .default)
        XCTAssertEqual(model.gf99(atDepth: 0), 0, accuracy: 1e-6)
    }

    func testGF99GrowsWithDepthAndTime() {
        var shallow = TissueModel(gradientFactors: .default)
        shallow.step(atDepth: 12, duration: 20 * 60, gas: .air)

        var deep = TissueModel(gradientFactors: .default)
        deep.step(atDepth: 30, duration: 20 * 60, gas: .air)

        XCTAssertGreaterThan(deep.gf99(atDepth: 30), shallow.gf99(atDepth: 12))
        XCTAssertGreaterThan(shallow.gf99(atDepth: 12), 0)
    }

    /// 18 m'de 45 dakika hava dalışında GF99 makul aralıkta olmalıdır.
    func testGF99IsInRealisticRangeForRecreationalDive() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 18, duration: 45 * 60, gas: .air)

        let gf99 = model.gf99(atDepth: 18)
        XCTAssertGreaterThan(gf99, 50)
        XCTAssertLessThan(gf99, 150, "18 m / 45 dk hava GF99 tipik olarak %60-110 aralığındadır")
    }

    func testGF99DecreasesOnSurfaceInterval() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 30, duration: 25 * 60, gas: .air)
        let before = model.gf99(atDepth: 0)

        model.step(atDepth: 0, duration: 6 * 3600, gas: .air)
        XCTAssertLessThan(model.gf99(atDepth: 0), before)
    }

    // MARK: - Desatürasyon

    func testDesaturationTimeIsMinimalWhenAlreadyClean() {
        let model = TissueModel(gradientFactors: .default)
        XCTAssertLessThanOrEqual(model.desaturationTime(gas: .air, gf: 1.0), 10)
    }

    func testDesaturationTimeGrowsWithDepth() {
        var shallow = TissueModel(gradientFactors: .default)
        shallow.step(atDepth: 20, duration: 30 * 60, gas: .air)

        var deep = TissueModel(gradientFactors: .default)
        deep.step(atDepth: 50, duration: 40 * 60, gas: .air)

        XCTAssertGreaterThan(deep.desaturationTime(), shallow.desaturationTime())
        XCTAssertGreaterThan(deep.desaturationTime(), 900)
    }

    /// Uzun bir derin dalıştan sonra **en fazla dolu** kompartman hızlı olanlardır
    /// (yavaşlar henüz dolmamıştır). Tavanı belirleyen "leading tissue" ile aynı
    /// şey değildir; o, toleransı en yüksek olan kompartmandır.
    func testMostLoadedCompartmentIsAFastOneAfterLongExposure() {
        var model = TissueModel(gradientFactors: .default)
        model.step(atDepth: 60, duration: 3600, gas: .air)
        XCTAssertLessThan(model.leadingCompartmentHalfTime, 60.0)
    }

    // MARK: - GF interpolasyonu

    func testGradientFactorInterpolationBetweenHighAndLow() {
        var model = TissueModel(gradientFactors: GradientFactors(low: 30, high: 70))
        model.step(atDepth: 30, duration: 60 * 60, gas: .air)   // tavan oluşturur

        let deepest = model.deepestCeilingPressure
        XCTAssertGreaterThan(deepest, DivePhysics.surfacePressure)

        // En derin tavan basıncında GF Low, yüzeyde GF High geçerli
        XCTAssertEqual(model.gradientFactor(atPressure: deepest), 0.30, accuracy: 1e-9)
        XCTAssertEqual(model.gradientFactor(atPressure: DivePhysics.surfacePressure), 0.70, accuracy: 1e-9)

        // Ara değerler lineer
        let middle = (DivePhysics.surfacePressure + deepest) / 2
        XCTAssertEqual(model.gradientFactor(atPressure: middle), 0.50, accuracy: 1e-9)
    }

    func testGradientFactorEqualsLowWhenNoCeilingYet() {
        let model = TissueModel(gradientFactors: GradientFactors(low: 30, high: 70))
        // Henüz tavan yok → GF Low uygulanır (Subsurface davranışı)
        XCTAssertEqual(model.gradientFactor(atPressure: 4.0), 0.30, accuracy: 1e-9)
    }

    // MARK: - Kodlama

    func testCodableRoundTrip() throws {
        var model = TissueModel(gradientFactors: .moderate, water: .fresh)
        model.step(atDepth: 20, duration: 300, gas: .ean32)

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(TissueModel.self, from: data)
        XCTAssertEqual(decoded.nitrogenPressures, model.nitrogenPressures)
        XCTAssertEqual(decoded.gradientFactors, model.gradientFactors)
        XCTAssertEqual(decoded.water, model.water)
    }
}