#if os(watchOS) || os(iOS)
import CoreMotion
import CoreLocation
import Foundation
import DiveCore

/// Pusola/yön bilgisi kaynağı (ADIM 3'teki heading göstergesi için).
///
/// Öncelik sırası:
/// 1. `CLHeading` (konum servisi) — en doğru pusula değeri,
/// 2. `CMMotionManager.heading` — manyetik/ivmeölçer tabanlı (konum izni yoksa).
///
/// Apple Watch'ta pusola **konum izni** gerektirir; kullanıcı izni vermezse
/// CoreMotion başlığına düşülür ve bu durum `isMagneticHeading` ile bildirilir.
@available(watchOS 10.0, iOS 16.0, *)
@MainActor
public final class WatchHeadingSource: NSObject, CLLocationManagerDelegate {

    public private(set) var headingDegrees: Double?
    public private(set) var accuracy: Double = -1
    /// Konum servisi olmadan manyetik başlık mı kullanılıyor?
    public private(set) var isMagneticFallback = false

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.dive.heading"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var wantsUpdates = false

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.headingFilter = 1
    }

    /// Konum izni ister ve başlığı dinlemeye başlar.
    public func start() {
        guard !wantsUpdates else { return }
        wantsUpdates = true

        locationManager.requestWhenInUseAuthorization()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }

        if CMMotionManager.isHeadingAvailable() {
            motionManager.headingUpdateInterval = 1.0
            motionManager.startHeadingUpdates(to: queue) { [weak self] heading, _ in
                guard let self else { return }
                let value = heading?.magneticHeading
                Task { @MainActor in
                    // Konum başlığı gelene kadar manyetik başlığı kullan
                    guard self.headingDegrees == nil, let value else { return }
                    self.headingDegrees = value
                    self.isMagneticFallback = true
                }
            }
        }
    }

    public func stop() {
        wantsUpdates = false
        locationManager.stopUpdatingHeading()
        motionManager.stopHeadingUpdates()
        headingDegrees = nil
        isMagneticFallback = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManager(_ manager: CLLocationManager,
                                            didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let horizontalAccuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.headingDegrees = degrees
            self.accuracy = horizontalAccuracy
            self.isMagneticFallback = newHeading.trueHeading < 0
        }
    }

    nonisolated public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
#endif