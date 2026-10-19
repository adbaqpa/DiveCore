#if os(watchOS) && canImport(CoreMotion) && canImport(WatchKit)
import CoreMotion
import Foundation
import WatchKit
import DiveCore

/// watchOS donanımını bir araya getiren "sistem" sınıfı (ADIM 2).
///
/// Bileşenler:
/// - `CMAltimeterDepthSource`  → derinlik/basınç (1 Hz)
/// - `WatchHeadingSource`      → pusola
/// - `WatchHapticEngine`       → dokunsal alarmlar
/// - `DiveSessionController`   → dekompresyon durumu (çekirdek)
///
/// Uygulama katmanı (ADIM 3) yalnızca bu sınıfı gözlemler.
@available(watchOS 10.0, *)
@MainActor
public final class DiveSystem {

    // MARK: - Bileşenler

    public let depthSource: CMAltimeterDepthSource
    public let headingSource: WatchHeadingSource
    public let haptics: WatchHapticEngine
    public private(set) var session: DiveSessionController

    /// Simülasyon modu (gerçek cihaz dışı testler için)
    public var isSimulationMode = false
    private var simulator: DiveSimulator?
    private var simulatorTimer: Timer?

    /// Arka plan görevini (WorkoutKit / extended runtime) tetikleyen çağrı için kanca.
    public var onBackgroundTaskRequest: (() -> Void)?

    // MARK: - Oluşturucu

    public init(configuration: DiveConfiguration = .recreational) {
        self.depthSource = CMAltimeterDepthSource()
        self.headingSource = WatchHeadingSource()
        self.haptics = WatchHapticEngine()
        self.session = DiveSessionController(configuration: configuration, haptic: haptics)
        self.sampler = AdaptiveSampler(policy: AdaptiveSamplingPolicy())
    }

    /// Konfigürasyonu değiştirip oturumu yeniden oluşturur (dalışlar arası).
    public func reconfigure(_ configuration: DiveConfiguration) {
        session = DiveSessionController(configuration: configuration, haptic: haptics)
    }

    // MARK: - Yaşam döngüsü

    /// Dalışı başlatır: sensörleri açar, oturumu başlatır, 1 Hz akışı bağlar.
    public func startDive(scenario: DiveScenario? = nil) throws {
        headingSource.start()

        if let scenario {
            isSimulationMode = true
            simulator = DiveSimulator(scenario: scenario)
        } else {
            isSimulationMode = false
            simulator = nil
        }

        session.start()

        // ADIM 11: enerji profiline göre dinamik örnekleme
        sampler = AdaptiveSampler(profile: energyProfile, state: energyState)

        depthSource.onReading = { [weak self] reading in
            guard let self else { return }
            _ = self.session.ingest(reading, sampler: &self.sampler)
            if let heading = self.headingSource.headingDegrees {
                self.session.updateHeading(heading)
            }
        }
        depthSource.onError = { [weak self] error in
            guard let self else { return }
            if case .calibrationRequired = error { self.onBackgroundTaskRequest?() }
        }

        if isSimulationMode {
            startSimulationLoop()
        } else {
            try depthSource.start()
        }
    }

    // MARK: - ADIM 11 enerji

    /// Aktif enerji profili (ayarlardan gelir).
    public var energyProfile: PowerProfile = .balanced
    /// Cihaz enerji durumu (adaptörden tazelenir).
    public var energyState = EnergyState()
    /// Dinamik örnekleme yürütücüsü.
    public private(set) var sampler: AdaptiveSampler

    /// Enerji durumu değiştiğinde çağrılır: örnekleme politikası yeniden
    /// hesaplanır (pil düşünce aralıklar açılır).
    public func updateEnergy(_ state: EnergyState, profile: PowerProfile) {
        energyState = state
        energyProfile = profile
        sampler.applyEnergy(state)
    }

    /// Dalışı sonlandırır ve `LogEntry` döndürür.
    @discardableResult
    public func endDive() -> LogEntry? {
        simulationTimer?.invalidate()
        simulationTimer = nil
        depthSource.stop()
        headingSource.stop()
        return session.end()
    }

    // MARK: - Simülasyon döngüsü

    private func startSimulationLoop() {
        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard var sim = self.simulator, let reading = sim.next() else {
                    self.simulationTimer?.invalidate()
                    self.simulationTimer = nil
                    return
                }
                self.simulator = sim
                self.session.ingest(reading)
            }
        }
    }

    // MARK: - Kullanıcı aksiyonları

    /// Action Button / dijital taç: yer imi ekler.
    public func addMarker() {
        session.addMarker()
        haptics.tapFeedback()
    }

    /// Gaz değişimi.
    public func switchGas(to index: Int) {
        session.switchGas(to: index)
        haptics.tapFeedback()
    }

    /// Kullanıcı alarmı okuduğunu onayladı.
    public func acknowledgeAlarm() {
        haptics.acknowledge()
    }

    /// Arka plan/ön plan geçişlerinde çağrılır.
    public func handleScenePhaseChange(isActive: Bool) {
        if isActive {
            haptics.tick()
            headingSource.start()
        } else {
            onBackgroundTaskRequest?()
        }
    }
}
#endif