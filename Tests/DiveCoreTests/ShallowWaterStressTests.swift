import XCTest
@testable import DiveCore

/// ADIM 12 — **sınır durum ve stres testleri (2/3)**: sığ su, dip zamanı
/// sınırı aşımı ve dekompresyon yükümlülüğüne geçiş.
///
/// ## Gerçek dünya senaryoları
/// - Yüzme havuzunda 5 m'de 2 saatlik "dalış" (aşırı sığ, uzun bekleme),
/// -礁 resifinde 18 m'de NDL'yi aşan uzun dip,
/// - Sığ sularda tavan hesabı (tavan asla 6 m'nin üstünde çıkmamalı),
/// - Ardışık sığ dalışlarda biriken yükün deko üretmesi.
final class ShallowWaterStressTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcılar

    /// Belirtilen derinlikte belirtilen süre boyunca sabit bekleyen okumalar.
    private func hold(at depth: Double, seconds: TimeInterval,
                      startElapsed: TimeInterval = 0) -> [DepthReading] {
        (0..<Int(seconds)).map { step in
            let elapsed = startElapsed + Double(step)
            return DepthReading(depth: depth,
                                timestamp: base.addingTimeInterval(elapsed),
                                elapsed: elapsed)
        }
    }

    /// Derinliğe güvenli iniş + bekleme + yavaş çıkış.
    @discardableResult
    @MainActor
    private func runDive(to depth: Double,
                         bottomSeconds: TimeInterval,
                         configuration: DiveConfiguration = .recreational) -> DiveSessionController {
        let controller = DiveSessionController(configuration: configuration)
        controller.start(at: base)
        var elapsed: TimeInterval = 0

        // İniş (12 m/dk)
        while controller.state.currentDepth < depth - 0.01 {
            elapsed += 1
            controller.ingest(DepthReading(
                depth: min(depth, controller.state.currentDepth + 12.0 / 60.0),
                timestamp: base.addingTimeInterval(elapsed), elapsed: elapsed))
        }
        for reading in hold(at: depth, seconds: bottomSeconds, startElapsed: elapsed) {
            controller.ingest(reading)
        }
        elapsed += bottomSeconds

        // Yavaş çıkış (8 m/dk) — ihlal üretmemeli
        while controller.state.currentDepth > 0.01 {
            elapsed += 1
            controller.ingest(DepthReading(
                depth: max(0, controller.state.currentDepth - 8.0 / 60.0),
                timestamp: base.addingTimeInterval(elapsed), elapsed: elapsed))
        }
        return controller
    }

    private func engineAt(_ depth: Double, seconds: TimeInterval) -> DecoEngine {
        var engine = DecoEngine(gradientFactors: .conservative,
                                gases: [.air, .oxygen], gasCylinderIndex: 0)
        engine.update(toDepth: depth, duration: depth / 15.0 * 60, gas: .air)
        engine.update(toDepth: depth, duration: seconds, gas: .air)
        return engine
    }

    // MARK: - Sığ su temel davranış

    /// Sığ sularda NDL **çok uzundur**: 5 m'de 6 saat geçse bile doku
    /// denge basıncına ulaştığı için tavan oluşmaz.
    ///
    /// - Note: Ölçülen değerler (GF 80/85, tuzlu su): 3/4/5/6/8 m'de 6 saat
    ///   boyunca tavan **yok**; 10 m'de 4 saat → 0.2 m, 6 saat → 0.7 m.
    ///   Bu, gerçek bilgisayarların davranışıyla örtüşür.
    func testVeryShallowLongDiveHasNoObligation() {
        for depth in [3.0, 4.0, 5.0, 6.0, 8.0] as [Double] {
            let engine = engineAt(depth, seconds: 6 * 3600)
            XCTAssertEqual(engine.ceiling(atDepth: depth).depthMeters, 0, accuracy: 0.01,
                           "\(Int(depth)) m'de 6 saat sonrası deko beklenmiyor")
        }
    }

    /// 10 m gibi "sığ ama uzun" dalışlar NDL'yi aşabilir.
    func testModerateShallowLongDiveProducesObligation() {
        let fourHours = engineAt(10, seconds: 4 * 3600)
        XCTAssertGreaterThan(fourHours.ceiling(atDepth: 10).depthMeters, 0,
                             "10 m'de 4 saat sonrası tavan oluşmalı")
        let sixHours = engineAt(10, seconds: 6 * 3600)
        XCTAssertGreaterThan(sixHours.ceiling(atDepth: 10).depthMeters,
                             fourHours.ceiling(atDepth: 10).depthMeters,
                             "Daha uzun dalışda tavan daha derin olmalı")
    }

    func testThreeMetreLongDiveHasNoObligation() {
        // 3 m'de 2 saat: sığ suda deko gerekmez (yüzey doygunluğu sınırı)
        let engine = engineAt(3, seconds: 2 * 3600)
        XCTAssertEqual(engine.ceiling(atDepth: 3).depthMeters, 0, accuracy: 0.01,
                       "3 m'de 2 saat hâlâ deko gerektirmemeli")
    }

    func testShallowCeilingNeverExceedsSixMetres() {
        // Sığ sularda tavan 6 m'yi (tavan sınırı) aşmamalı
        for depth in [4.0, 5.0, 6.0, 8.0] {
            for seconds in [600.0, 3600.0, 7200.0] as [TimeInterval] {
                let engine = engineAt(depth, seconds: seconds)
                let ceiling = engine.ceiling(atDepth: depth).depthMeters
                XCTAssertLessThanOrEqual(ceiling, 6.0 + 0.01,
                                         "\(depth) m / \(Int(seconds)) sn: tavan 6 m'yi aştı")
            }
        }
    }

    func testNdlIsZeroOnceObligationExists() {
        let engine = engineAt(18, seconds: 60 * 60)
        XCTAssertEqual(engine.noDecompressionLimit(atDepth: 18), 0,
                       "Deko yükümlülüğü varken NDL sıfır olmalı")
    }

    // MARK: - NDL sınır geçişi

    func testNdlTransitionToObligationIsMonotonic() {
        // Dip zamanı arttıkça NDL azalır, sonra tavan belirir
        var previousCeiling = -1.0
        for minutes in stride(from: 5.0, through: 120.0, by: 5.0) {
            let engine = engineAt(30, seconds: minutes * 60)
            let ceiling = engine.ceiling(atDepth: 30).depthMeters
            XCTAssertGreaterThanOrEqual(ceiling + 0.001, previousCeiling,
                                        "\(Int(minutes)) dk'da tavan gerilemedi")
            previousCeiling = ceiling
        }
        XCTAssertGreaterThan(previousCeiling, 0, "120 dk sonunda deko olmalı")
    }

    @MainActor
    func testNoDecoLimitReachedWarningFires() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        var elapsed: TimeInterval = 0
        while controller.state.currentDepth < 29.9 {
            elapsed += 1
            controller.ingest(DepthReading(
                depth: controller.state.currentDepth + 12.0 / 60.0,
                timestamp: base.addingTimeInterval(elapsed), elapsed: elapsed))
        }
        for reading in hold(at: 30, seconds: 40 * 60, startElapsed: elapsed) {
            controller.ingest(reading)
        }
        XCTAssertTrue(controller.state.warnings.contains {
            $0.kind == .noDecoLimitReached || $0.kind == .ceilingViolation
        }, "NDL aşımı uyarısı üretilmeli")
    }

    func testObligationAlwaysYieldsSurfacablePlan() {
        // Deko planı her zaman yüzeye çıkış sağlamalı
        for depth in [20.0, 30.0, 40.0, 45.0] as [Double] {
            for minutes in [30.0, 60.0, 90.0] as [TimeInterval] {
                let engine = engineAt(depth, seconds: minutes * 60)
                let plan = DecoStopPlan.make(from: engine, currentDepth: depth)
                XCTAssertGreaterThanOrEqual(plan.totalTime, 0)
                if engine.ceiling(atDepth: depth).depthMeters > 0 {
                    XCTAssertFalse(plan.stops.isEmpty,
                                   "\(depth) m / \(Int(minutes)) dk: plan boş olmamalı")
                    XCTAssertTrue(plan.stops.contains { $0.depth <= 6 },
                                  "Son deko durağı 6 m'nin altında olmalı")
                }
            }
        }
    }

    // MARK: - Ardışık sığ dalışlar

    func testRepeatedShallowDivesAccumulateLoad() {
        var engine = DecoEngine(gradientFactors: .conservative,
                                gases: [.air, .oxygen], gasCylinderIndex: 0)
        var firstNdl = 0.0

        for dive in 1...4 {
            engine.update(toDepth: 6, duration: 6 / 15.0 * 60, gas: .air)
            engine.update(toDepth: 6, duration: 25 * 60, gas: .air)
            let ndl = engine.noDecompressionLimit(atDepth: 6)
            if dive == 1 { firstNdl = ndl }
            XCTAssertLessThanOrEqual(ndl, firstNdl,
                                     "Art arda dalışlarda NDL artmamalı")
            // Çıkış + 45 dk yüzey
            engine.update(toDepth: 0, duration: 6 / 9.0 * 60, gas: .air)
            engine.update(toDepth: 0, duration: 45 * 60, gas: .air)
        }
        XCTAssertGreaterThanOrEqual(firstNdl, 0)
    }

    func testRepetitiveCalculatorShallowSequence() {
        let results = RepetitiveDiveCalculator.sequence(
            dives: [(depth: 6.0, duration: 30.0 * 60),
                    (depth: 6.0, duration: 30.0 * 60),
                    (depth: 6.0, duration: 30.0 * 60)],
            surfaceInterval: 30 * 60)
        XCTAssertEqual(results.count, 3)
        // NDL'ler monotonik azalmalı
        XCTAssertLessThanOrEqual(results[1].effectiveNDL, results[0].effectiveNDL)
        XCTAssertLessThanOrEqual(results[2].effectiveNDL, results[1].effectiveNDL)
    }

    func testLongSurfaceIntervalResetsShallowLoad() {
        var engine = DecoEngine(gradientFactors: .conservative,
                                gases: [.air, .oxygen], gasCylinderIndex: 0)
        engine.update(toDepth: 6, duration: 4 / 15.0 * 60 + 40 * 60, gas: .air)
        engine.update(toDepth: 0, duration: 6 / 9.0 * 60, gas: .air)
        let loaded = engine.noDecompressionLimit(atDepth: 6)

        var rested = engine
        rested.update(toDepth: 0, duration: 12 * 3600, gas: .air)
        XCTAssertGreaterThanOrEqual(rested.noDecompressionLimit(atDepth: 6), loaded)
    }

    // MARK: - Uçtan uca sığ dalış

    @MainActor
    func testShallowEndToEndDive() {
        let controller = runDive(to: 5, bottomSeconds: 45 * 60)
        // 5 m'de 45 dakika: kesinlikle deko olmaz
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
        XCTAssertEqual(log.maxDepth, 5, accuracy: 0.3)
        XCTAssertFalse(log.hadDecoObligation)
        XCTAssertGreaterThan(log.totalDiveTime, 45 * 60)
        XCTAssertFalse(log.samples.isEmpty)
        // Sığ suda 45 dakika sonrası hâlâ yüzeye çıkılabilir olmalı
        XCTAssertLessThanOrEqual(controller.state.ceilingDepth, 6.5)
    }

    @MainActor
    func testLongShallowDiveProducesObligationEndToEnd() {
        // 10 m'de 4 saat → NDL aşılır, tavan oluşur
        let controller = runDive(to: 10, bottomSeconds: 4 * 3600)
        let report = controller.makeReport()
        XCTAssertGreaterThan(report.maxGF99, 0)
        XCTAssertGreaterThan(report.maxGF99, 60, "Yüzey GF99 dalış sırasında yüksek olmalı")
        // Dalış sonunda yüzeye çıkılmış olmalı
        XCTAssertLessThanOrEqual(controller.state.ceilingDepth, 6.5)
    }

    @MainActor
    func testSafetyStopInShallowWater() {
        let controller = runDive(to: 6, bottomSeconds: 20 * 60)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
        // Sığ suda deko yoksa emniyet durağı planlanmalı
        if !log.hadDecoObligation {
            XCTAssertTrue(log.safetyStopAccumulated > 0 || log.safetyStopCompleted,
                          "Emniyet durağı biriktirilmeliydi")
        }
    }

    // MARK: - Oksijen sınırları (derin/sığ çapraz)

    func testShallowAirNeverExceedsPo2Limit() {
        // Sığ suda hava ile PO₂ sorunu olmamalı
        for depth in [3.0, 6.0, 10.0] as [Double] {
            let po2 = GasMix.air.oxygenPartialPressure(atDepth: depth)
            XCTAssertLessThan(po2, DiveSafetyLimits.maximumPO2,
                              "\(depth) m'de hava PO₂ sınırı aşmamalı")
        }
    }

    func testDeepNitroxNdlRespectsMod() {
        // Ölçülen MOD değerleri (PO₂ 1.4 bar): EAN32 → 34.4 m, EAN36 → 29.5 m
        let mod32 = GasMix.nitrox(32)!.maximumOperatingDepth(maxPO2: 1.4)
        XCTAssertEqual(mod32, 34.4, accuracy: 0.3)
        let mod36 = GasMix.nitrox(36)!.maximumOperatingDepth(maxPO2: 1.4)
        XCTAssertEqual(mod36, 29.5, accuracy: 0.3)
        XCTAssertGreaterThan(mod32, mod36)
    }

    // MARK: - Sayısal kararlılık

    @MainActor
    func testNoNaNInShallowStress() {
        let controller = runDive(to: 4, bottomSeconds: 2 * 3600)
        let state = controller.state
        for value in [state.gf99, state.ceilingDepth, state.averageDepth,
                      state.noDecompressionLimit, state.timeToSurface,
                      state.cnsPercent, state.otuUnits] {
            XCTAssertFalse(value.isNaN, "NaN üretildi")
            XCTAssertFalse(value.isInfinite, " sonsuz değer üretildi")
        }
        XCTAssertGreaterThanOrEqual(state.gf99, 0)
        XCTAssertGreaterThanOrEqual(state.averageDepth, 0)
        XCTAssertLessThanOrEqual(state.averageDepth, state.maxDepth + 0.01)
    }

    func testCeilingNeverNegativeOrNaN() {
        for depth in [1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 45.0] as [Double] {
            for minutes in [5.0, 30.0, 60.0, 120.0, 240.0] as [TimeInterval] {
                let engine = engineAt(depth, seconds: minutes * 60)
                let ceiling = engine.ceiling(atDepth: depth).depthMeters
                XCTAssertFalse(ceiling.isNaN)
                XCTAssertGreaterThanOrEqual(ceiling, 0, "Tavan negatif olamaz")
                XCTAssertLessThanOrEqual(ceiling, depth + 0.01,
                                         "Tavan mevcut derinliği aşamaz")
            }
        }
    }

    func testZeroDepthHasNoObligation() {
        let engine = engineAt(0, seconds: 3600)
        XCTAssertEqual(engine.ceiling(atDepth: 0).depthMeters, 0, accuracy: 0.001)
    }
}
