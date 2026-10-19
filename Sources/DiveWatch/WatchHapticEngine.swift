#if os(watchOS) && canImport(CoreMotion) && canImport(WatchKit)
import WatchKit
import Foundation
import DiveCore

/// watchOS dokunsal geri bildirim motoru.
///
/// ADIM 2 gereksinimi: hızlı çıkış ihlalinde
/// `WKInterfaceDevice.current().play(.notification)` çağrılır.
///
/// Alarm kararları (`AlarmCoordinator`) çekirdekte verilir; bu sınıf yalnızca
/// kararı WatchKit'e taşır — bu sayede alarm politikası platformdan bağımsız
/// test edilir.
@available(watchOS 10.0, *)
@MainActor
public final class WatchHapticEngine: HapticEngine {

    private let device: WKInterfaceDevice?
    private var isCriticalActive = false
    private var lastCriticalAt: Date?

    /// Tekrarlanan kritik titreşim aralığı (saniye)
    public var criticalRepeatInterval: TimeInterval = 6

    public init(device: WKInterfaceDevice? = .current()) {
        self.device = device
    }

    public func perform(_ actions: [AlarmAction]) {
        guard let device else { return }

        for action in actions where action.feedback != .none {
            switch action.feedback {
            case .none:
                break

            case .notification:
                device.play(.notification)

            case .directional:
                // Hızlı çıkışta yön bilgisi anlamlı değil; nazik uyarı verilir
                device.play(.notification)

            case .success:
                device.play(.success)

            case .critical:
                device.play(.failure)
                if isCriticalActive == false { lastCriticalAt = Date() }
                isCriticalActive = true

            case .repeated:
                // Sürekli titreşim: kritik alarm sürerken periyodik hatırlatma
                device.play(.retry)
            }
        }
    }

    public func tapFeedback() {
        device?.play(.click)
    }

    public func acknowledge() {
        device?.play(.success)
        isCriticalActive = false
        lastCriticalAt = nil
    }

    /// Arka plan görevleri tarafından periyodik çağrılır (kritik alarm sürerken).
    public func tick() {
        guard isCriticalActive, let lastCriticalAt else { return }
        if Date().timeIntervalSince(lastCriticalAt) >= criticalRepeatInterval {
            device?.play(.retry)
            self.lastCriticalAt = Date()
        }
    }

    /// Mevcut durum (UI testleri için).
    public var criticalAlarmActive: Bool { isCriticalActive }
}
#endif