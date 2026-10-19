import Foundation
import DiveCore

#if os(watchOS)
import WatchKit

/// ADIM 8 — dalış sonrası **arka planda uçuş yasağı takibi**.
///
/// ## watchOS kısıtları
///
/// watchOS'ta uygulama arka planda sürekli çalışamaz. Kullanılabilen iki
/// mekanizma var:
///
/// - `WKExtendedRuntimeSession` — kullanıcı kolunu kaldırdığında açılan kısa
///   oturum (birkaç saat). Bizim senaryomuzda dalıştan hemen sonra zaten
///   aktiftir.
/// - `WKApplicationRefreshBackgroundTask` — sistemin uygun gördüğü anda
///   kısa bir uyanma (arka plan yenileme). Ne zaman geleceği garanti
///   edilmez, bu yüzden **önceden hesaplanmış bir zamanlama** ile
///   birleştirilir: `BackgroundMonitoringPolicy` bir sonraki kontrolün
///   zamanını verir, uygulama o anda uyanmayı ister.
///
/// ## Neden "sonraki kontrol" zamanı önceden hesaplanır?
///
/// Sistem uyanma saatini garanti etmez. Geri sayımın doğru olması için
/// durum **her zaman `SurfaceIntervalManager.update(to:)` ile anlık
/// hesaplanır**; zamanlama yalnızca komplikasyonu ve bildirimi tazelemek
/// içindir. Bu yüzden yanlış bir uyanma güvenli, eksik bir uyanma ise
/// yalnızca gecikmeye yol açar (veri kaybı olmaz).
@available(watchOS 10.0, *)
public final class SurfaceIntervalBackgroundAdapter {

    /// Çalışma durumu.
    public enum State: Equatable {
        /// Aktif izleme oturumu (extended runtime) açık
        case active(until: Date)
        /// Sistem uyanması planlandı
        case scheduled(Date)
        /// Aktif yüzey aralığı yok
        case idle
        /// Uçuş yasağı bitti, izleme durdu
        case cleared
    }

    public private(set) var state: State = .idle
    /// Zamanlama politikası
    public let policy: BackgroundMonitoringPolicy
    /// Kabin profili (kullanıcı ayarı)
    public var cabin: FlightAltitudeCalculator.CabinProfile {
        didSet { reschedule() }
    }

    private var manager: SurfaceIntervalManager?
    private var session: WKExtendedRuntimeSession?
    private var scheduledDate: Date?
    private let calendar: Calendar

    public init(policy: BackgroundMonitoringPolicy = .standard,
                cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel,
                calendar: Calendar = .current) {
        self.policy = policy
        self.cabin = cabin
        self.calendar = calendar
    }

    // MARK: - Yaşam döngüsü

    /// Yüzey aralığı takibini başlatır.
    ///
    /// - Parameter manager: Güncel yüzey aralığı yöneticisi (kopyalanır).
    public func start(manager: SurfaceIntervalManager, now: Date = Date()) {
        self.manager = manager
        let status = manager.update(to: now)
        if status.isNoFlyCleared {
            state = .cleared
            cancel()
            return
        }
        openRuntimeSession()
        reschedule()
    }

    /// İzlemeyi durdurur ve kaynakları serbest bırakır.
    public func cancel() {
        session?.invalidate()
        session = nil
        scheduledDate = nil
        if case .active = state { state = .idle }
        WKApplication.shared().cancelBackgroundRefresh()
    }

    // MARK: - Zamanlama

    /// Bir sonraki kontrolü yeniden planlar.
    public func reschedule() {
        guard let manager, manager.lastDiveEnd != nil else {
            scheduledDate = nil
            state = .idle
            return
        }

        let now = Date()
        let status = manager.update(to: now)

        // Kullanılmış kontrol sayısı, dalıştan bu yana geçen süreden türetilir:
        // uygulama kapalıyken de geçen her 15 dakika bir "kontrol" sayılır.
        let diveEnd = manager.lastDiveEnd ?? now
        let elapsed = max(0, now.timeIntervalSince(diveEnd))
        let usedChecks = Int(elapsed / policy.maximumInterval)

        guard let next = policy.nextCheckDate(now: now,
                                              remainingNoFly: status.noFlyRemaining,
                                              remainingDesaturation: status.desaturationRemaining,
                                              isDiving: false,
                                              usedChecks: usedChecks) else {
            scheduledDate = nil
            state = .cleared
            return
        }

        scheduledDate = next
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: next,
                                                          userInfo: ["reason": "noFly"] as NSDictionary)
        state = .active(until: next)
    }

    /// Planlanmış kontrolün tarihi (varsa).
    public var nextCheckDate: Date? { scheduledDate }

    /// Sistem uyandırdığında çağrılır: durumu tazeler ve yeniden planlar.
    @discardableResult
    public func handleBackgroundRefresh(now: Date = Date()) -> State {
        guard let manager else { return state }
        let status = manager.update(to: now)
        if status.isNoFlyCleared {
            state = .cleared
            cancel()
            return .cleared
        }
        reschedule()
        return state
    }

    // MARK: - Extended runtime

    private func openRuntimeSession() {
        guard session == nil else { return }
        let configuration = WKExtendedRuntimeSessionConfiguration()
        configuration.extendedRuntimeSessionCategory = .mindfulness
        configuration.locationTrackingEnabled = false

        session = WKExtendedRuntimeSession()
        session?.delegate = self
        session?.startSession(using: configuration)
    }

    // MARK: - Kabin profili

    /// Kabin profiline göre kalan uçuş yasağı (saniye).
    public func noFlyRemaining(now: Date = Date()) -> TimeInterval {
        guard let manager else { return 0 }
        return FlightAltitudeCalculator.noFlyTime(tissues: manager.update(to: now) .noFlyRemaining > 0
            ? manager.residualTissues : TissueModel(),
                                              cabin: cabin)
    }
}

@available(watchOS 10.0, *)
extension SurfaceIntervalBackgroundAdapter: WKExtendedRuntimeSessionDelegate {

    public func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                       didChangeTo state: WKExtendedRuntimeSessionState) {
        switch state {
        case .running:
            break
        case .expired, .notRunning:
            // Oturum kapandı: planlı uyanma devrede kalsın.
            self.session = nil
        @unknown default:
            self.session = nil
        }
    }

    public func extendedRuntimeSessionDidExceedRuntimeLimit(_ session: WKExtendedRuntimeSession) {
        self.session = nil
        reschedule()
    }

    public func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                       willDeactivateAfter date: Date) {
        // Bitişten hemen önce bir kontrol iste.
        reschedule()
    }
}
#endif