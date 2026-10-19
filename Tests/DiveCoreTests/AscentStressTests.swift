import XCTest
@testable import DiveCore

/// ADIM 12 — **sınır durum ve stres testleri (1/3)**: hız, aşırı çıkış,
/// sensör arızası ve alarm doğruluğu.
///
/// ## Neden ayrı bir dosya?
/// Bu testler "mutlu yol" değil, **kötü yol** testleridir: kullanıcı hatası,
/// sensör arızası, zaman sıçraması ve ani derinlik sıçraması gibi gerçek
/// dalışlarda görülen durumlar. Amaç, sistemin bunlarda **güvenli** davranmasını
/// kanıtlamaktır (yanlış alarm yok, kaçırılan alarm yok, çökme yok).
final class AscentStressTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcılar

    /// Belirtilen hızda (m/dk) yükselen okuma dizisi üretir.
    private func ascentReadings(from startDepth: Double = 30,
                                to endDepth: Double = 0,
                                rate: Double,
                                step: TimeInterval = 1,
                                startElapsed: TimeInterval = 0) -> [DepthReading] {
        var readings: [DepthReading] = []
        var depth = startDepth
        var elapsed = startElapsed
        let perSecond = rate / 60.0

        // Hedef derinliğe ulaşana kadar ilerle (yön `endDepth` ile belirlenir)
        let descending = endDepth > startDepth
        while descending ? (depth < endDepth) : (depth > endDepth) {
            let next = descending
                ? min(endDepth, depth + perSecond * step)
                : max(endDepth, depth - perSecond * step)
            readings.append(DepthReading(depth: next,
                                         timestamp: base.addingTimeInterval(elapsed),
                                         elapsed: elapsed))
            depth = next
            elapsed += step
        }
        return readings
    }

    private func runMonitor(_ readings: [DepthReading],
                            limit: Double = DiveSafetyLimits.maximumAscentRate)
        -> (monitor: AscentRateMonitor, updates: [AscentRateUpdate]) {
        var monitor = AscentRateMonitor(limit: limit)
        let updates = readings.map { monitor.update(with: $0) }
        return (monitor, updates)
    }

    // MARK: - Temel hız doğruluğu

    func testSmoothedRateMatchesPhysicalRate() {
        let readings = ascentReadings(rate: 10)
        let (_, updates) = runMonitor(readings)
        // Yumuşatma (α=0.25) sonrası yaklaşık değer
        let last = updates.last!.smoothedRate
        XCTAssertEqual(last, 10, accuracy: 0.5)
    }

    func testAscentRateSignIsUpward() {
        // Yukarı çıkış (+) pozitif olmalı
        let ascending = runMonitor(ascentReadings(rate: 8)).updates.last!.smoothedRate
        XCTAssertGreaterThan(ascending, 0)
        // Aşağı iniş (−) negatif olmalı
        let descending = runMonitor(ascentReadings(from: 0, to: 30, rate: 8))
            .updates.last!.smoothedRate
        XCTAssertLessThan(descending, 0)
    }

    func testDescentNeverTriggersAscentViolation() {
        // 30 m'ye 40 m/dk ile inmek hızlı iniştir, hızlı çıkış DEĞİLDİR
        let readings = ascentReadings(from: 0, to: 40, rate: 40)
        let (_, updates) = runMonitor(readings, limit: 10)
        XCTAssertFalse(updates.contains { $0.exceededLimit },
                       "Hızlı iniş çıkış ihlali üretmemeli")
        XCTAssertFalse(updates.contains { $0.alarmDue })
    }

    // MARK: - Aşırı hızlı çıkış

    func testExtremeAscentTriggersViolation() {
        // 20 m/dk — sınırın iki katı
        let readings = ascentReadings(rate: 20)
        let (_, updates) = runMonitor(readings, limit: 10)
        XCTAssertTrue(updates.contains { $0.exceededLimit })
        XCTAssertTrue(updates.contains { $0.alarmDue })
    }

    func testViolationRequiresSustainedDuration() {
        // Tek bir 20 m/dk ölçümü yeterli değil: `violationHoldTime` (4 sn)
        // boyunca **sürekli** aşılmalıdır.
        let monitor = AscentRateMonitor(limit: 10)
        let readings = ascentReadings(rate: 20, step: 0.2)
        var updates: [AscentRateUpdate] = []
        var scratch = monitor
        for reading in readings { updates.append(scratch.update(with: reading)) }

        let firstViolation = updates.first { $0.exceededLimit }
        guard let firstViolation else {
            return XCTFail("Sürdürülen ihlal bir noktada alarm vermeli")
        }
        XCTAssertEqual(firstViolation.violationDuration,
                       monitor.violationHoldTime, accuracy: 0.25,
                       "İhlal ancak eşik tutturulduğunda bildirilir")
        XCTAssertFalse(updates.first?.alarmDue ?? true, "İlk okamada alarm olmamalı")
    }

    func testSingleSpikeDoesNotTriggerAlarm() {
        // Derinlik 30 → 20 → 30: tek örneklik 10 m sıçrama yumuşatılmalı
        var readings = ascentReadings(from: 30, to: 20, rate: 3)
        let spikeDepth = 20.0
        var elapsed = readings.last?.elapsed ?? 0
        readings.append(DepthReading(depth: spikeDepth - 10,
                                     timestamp: base.addingTimeInterval(elapsed),
                                     elapsed: elapsed))
        elapsed += 1
        readings.append(DepthReading(depth: spikeDepth,
                                     timestamp: base.addingTimeInterval(elapsed),
                                     elapsed: elapsed))
        let (_, updates) = runMonitor(readings, limit: 10)
        XCTAssertFalse(updates.contains { $0.alarmDue },
                       "Tek örneklik derinlik sıçraması alarm üretmemeli")
    }

    func testAlarmRespectsCooldown() {
        let readings = ascentReadings(rate: 20)
        let (_, updates) = runMonitor(readings, limit: 10)
        let alarms = updates.filter { $0.alarmDue }
        // Alarm cooldown = 60 sn; 30 m'lik çıkış ~90 sn sürer
        for (index, alarm) in alarms.enumerated() where index > 0 {
            let previous = alarms[index - 1]
            XCTAssertGreaterThanOrEqual(alarm.reading.elapsed - previous.reading.elapsed,
                                        AscentRateMonitor().alarmCooldown - 0.1,
                                        "Alarmlar cooldown aralığına uymalı")
        }
    }

    func testViolationResetsWhenRateDrops() {
        var readings = ascentReadings(from: 30, to: 20, rate: 20)
        var elapsed = readings.last?.elapsed ?? 0
        // Yavaş çıkış
        let slow = ascentReadings(from: 20, to: 10, rate: 4, startElapsed: elapsed)
        readings += slow
        let (_, updates) = runMonitor(readings, limit: 10)
        // Son okumalarda ihlal süresi sıfırlanmış olmalı
        XCTAssertEqual(updates.last?.violationDuration ?? -1, 0, accuracy: 0.1)
    }

    func testTotalsAccumulate() {
        let readings = ascentReadings(from: 30, to: 5, rate: 5)
        let (monitor, _) = runMonitor(readings)
        XCTAssertEqual(monitor.totalAscent, 25, accuracy: 0.5)
        XCTAssertEqual(monitor.totalDescent, 0, accuracy: 0.01)
    }

    // MARK: - Sensör arızaları

    func testSurfaceReadingsAreNotRateMeasured() {
        // Yüzeyde hız hesabı anlamsızdır (dalgalanma)
        let readings = ascentReadings(from: 0.1, to: 0, rate: 30)
        let (_, updates) = runMonitor(readings, limit: 10)
        XCTAssertFalse(updates.contains { $0.exceededLimit })
    }

    func testAbsurdRateIsRejected() {
        // |hız| > 60 m/dk fiziksel olarak imkânsızdır → yok sayılır
        let readings = ascentReadings(from: 30, to: 0, rate: 500)
        let (_, updates) = runMonitor(readings, limit: 10)
        XCTAssertFalse(updates.contains { $0.exceededLimit })
    }

    func testTimeResetClearsMonitor() {
        var monitor = AscentRateMonitor(limit: 10)
        _ = monitor.update(with: DepthReading(depth: 30, timestamp: base, elapsed: 100))
        _ = monitor.update(with: DepthReading(depth: 20, timestamp: base.addingTimeInterval(10),
                                               elapsed: 110))
        XCTAssertGreaterThan(monitor.smoothedRate, 0)
        // Saat sıfırlandı (yüzey aralığı sonrası)
        _ = monitor.update(with: DepthReading(depth: 0, timestamp: base.addingTimeInterval(20),
                                              elapsed: 0))
        XCTAssertEqual(monitor.smoothedRate, 0, accuracy: 0.001)
        XCTAssertEqual(monitor.violationDuration, 0, accuracy: 0.001)
    }

    func testRepeatedIdenticalReadingsProduceZeroRate() {
        var monitor = AscentRateMonitor(limit: 10)
        for step in 0..<10 {
            _ = monitor.update(with: DepthReading(depth: 20,
                                                  timestamp: base.addingTimeInterval(Double(step)),
                                                  elapsed: Double(step)))
        }
        XCTAssertEqual(monitor.smoothedRate, 0, accuracy: 0.001)
    }

    // MARK: - Uçtan uca alarm zinciri

    @MainActor
    func testFastAscentEndToEndProducesWarning() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        // Dibine güvenli in
        for reading in ascentReadings(from: 0, to: 30, rate: 12, startElapsed: 0) {
            controller.ingest(reading)
        }
        // 18 m/dk ile yüksel
        let fast = ascentReadings(from: 30, to: 3, rate: 18,
                                  startElapsed: controller.state.diveTime)
        for reading in fast { controller.ingest(reading) }

        XCTAssertTrue(controller.state.warnings.contains { $0.kind == .fastAscent },
                      "Uçtan uca hızlı çıkış uyarısı üretmeli")
    }

    @MainActor
    func testFastAscentFiresHapticAlarm() {
        let engine = RecordingHapticEngine()
        let controller = DiveSessionController(configuration: .recreational, haptic: engine)
        controller.start(at: base)
        for reading in ascentReadings(from: 0, to: 30, rate: 12) {
            controller.ingest(reading)
        }
        let fast = ascentReadings(from: 30, to: 3, rate: 18,
                                  startElapsed: controller.state.diveTime)
        for reading in fast { controller.ingest(reading) }

        XCTAssertFalse(engine.performed.isEmpty,
                       "Hızlı çıkışta en az bir titreşim üretilmeli")
        XCTAssertTrue(engine.performed.contains { $0.sourceWarning == .fastAscent },
                      "Titreşim kaynağı hızlı çıkış olmalı")
    }

    @MainActor
    func testFastAscentRecordedInReport() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        for reading in ascentReadings(from: 0, to: 30, rate: 12) {
            controller.ingest(reading)
        }
        for reading in ascentReadings(from: 30, to: 2, rate: 18,
                                      startElapsed: controller.state.diveTime) {
            controller.ingest(reading)
        }
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
        let report = controller.makeReport()
        XCTAssertGreaterThan(report.maxAscentRate, DiveSafetyLimits.maximumAscentRate)
        XCTAssertTrue(log.samples.contains { $0.ascentRate > DiveSafetyLimits.maximumAscentRate })
    }

    @MainActor
    func testViolationDuringDecoIsStillCaught() {
        // Deko tavanı varken hızlı çıkış: en tehlikeli senaryo
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        // 45 m'de 50 dk → deko yükümlülüğü
        for reading in ascentReadings(from: 0, to: 45, rate: 12) {
            controller.ingest(reading)
        }
        // 50 dakika dibe sabit bekle
        var holdElapsed = controller.state.diveTime
        for _ in 0..<3_000 {
            holdElapsed += 1
            controller.ingest(DepthReading(
                depth: 45, timestamp: base.addingTimeInterval(holdElapsed),
                elapsed: holdElapsed))
        }
        XCTAssertGreaterThan(controller.state.ceilingDepth, 0, "Deko yükümlülüğü bekleniyordu")

        // Tavanı delerek hızlı çıkış
        var elapsed = controller.state.diveTime
        for _ in 0..<20 {
            elapsed += 1
            let reading = DepthReading(depth: max(0, controller.state.currentDepth - 18.0 / 60),
                                       timestamp: base.addingTimeInterval(elapsed),
                                       elapsed: elapsed)
            controller.ingest(reading)
        }
        XCTAssertTrue(controller.state.warnings.contains { $0.kind == .fastAscent }
                      || controller.state.warnings.contains { $0.kind == .ceilingViolation },
                      "Deko tavanı ihlali veya hızlı çıkış yakalanmalı")
    }

    // MARK: - Alarm politikası

    func testCooldownSuppressesRepeat() {
        var coordinator = AlarmCoordinator(cooldown: 10)
        let warning = DiveWarning(kind: .fastAscent, severity: .critical,
                                  message: "Hızlı çıkış", raisedAtElapsed: 0)
        XCTAssertEqual(coordinator.actions(for: [warning], elapsed: 0).count, 1)
        XCTAssertEqual(coordinator.actions(for: [warning], elapsed: 5).count, 0,
                       "Cooldown içinde tekrar alarm olmamalı")
        XCTAssertEqual(coordinator.actions(for: [warning], elapsed: 11).count, 1)
    }

    func testCooldownIsPerWarningKind() {
        var coordinator = AlarmCoordinator(cooldown: 100)
        let fast = DiveWarning(kind: .fastAscent, severity: .critical,
                               message: "Hızlı çıkış", raisedAtElapsed: 0)
        let ceiling = DiveWarning(kind: .ceilingViolation, severity: .critical,
                                   message: "Tavan", raisedAtElapsed: 0)
        XCTAssertEqual(coordinator.actions(for: [fast], elapsed: 0).count, 1)
        // Farklı tür → cooldown birbirini etkilemez
        XCTAssertEqual(coordinator.actions(for: [ceiling], elapsed: 1).count, 1)
    }

    func testCriticalWarningsSortFirst() {
        var coordinator = AlarmCoordinator()
        let info = DiveWarning(kind: .gasSwitch, severity: .info,
                               message: "Gaz", raisedAtElapsed: 0)
        let critical = DiveWarning(kind: .fastAscent, severity: .critical,
                                   message: "Hızlı çıkış", raisedAtElapsed: 0)
        let actions = coordinator.actions(for: [info, critical], elapsed: 0)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions.first?.kind, .critical)
    }

    func testSilentModeRemovesHaptic() {
        var coordinator = AlarmCoordinator(silentMode: true)
        let warning = DiveWarning(kind: .fastAscent, severity: .critical,
                                  message: "Hızlı çıkış", raisedAtElapsed: 0)
        let action = coordinator.actions(for: [warning], elapsed: 0).first
        // Not: `.none` yazımı `Optional.none` olarak çözümlenir; enum durumu
        // açıkça adlandırılmalıdır.
        XCTAssertEqual(action?.feedback, AlarmAction.HapticFeedback.none)
        XCTAssertNotEqual(action?.visualLevel, AlarmAction.VisualLevel.none,
                          "Sessiz modda bile görsel uyarı kalmalı")
        XCTAssertNotEqual(action?.visualLevel, Optional<AlarmAction.VisualLevel>.none)
    }

    // MARK: - Enerji sınırları

    @MainActor
    func testVeryLongDiveDoesNotOverflow() {
        // 6 saatlik (aşırı) dalış: sayısal kararlılık
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        var elapsed: TimeInterval = 0
        var depth = 0.0
        while elapsed < 6 * 3600 {
            let target = 30.0
            let rate = 10.0 / 60.0
            depth += depth < target ? rate : -rate
            depth = min(max(depth, 0), target)
            controller.ingest(DepthReading(depth: depth,
                                           timestamp: base.addingTimeInterval(elapsed),
                                           elapsed: elapsed))
            elapsed += 1
        }
        let state = controller.state
        XCTAssertFalse(state.gf99.isNaN)
        XCTAssertFalse(state.gf99.isInfinite)
        XCTAssertGreaterThan(state.gf99, 0)
        XCTAssertEqual(state.diveTime, elapsed, accuracy: 1)
        // GF99 tavanla sınırlıdır (çok büyük değer anlamlı değil)
        XCTAssertLessThanOrEqual(state.gf99, 1000)
    }
}
