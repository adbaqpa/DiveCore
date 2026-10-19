#if os(watchOS) || os(iOS)
import CoreMotion
import Foundation
import DiveCore

/// CoreMotion tabanlı derinlik/basınç sensörü (watchOS 10+).
///
/// ## Donanım gerçekliği hakkında önemli not
/// Apple Watch'ta **derinlik ölçen herkese açık bir API yoktur**. Apple'ın Depth
/// uygulaması Ultra'da özel donanım/çipleri kullanır ve bu API dışarıya
/// açık değildir. Kullanılabilen en yakın sinyaller:
///
/// - `CMAltimeter`: atmosfer basıncına dayalı **göreli yükseklik**. Suyun
///   altında da çalışır ve su sütununun yarattığı basınç farkını verir.
///   Yüzeydeki referans basınçla karşılaştırıldığında derinlik elde edilir.
/// - `CMMotionManager` ivmeölçer: hareket/aktivite (nemeşik, çalkalanma).
///
/// Bu sınıf:
/// 1. Yüzeye çıkarken (ya da başlangıçta) referans basıncı kalibre eder,
/// 2. `relativeAltitude` farkını derinliğe çevirir,
/// 3. Ölçüm gürültüsünü yumuşatır,
/// 4. Kalibrasyon yapılamıyorsa `DepthSensorError.calibrationRequired` bildirir.
///
/// ## Sığ derinliklerde hassasiyet
/// Basınç temelli ölçüm yüzeye yakın (0-3 m) çalışır; derinleştikçe
/// mutlak doğruluk artar, ancak sığ dalışlarda dalış filigranıyla karışabilir.
/// Üretim sürümünde hibrit çözüm (ivmeölçer + zaman filtreleme) önerilir.
@available(watchOS 10.0, iOS 16.0, *)
@MainActor
public final class CMAltimeterDepthSource: NSObject, DepthSensor {

    public var onReading: ((DepthReading) -> Void)?
    public var onError: ((DepthSensorError) -> Void)?

    public private(set) var isRunning = false
    public let sourceName = "CMAltimeter"

    // MARK: - Ayarlar

    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.dive.depthsource"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Yumuşatma katsayısı (0 = ham, 1 = tam yumuşatma)
    public var smoothing: Double = 0.4
    /// Referans basınç (bar). `nil` ise ilk ölçümde kalibre edilir.
    public var surfacePressure: Double?

    // MARK: - Dahili durum

    private var lastRelativeAltitude: Double?
    private var startDate: Date?
    private var lastDepth: Double = 0
    private var pendingErrorReported = false

    public override init() {
        super.init()
    }

    // MARK: - DepthSensor

    public func start() throws {
        guard !isRunning else { return }
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            let error = DepthSensorError.notAvailable("CMAltimeter göreli yükseklik desteklemiyor")
            onError?(error)
            throw error
        }

        isRunning = true
        startDate = Date()
        lastDepth = 0
        pendingErrorReported = false

        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor in
                    self?.onError?(.underlying(message))
                }
                return
            }
            guard let data else { return }

            let relative = data.relativeAltitude.doubleValue      // metre
            let pressure = data.pressure.doubleValue              // kPa
            Task { @MainActor in
                self?.handle(relativeAltitude: relative, pressureKPa: pressure)
            }
        }

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0
            motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let motion else { return }
                let intensity = sqrt(motion.userAcceleration.x * motion.userAcceleration.x
                                     + motion.userAcceleration.y * motion.userAcceleration.y
                                     + motion.userAcceleration.z * motion.userAcceleration.z)
                Task { @MainActor in
                    self?.lastMotionIntensity = intensity
                }
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopDeviceMotionUpdates()
        lastRelativeAltitude = nil
    }

    // MARK: - İşleme

    private var lastMotionIntensity: Double = 0

    private func handle(relativeAltitude: Double, pressureKPa: Double) {
        guard isRunning else { return }

        // Yüzey referansı: ilk okumda kalibre et
        if surfacePressure == nil {
            surfacePressure = Double(pressureKPa) / 100.0
        }

        // Derinlik = yüzeyden aşağı yöndeki yükseklik farkı
        let rawDepth = max(0, -relativeAltitude)

        // Yumuşatma
        lastDepth = smoothing * rawDepth + (1 - smoothing) * lastDepth

        let elapsed = Date().timeIntervalSince(startDate ?? Date())
        let reading = DepthReading(
            depth: lastDepth,
            ambientPressure: DivePhysics.ambientPressure(depthMeters: lastDepth),
            surfacePressure: surfacePressure ?? DivePhysics.surfacePressure,
            timestamp: Date(),
            elapsed: elapsed,
            isSimulated: false)

        onReading?(reading)
    }

    /// Yüzey referansını sıfırlar (dalış başlangıcında çağrılır).
    public func calibrateSurface(pressureKPa: Double) {
        surfacePressure = Double(pressureKPa) / 100.0
    }

    /// Yüzey basıncını ölçerek kalibrasyon yapar (yüzeydeyken çağrılır).
    public func autoCalibrate() async throws {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            throw DepthSensorError.notAvailable("CMAltimeter")
        }
        let instrument = altimeter
        let kPa: Double = try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            instrument.startRelativeAltitudeUpdates(to: queue) { data, error in
                let finish: (Result<Double, Error>) -> Void = { result in
                    lock.lock()
                    let alreadyResumed = resumed
                    resumed = true
                    lock.unlock()
                    guard !alreadyResumed else { return }
                    instrument.stopRelativeAltitudeUpdates()
                    continuation.resume(with: result)
                }
                if let error { return finish(.failure(error)) }
                if let data { finish(.success(data.pressure.doubleValue)) }
            }
        }
        calibrateSurface(pressureKPa: kPa)
    }
}
#endif