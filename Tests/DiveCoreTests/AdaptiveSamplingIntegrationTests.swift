import XCTest
@testable import DiveCore

/// ADIM 11 — dinamik örneklemenin **oturum akışına** entegrasyonu.
///
/// Önemli güvenlik özelliği: örnekleme seyrekleşse bile dalışın sonucu
/// (GF99, tavan, dalış süresi) önemli ölçüde değişmemelidir; motor `dt`
/// üzerinden entegre ettiği için **kayıp yoktur**.
final class AdaptiveSamplingIntegrationTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func runDive(profile: PowerProfile) -> DiveState {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        var sampler = AdaptiveSampler(profile: profile, state: EnergyState(isDiving: true))
        for reading in DiveSimulator(scenario: .decompressionDive).readings {
            _ = controller.ingest(reading, sampler: &sampler)
        }
        return controller.state
    }

    @MainActor
    func testCoarseSamplingDoesNotLoseDiveTime() {
        // Aynı okuma dizisi, iki farklı profil: süre ve derinlik aynı kalmalı.
        let fast = runDive(profile: .performance)
        let slow = runDive(profile: .saver)

        XCTAssertEqual(fast.diveTime, slow.diveTime, accuracy: 2,
                       "Reddedilen okumalar motoru ilerletmez ama süre de kaybolmaz")
        XCTAssertEqual(fast.maxDepth, slow.maxDepth, accuracy: 0.5)
    }

    @MainActor
    func testCoarseSamplingKeepsGFClose() {
        let fast = runDive(profile: .performance)
        let slow = runDive(profile: .saver)
        XCTAssertEqual(fast.gf99, slow.gf99, accuracy: 12,
                       "Gaz yükü seyrekleşmeyle anlamlı biçimde değişmemeli")
    }

    @MainActor
    func testSafetyPhaseIsNeverCoarse() {
        // Deko yükümlülüğü başladıktan sonra her okuma işlenmeli.
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        var sampler = AdaptiveSampler(profile: .saver, state: EnergyState(isDiving: true))

        var processedWhileRising = 0
        var offeredWhileRising = 0
        for reading in DiveSimulator(scenario: .decompressionDive).readings {
            let obligated = controller.state.ceilingDepth > 0
            let rising = controller.state.ascentRate > 4
            if obligated, rising {
                offeredWhileRising += 1
                if controller.ingest(reading, sampler: &sampler) {
                    processedWhileRising += 1
                }
            } else {
                _ = controller.ingest(reading, sampler: &sampler)
            }
        }
        XCTAssertGreaterThan(offeredWhileRising, 0, "Senaryo deko üretmeliydi")
        XCTAssertEqual(processedWhileRising, offeredWhileRising,
                       "Deko yükümlülüğünde yükseliş sırasında hiçbir okuma atlanmamalı")
    }

    @MainActor
    func testFastAscentIsAlwaysSampled() {
        // 15 m/dk hızlı çıkış: her okuma işlenmeli.
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        var sampler = AdaptiveSampler(profile: .saver, state: EnergyState(isDiving: true))

        // Önce dibe in
        for reading in DiveSimulator(scenario: .recreational30m).readings
        where reading.depth < 20 {
            _ = controller.ingest(reading, sampler: &sampler)
        }

        var offered = 0
        var processed = 0
        var previous = 30.0
        var elapsed = controller.state.diveTime
        for _ in 0..<40 {
            elapsed += 1
            previous = max(0, previous - 15.0 / 60.0)   // 15 m/dk çıkış
            let reading = DepthReading(depth: previous,
                                       timestamp: base.addingTimeInterval(elapsed),
                                       elapsed: elapsed)
            offered += 1
            if controller.ingest(reading, sampler: &sampler) { processed += 1 }
        }
        XCTAssertGreaterThan(offered, 0)
        XCTAssertEqual(processed, offered, "Hızlı çıkışta hiçbir okuma atlanmamalı")
        XCTAssertGreaterThan(controller.state.ascentRate, 9,
                             "ascentRate pozitif = yukarı çıkış")
    }

    @MainActor
    func testSaversProcessesFewerReadings() {
        func processedCount(_ profile: PowerProfile) -> Int {
            let controller = DiveSessionController(configuration: .recreational)
            controller.start(at: base)
            var sampler = AdaptiveSampler(profile: profile, state: EnergyState(isDiving: true))
            var count = 0
            for reading in DiveSimulator(scenario: .recreational30m).readings {
                if controller.ingest(reading, sampler: &sampler) { count += 1 }
            }
            return count
        }
        let performance = processedCount(.performance)
        let saver = processedCount(.saver)
        XCTAssertLessThan(saver, performance, "Pil tasarrufu daha az işlem yapmalı")
    }
}
