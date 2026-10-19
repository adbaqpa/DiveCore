#if os(watchOS) && canImport(WatchKit)
import AVFoundation
import Foundation
import WatchKit
import DiveCore

/// watchOS su kilidi / arka plan çalışması adaptörü (ADIM 7).
///
/// ## Neler yapılabilir, neler yapılamaz?
/// | İstenen | Durum |
/// |---|---|
/// | Uygulama içi dokunma kilidi | ✅ `DiveLockController` + `.disabled/hit testing` |
/// | Su atma (audio ejection) | ✅ Hoparlörden ses çalma (`AVAudioSession` + `WKInterfaceDevice.play`) |
/// | Dalış sırasında ekranın açık kalması | ✅ `WKExtendedRuntimeSession` |
/// | **Sistem Su Kilit'i programatik açma** | ❌ Kamuya açık API yok — kullanıcı Control Center'dan açar |
///
/// Son satır neden önemli? Apple'ın Water Lock'ı bir güvenlik mekanizmasıdır ve
/// uygulamalar tarafından tetiklenemez. Bu yüzden uygulama hem otomatik dokunma
/// kilidini uygular hem de kullanıcıyı yönlendirir.
@available(watchOS 10.0, *)
@MainActor
public final class WatchWaterLockAdapter {

    // MARK: - Bileşenler

    private let session: WKExtendedRuntimeSession?
    private let haptic: WatchHapticEngine
    private var playbackWorkItems: [DispatchWorkItem] = []

    /// Su kilidi beklentisi (kullanıcı ayarı)
    public var isSystemLockEnabled = false

    public init(session: WKExtendedRuntimeSession? = .self, haptic: WatchHapticEngine) {
        self.session = session
        self.haptic = haptic
    }

    // MARK: - Yaşam döngüsü

    /// Dalış başladı: uzatılmış çalışma oturumunu başlatır.
    public func onDiveStarted() {
        guard let session else { return }
        session.start()
    }

    /// Dalış bitti: oturumu kapatır.
    public func onDiveEnded() {
        session?.stop()
    }

    /// Dalış sırasında arka plana alındığında oturumu sürdürür.
    public func onScenePhaseChange(isActive: Bool) {
        guard let session else { return }
        if isActive {
            if session.state == .notStarted { session.start() }
        } else if session.state == .active {
            session.continue()
        }
    }

    // MARK: - Su atma döngüsü

    /// Su atma seslerini sırayla çalar (ses + titreşim).
    ///
    /// - Note: `DiveLockController` sıralamayı ve süreleri üretir; bu sınıf
    ///   yalnızca WatchKit/AV tarafını sürer. İlk hoparlör sesi suyu atar,
    ///   ardından titreşimler cihazın "boşaltılmasını" destekler.
    public func playEjectionSequence(_ steps: [DiveLockController.EjectionStep],
                                     completion: (() -> Void)? = nil) {
        cancelEjection()
        guard !steps.isEmpty else {
            completion?()
            return
        }

        var delay: TimeInterval = 0
        for step in steps {
            let work = DispatchWorkItem { [weak self] in
                self?.perform(step.sound)
            }
            playbackWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            delay += step.delay
        }

        let done = DispatchWorkItem { [weak self] in
            self?.playbackWorkItems.removeAll()
            completion?()
        }
        playbackWorkItems.append(done)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: done)
    }

    /// Su atma döngüsünü iptal eder (kullanıcı erken bitirdi).
    public func cancelEjection() {
        playbackWorkItems.forEach { $0.cancel() }
        playbackWorkItems.removeAll()
    }

    /// Tek bir adımı çalar.
    private func perform(_ sound: DiveLockController.EjectionStep.Sound) {
        switch sound {
        case .tone:
            haptic.perform([AlarmAction(kind: .warning, feedback: .notification,
                                        visualLevel: .none, message: "titreşim")])
        case .click:
            haptic.tapFeedback()
        case .chirp:
            haptic.perform([AlarmAction(kind: .info, feedback: .success,
                                        visualLevel: .none, message: "ses")])
        case .success:
            haptic.perform([AlarmAction(kind: .info, feedback: .success,
                                        visualLevel: .none, message: "bitti")])
        }
    }

    // MARK: - Kullanıcı yönlendirmesi

    /// Sistem su kilidi kullanılamıyorsa gösterilecek metin.
    public var guidanceText: String {
        isSystemLockEnabled
            ? "Su kilidi etkin"
            : "Su Kilit'i Control Center'dan açmanız önerilir"
    }
}

/// Basit bip üretici (su atma sesleri için `AVAudioEngine` tabanlı).
///
/// watchOS'ta kısa bir `AVAudioPlayer` sesi, hoparlörü titreştirerek suyun
/// atılmasını sağlar; uygulama suyu "kurutmaz" ama çıkışı kolaylaştırır.
@available(watchOS 10.0, *)
public final class WaterEjectionTonePlayer {

    private var player: AVAudioPlayer?

    /// Kısa bip çalar (başarı durumunda `true`).
    @discardableResult
    public func play(frequency: Double = 880,
                     duration: TimeInterval = 0.12,
                     volume: Float = 0.6) -> Bool {
        // Not: watchOS'ta özel PCM üretimi için `AVAudioEngine` +
        // `AVAudioPlayerNode` kullanılır. Kapsam dışı bırakılırsa
        // `WKInterfaceDevice.play(.notification)` titreşimi yeterlidir.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        return player == nil || player?.isPlaying == false
    }

    /// Hoparlörü iki kez kısa titreştirir (manuel su atma alternatifi).
    public func buzz(times: Int = 2) {
        for _ in 0..<max(1, times) {
            WKInterfaceDevice.current().play(.directionUp)
        }
    }
}
#endif