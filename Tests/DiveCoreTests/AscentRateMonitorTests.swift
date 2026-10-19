import XCTest
@testable import DiveCore

/// Çıkış hızı takipçisi: yumuşatma, ihlal sürekliliği, alarm cooldown.
final class AscentRateMonitorTests: XCTestCase {

    // MARK: - Yardımcı

    private func readings(depths: [Double], interval: TimeInterval = 1) -> [DepthReading] {
        depths.enumerated().map { index, depth in
            DepthReading(depth: depth,
                         timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * interval),
                         elapsed: Double(index) * interval,
                         isSimulated: true)
        }
    }

    /// Derinlikleri doğrusal olarak değiştirir (sabit hız).
    private func linearProfile(from start: Double, to end: Double, seconds: Int) -> [DepthReading] {
        readings(depths: (0...seconds).map { index in
            start + (end - start) * Double(index) / Double(seconds)
        })
    }

    // MARK: - Temel davranış

    func testFirstReadingHasNoRate() {
        var monitor = AscentRateMonitor()
        let update = monitor.update(with: readings(depths: [10])[0])
        XCTAssertEqual(update.smoothedRate, 0)
        XCTAssertEqual(update.instantaneousRate, 0)
        XCTAssertFalse(update.exceededLimit)
    }

    func testConstantRateIsDetected() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)   // yumuşatma kapalı
        var lastUpdate = AscentRateUpdate.placeholder
        for reading in linearProfile(from: 20, to: 0, seconds: 60).dropFirst() {
            lastUpdate = monitor.update(with: reading)
        }
        // 20 m / 60 sn = 20 m/dk yukarı (pozitif)
        XCTAssertEqual(lastUpdate.smoothedRate, 20, accuracy: 0.2)
        // Profil yüzeyde bittiği için son durum "yüzey" olur; ara bir
        // noktada hız sınıflamasını kontrol ediyoruz.
        XCTAssertGreaterThan(lastUpdate.smoothedRate, DiveSafetyLimits.maximumAscentRate)
    }

    func testStatusWhileUnderway() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        let profile = linearProfile(from: 30, to: 0, seconds: 90)   // 20 m/dk
        var statuses: [AscentRateStatus] = []
        // İlk birkaç ölçüm hız henüz oturmamıştır; atlanır.
        for reading in profile.dropFirst(5) {
            statuses.append(monitor.update(with: reading).status)
        }
        XCTAssertTrue(statuses.contains(.danger), "Hızlı çıkışta kırmızı durum beklenir")
        let dangerShare = Double(statuses.filter { $0 == .danger }.count) / Double(statuses.count)
        XCTAssertGreaterThan(dangerShare, 0.8, "Çıkışın büyük bölümü tehlikeli olmalı")
    }

    func testSafeStatusWhileUnderway() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        let profile = linearProfile(from: 30, to: 0, seconds: 600)   // 3 m/dk
        var statuses: [AscentRateStatus] = []
        for reading in profile.dropFirst(5) {
            statuses.append(monitor.update(with: reading).status)
        }
        XCTAssertTrue(statuses.contains(.safe))
        XCTAssertFalse(statuses.contains(.danger))
    }

    func testSlowAscentIsSafe() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        var last = AscentRateUpdate.placeholder
        for reading in linearProfile(from: 20, to: 5, seconds: 600).dropFirst() {  // 1.5 m/dk
            last = monitor.update(with: reading)
        }
        XCTAssertEqual(last.smoothedRate, 1.5, accuracy: 0.2)
        XCTAssertEqual(last.status, .safe)
        XCTAssertFalse(last.exceededLimit)
    }

    func testDescentHasNegativeRate() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        var last = AscentRateUpdate.placeholder
        for reading in linearProfile(from: 0, to: 30, seconds: 120).dropFirst() {
            last = monitor.update(with: reading)
        }
        XCTAssertEqual(last.smoothedRate, -15, accuracy: 0.2)
        XCTAssertTrue(last.status == .descending || last.status == .surface)
    }

    // MARK: - Yumuşatma

    func testSmoothingReducesNoise() {
        var monitor = AscentRateMonitor(smoothingFactor: 0.2)
        let noisy = readings(depths: [10.0, 11.0, 10.0, 11.0, 10.0, 11.0, 10.0, 11.0])
        var rawRates: [Double] = []
        for reading in noisy.dropFirst() {
            let update = monitor.update(with: reading)
            rawRates.append(abs(update.instantaneousRate))
        }
        // Ham hızlar ±60 m/dk arasında salınıyor (1 m/s)
        XCTAssertGreaterThan(rawRates.max() ?? 0, 50)
        // Yumuşatılmış hız çok daha kontrollü
        XCTAssertLessThan(abs(monitor.smoothedRate), 20)
    }

    func testSmoothingIsExponentialWeightedAverage() {
        var monitor = AscentRateMonitor(smoothingFactor: 0.5)
        // 60 m'yi 60 saniyede çıkış = 60 m/dk (pozitif)
        for reading in linearProfile(from: 60, to: 0, seconds: 60).dropFirst() {
            monitor.update(with: reading)
        }
        XCTAssertGreaterThan(monitor.smoothedRate, 55)
    }

    // MARK: - İhlal sürekliliği

    func testViolationRequiresPersistence() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0, violationHoldTime: 10)
        let profile = linearProfile(from: 30, to: 0, seconds: 60)   // 30 m/dk

        var exceededAt: TimeInterval?
        for reading in profile.dropFirst() {
            let update = monitor.update(with: reading)
            if update.exceededLimit, exceededAt == nil { exceededAt = reading.elapsed }
        }
        // İlk ölçümde (t=1) hız henüz tam oluşmamıştır; 10 saniyelik
        // süreklilik sağlandığında (t=11) alarm verilmeli.
        XCTAssertEqual(exceededAt, 11)
    }

    func testSingleSpikeDoesNotTriggerViolation() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0, violationHoldTime: 5)

        // 30 m'de 4 saniye, sonra 1 saniyelik sıçrama, ardından sabit derinlik
        var profile: [DepthReading] = []
        for index in 0..<10 {
            let depth = index < 4 ? 30.0 : 31.0
            profile.append(DepthReading(depth: depth,
                                        timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                                        elapsed: Double(index),
                                        isSimulated: true))
        }

        var everExceeded = false
        for reading in profile.dropFirst() {
            if monitor.update(with: reading).exceededLimit { everExceeded = true }
        }
        XCTAssertFalse(everExceeded, "Tek saniyelik sıçrama alarm üretmemeli")
    }

    func testViolationDurationResetsWhenRateDrops() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0, violationHoldTime: 5)
        // 5 sn hızlı çıkış
        for reading in linearProfile(from: 30, to: 27.5, seconds: 5).dropFirst() {
            monitor.update(with: reading)
        }
        XCTAssertGreaterThan(monitor.violationDuration, 0)
        // 20 sn bekle (hız sıfır)
        for reading in linearProfile(from: 27.5, to: 27.5, seconds: 20).dropFirst() {
            monitor.update(with: reading)
        }
        XCTAssertEqual(monitor.violationDuration, 0)
    }

    // MARK: - Alarm zamanlaması

    func testAlarmRespectsCooldown() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0, violationHoldTime: 4, alarmCooldown: 20)
        var alarmTimes: [TimeInterval] = []
        // 120 saniye boyunca 30 m/dk çıkış
        for reading in linearProfile(from: 40, to: 0, seconds: 120).dropFirst() {
            if monitor.update(with: reading).alarmDue { alarmTimes.append(reading.elapsed) }
        }
        XCTAssertFalse(alarmTimes.isEmpty)
        XCTAssertEqual(alarmTimes.first, 5)
        // Ardışık alarmlar en az 20 sn aralıklı
        for index in 1..<max(1, alarmTimes.count) {
            XCTAssertGreaterThanOrEqual(alarmTimes[index] - alarmTimes[index - 1], 20)
        }
    }

    func testNoAlarmWhenWithinLimit() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        var alarmCount = 0
        for reading in linearProfile(from: 10, to: 0, seconds: 600).dropFirst() {  // 1 m/dk
            if monitor.update(with: reading).alarmDue { alarmCount += 1 }
        }
        XCTAssertEqual(alarmCount, 0)
    }

    // MARK: - Yüzey davranışı

    func testSurfaceReadingsDoNotTriggerViolation() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        var everExceeded = false
        // Yüzeyde gürültülü sığ "çıkışlar"
        let depths: [Double] = [0.0, 0.2, 0.0, 0.25, 0.0, 0.3, 0.0, 0.25, 0.0]
        for (index, depth) in depths.enumerated() {
            let reading = DepthReading(depth: depth,
                                       timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                                       elapsed: Double(index), isSimulated: true)
            if monitor.update(with: reading).exceededLimit { everExceeded = true }
        }
        XCTAssertFalse(everExceeded, "Yüzeyde hız alarmı üretilmemeli")
    }

    // MARK: - İstatistikler

    func testTotalAscentAndDescentAreTracked() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        for reading in linearProfile(from: 0, to: 30, seconds: 120).dropFirst() {
            monitor.update(with: reading)
        }
        XCTAssertEqual(monitor.totalDescent, 30, accuracy: 0.3)
        XCTAssertEqual(monitor.totalAscent, 0, accuracy: 0.001)

        for reading in linearProfile(from: 30, to: 10, seconds: 120).dropFirst() {
            monitor.update(with: reading)
        }
        XCTAssertEqual(monitor.totalAscent, 20, accuracy: 0.3)
    }

    func testResetClearsEverything() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        for reading in linearProfile(from: 30, to: 0, seconds: 60).dropFirst() {
            monitor.update(with: reading)
        }
        monitor.reset()
        XCTAssertEqual(monitor.smoothedRate, 0)
        XCTAssertEqual(monitor.totalAscent, 0)
        XCTAssertNil(monitor.lastAlarmAt)

        // Sıfırdan sonra ilk okuma yine hızsız olmalı
        let update = monitor.update(with: readings(depths: [5])[0])
        XCTAssertEqual(update.instantaneousRate, 0)
    }

    // MARK: - Zaman sıfırlama

    func testNonMonotonicTimeIsHandled() {
        var monitor = AscentRateMonitor()
        for reading in linearProfile(from: 10, to: 5, seconds: 10) {
            monitor.update(with: reading)
        }
        // Saat sıfırlanması: yeni başlangıç
        let restarted = DepthReading(depth: 0,
                                     timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                     elapsed: 0, isSimulated: true)
        let update = monitor.update(with: restarted)
        XCTAssertEqual(update.instantaneousRate, 0, "Zaman sıfırlanınca hız sıfır olmalı")
    }

    // MARK: - Yapılandırma

    func testSmoothingFactorIsClamped() {
        let monitor = AscentRateMonitor(smoothingFactor: 5.0)
        XCTAssertLessThanOrEqual(monitor.smoothingFactor, 1.0)
        let low = AscentRateMonitor(smoothingFactor: 0.0)
        XCTAssertGreaterThan(low.smoothingFactor, 0.0)
    }

    func testStatusEvaluationBoundaries() {
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 10, depth: 10), .caution)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 10.5, depth: 10), .danger)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 7, depth: 10), .safe)
        XCTAssertEqual(AscentRateStatus.evaluate(rate: 7.5, depth: 10), .caution)
    }

    func testUpdateDisplayRate() {
        var monitor = AscentRateMonitor(smoothingFactor: 1.0)
        var update = AscentRateUpdate.placeholder
        for reading in linearProfile(from: 18, to: 0, seconds: 120).dropFirst() {   // 9 m/dk
            update = monitor.update(with: reading)
        }
        XCTAssertEqual(update.displayRate, "9.0")
        XCTAssertEqual(update.totalAscent, 18, accuracy: 0.2)
    }
}

// MARK: - Placeholder (shim uyumluluğu için)

extension AscentRateUpdate {
    /// Testlerde "son durum" değişkenini başlatmak için kullanılır.
    static let placeholder = AscentRateUpdate(
        reading: DepthReading(depth: 0, timestamp: Date(timeIntervalSince1970: 0), elapsed: 0),
        instantaneousRate: 0,
        smoothedRate: 0,
        status: .surface,
        exceededLimit: false,
        alarmDue: false,
        violationDuration: 0,
        totalAscent: 0,
        totalDescent: 0)
}