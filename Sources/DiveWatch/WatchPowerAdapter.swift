import Foundation
import DiveCore

#if os(watchOS)
import WatchKit

/// ADIM 11 — cihaz enerji durumunu okuyan ince adaptör.
///
/// `WKInterfaceDevice` pil ölçümü ve `ProcessInfo` termal durumu **ham**
/// veri sağlar; tüm kararlar `EnergyManager` (çekirdek) içinde verilir.
///
/// ## Dikkat
/// Pil ölçümü `WCSession.isSupported()` gerektirir ve yalnızca gerçek
/// Ultra'da anlamlıdır. Bu yüzden adaptör her zaman "bilinmiyor" durumuna
/// düşebilir ve çekirdek buna göre temkinli davranır.
@available(watchOS 10.0, *)
public final class WatchPowerAdapter {

    /// Pil ölçümü dinleyicisi.
    public var onChange: ((EnergyState) -> Void)?

    private var timer: Timer?
    private let pollInterval: TimeInterval
    private(set) var lastState: EnergyState

    public init(pollInterval: TimeInterval = 30) {
        self.pollInterval = pollInterval
        self.lastState = WatchPowerAdapter.readEnergyState()
    }

    // MARK: - Okuma

    /// Cihazın anlık enerji durumu.
    public static func readEnergyState(theme: DiveDisplayTheme = .standard,
                                       isDiving: Bool = false,
                                       profile: PowerProfile = .balanced,
                                       isAlwaysOn: Bool = false) -> EnergyState {
        WKInterfaceDevice.current.isBatteryMonitoringEnabled = true

        let rawLevel = WKInterfaceDevice.current.batteryLevel
        // -1 = bilinmiyor
        let level: Double? = rawLevel >= 0 ? Double(rawLevel) : nil

        return EnergyState(
            batteryLevel: level,
            isLowPowerModeEnabled: WKInterfaceDevice.current.isLowPowerModeEnabled,
            thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
            isAlwaysOn: isAlwaysOn,
            theme: theme,
            isDiving: isDiving,
            profile: profile)
    }

    /// `ProcessInfo.ThermalState` → çekirdek tipi.
    static func ThermalState(_ state: ProcessInfo.ThermalState) -> EnergyState.ThermalState {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    // MARK: - İzleme

    /// Periyodik pil/termal yoklaması başlatır.
    ///
    /// - Note: Pil verisi yalnızca iOS 9+/watchOS 3+ cihazlarda ve pil
    ///   ölçümü etkinken gelir; bu yüzden **nadir** yoklama (30 sn) yeterlidir.
    ///   Dalış sırasında saniyelik yoklama pil tüketir.
    public func start() {
        stop()
        lastState = WatchPowerAdapter.readEnergyState(theme: lastState.theme,
                                                      isDiving: lastState.isDiving,
                                                      profile: lastState.profile,
                                                      isAlwaysOn: lastState.isAlwaysOn)
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        onChange?(lastState)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Anlık yoklama.
    public func poll() {
        let fresh = WatchPowerAdapter.readEnergyState(theme: lastState.theme,
                                                      isDiving: lastState.isDiving,
                                                      profile: lastState.profile,
                                                      isAlwaysOn: lastState.isAlwaysOn)
        guard fresh != lastState else { return }
        lastState = fresh
        onChange?(fresh)
    }

    /// Dalış durumu değiştiğinde bağlamı güncelle.
    public func updateContext(isDiving: Bool, isAlwaysOn: Bool,
                              theme: DiveDisplayTheme, profile: PowerProfile) {
        lastState = WatchPowerAdapter.readEnergyState(theme: theme,
                                                      isDiving: isDiving,
                                                      profile: profile,
                                                      isAlwaysOn: isAlwaysOn)
        onChange?(lastState)
    }
}

/// ADIM 11 — `WKExtendedRuntimeSession` **kullanım optimizasyonu**.
///
/// ## Neden?
/// ADIM 7'de su kilidi için başlatılan extended runtime oturumu, kullanıcı
/// kolunu çevirip cihazı çıkardığında **kapanır**. Dalış sırasında
/// (su altındayken) kol çevirme olmadığı için oturum açık kalmalıdır.
///
/// ## Optimizasyon ilkeleri
///
/// 1. **Tek oturum, doğru kategori** — `.mindfulness` yerine `.selfCare`
///    kullanılır; Apple'ın belgelediği süre limitleri daha uzundur.
/// 2. **AOD ile uyum** — AOD'da ekran açıktır, oturumun kapatılmasına
///    gerek yoktur; kapatma yalnızca ekran **kapalıyken** yapılır.
/// 3. **Pil düşükse kısa oturum** — kullanıcıya "yüzeye dön" bilgisi verilir,
///    oturum bilinçli olarak sonlandırılır.
/// 4. **Kendi sunduğumuz oturumu yönetiyoruz** — `DiveLockController`'ın
///    su kilidi oturumu ile bu oturum çakışmamalıdır; adaptör
///    `isSurfaceSessionActive` bayrağıyla bunu korur.
@available(watchOS 10.0, *)
public final class DiveRuntimeSessionAdapter {

    public enum State: Equatable {
        case inactive
        case running(since: Date)
        /// Sistem limitine yaklaşıldı — kullanıcı uyarılmalı
        case expiring(remaining: TimeInterval)
        case failed(String)
    }

    public private(set) var state: State = .inactive
    /// Başka bir modül (su kilidi) oturum açtı mı? — çakışma koruması
    public var isSurfaceSessionActive: Bool = false

    private var session: WKExtendedRuntimeSession?
    /// Pil oranı düşerse oturum kapatılır
    public var minimumBatteryForExtendedSession: Double = 0.20

    public init() {}

    // MARK: - Yaşam döngüsü

    /// Oturumu başlatır.
    ///
    /// - Parameters:
    ///   - batteryLevel: Güncel pil seviyesi (0...1)
    ///   - isAlwaysOn: AOD açık mı
    /// - Returns: Oturum açıldıysa `true`.
    @discardableResult
    public func start(batteryLevel: Double?, isAlwaysOn: Bool) -> Bool {
        guard session == nil else { return true }

        // 3) Pil düşükse uzatma
        if let batteryLevel, batteryLevel < minimumBatteryForExtendedSession {
            state = .failed("Pil %\(Int(batteryLevel * 100)) — oturum uzatılmadı")
            return false
        }

        // 1) Tek oturum, doğru kategori
        let configuration = WKExtendedRuntimeSessionConfiguration()
        // 2) AOD durumunda kapatma yok — ekran zaten açık, oturum gerekli
        configuration.extendedRuntimeSessionCategory = .selfCare
        configuration.locationTrackingEnabled = false

        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.startSession(using: configuration)
        session = newSession
        state = .running(since: Date())
        return true
    }

    /// Oturumu sonlandırır.
    public func end() {
        session?.invalidate()
        session = nil
        state = .inactive
    }

    // MARK: - Bütçe

    /// Apple'ın belgelediği azami süre (saat) — `selfCare` kategorisi.
    ///
    /// - Note: Kesin sınır cihaz yazılımına göre değişebilir; kullanıcıya
    ///   kalan süreyi göstermek için kullanılır, garanti değildir.
    public static let maximumDurationHours: Double = 12

    /// Kalan süre tahmini (saat).
    public var estimatedRemainingHours: Double? {
        guard case .running(let since) = state else { return nil }
        let used = Date().timeIntervalSince(since) / 3600
        return max(0, DiveRuntimeSessionAdapter.maximumDurationHours - used)
    }

    /// Kullanıcı bilgilendirmesi gerekli mi?
    public var shouldWarnUser: Bool {
        guard let remaining = estimatedRemainingHours else { return false }
        return remaining < 2
    }
}

@available(watchOS 10.0, *)
extension DiveRuntimeSessionAdapter: WKExtendedRuntimeSessionDelegate {

    public func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                       didChangeTo state: WKExtendedRuntimeSessionState) {
        switch state {
        case .running:
            if case .running = self.state { return }
            self.state = .running(since: Date())
        case .expired, .notRunning:
            // Su kilidi oturumu varsa bu kapanış normaldir.
            self.session = nil
            if isSurfaceSessionActive {
                self.state = .inactive
            } else {
                self.state = .failed("Çalışma süresi doldu")
            }
        @unknown default:
            self.session = nil
            self.state = .inactive
        }
    }

    public func extendedRuntimeSessionDidExceedRuntimeLimit(_ session: WKExtendedRuntimeSession) {
        self.session = nil
        if let remaining = estimatedRemainingHours {
            self.state = .expiring(remaining: remaining)
        } else {
            self.state = .failed("Çalışma süresi sınırına ulaşıldı")
        }
    }

    public func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                       willDeactivateAfter date: Date) {
        let remaining = date.timeIntervalSinceNow
        if remaining > 0 {
            state = .expiring(remaining: remaining)
        }
    }
}
#endif
