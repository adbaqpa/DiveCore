import Foundation

/// Alarm türü — hem dokunsal hem görsel geri bildirimi tanımlar.
public enum AlarmKind: String, Equatable, Codable, Sendable {
    /// Bilgi (ör. gaz değişimi)
    case info
    /// Dikkat (ör. yavaşlayan çıkış)
    case caution
    /// Uyarı (ör. NDL doldu, CNS %80)
    case warning
    /// Kritik (ör. hızlı çıkış, tavan ihlali)
    case critical
}

/// Bir alarmın çalışma anında ürettiği eylem.
public struct AlarmAction: Equatable, Codable, Sendable, Identifiable {

    /// Dokunsal geri bildirim tipi (WatchKit/WKInterfaceDevice.play ile eşleşir).
    public enum HapticFeedback: String, Equatable, Codable, Sendable {
        case none
        /// `.notification` — nazik, bilgilendirici
        case notification
        /// `.directionUp` / `.directionDown` — yönlendirilmiş (opsiyonel)
        case directional
        /// `.success` — onay
        case success
        /// `.failure` / `.retry` — kritik uyarı
        case critical
        /// Sürekli titreşim (kritik, ekran kırmızıyken)
        case repeated
    }

    /// Görsel yoğunluk seviyesi — ADIM 3 UI'ı bunu kullanacak.
    public enum VisualLevel: String, Equatable, Codable, Sendable {
        case none
        case subtle
        case prominent
        case fullScreenAlert
    }

    public let id: UUID
    public let kind: AlarmKind
    public let feedback: HapticFeedback
    public let visualLevel: VisualLevel
    public let message: String
    /// Aynı alarmın tekrar ne kadar süre sonra çalınabileceği (saniye)
    public let repeatAfter: TimeInterval
    /// Bu alarmın hangi uyarıdan geldiği
    public let sourceWarning: DiveWarning.Kind?

    public init(id: UUID = UUID(),
                kind: AlarmKind,
                feedback: HapticFeedback,
                visualLevel: VisualLevel,
                message: String,
                repeatAfter: TimeInterval = 0,
                sourceWarning: DiveWarning.Kind? = nil) {
        self.id = id
        self.kind = kind
        self.feedback = feedback
        self.visualLevel = visualLevel
        self.message = message
        self.repeatAfter = repeatAfter
        self.sourceWarning = sourceWarning
    }
}

/// Alarm politikası: uyarıları dokunsal/görsel geri bildirime dönüştürür.
///
/// Saf fonksiyoneldir — `WatchKit`'e bağımlı değildir; bu sayede ADIM 3'teki
/// ekran mantığı ve ADIM 2'deki titreşim aynı testlerle doğrulanır.
public struct AlarmCoordinator: Sendable {

    /// Aynı alarm türünün tekrar çalma beklemesi (saniye)
    public var cooldown: TimeInterval
    /// Kritik alarmlarda tam ekran uyarısı açılsın mı?
    public var fullScreenAlertsEnabled: Bool
    /// Sadece görsel (sessiz) mod — kullanıcı ayarı
    public var silentMode: Bool

    private var lastFiredAt: [DiveWarning.Kind: TimeInterval] = [:]
    private var activeCritical = false

    public init(cooldown: TimeInterval = 10,
                fullScreenAlertsEnabled: Bool = true,
                silentMode: Bool = false) {
        self.cooldown = cooldown
        self.fullScreenAlertsEnabled = fullScreenAlertsEnabled
        self.silentMode = silentMode
    }

    /// Uyarı listesini değerlendirip çalınacak alarmları döndürür.
    ///
    /// - Parameters:
    ///   - warnings: Durumdan üretilen uyarılar (kritik olanlar önce gelmeli)
    ///   - elapsed: Dalış başlangıcından geçen süre (saniye)
    public mutating func actions(for warnings: [DiveWarning],
                                 elapsed: TimeInterval) -> [AlarmAction] {
        var result: [AlarmAction] = []

        for warning in warnings.sorted(by: { $0.severity > $1.severity }) {
            guard shouldFire(warning, elapsed: elapsed) else { continue }
            lastFiredAt[warning.kind] = elapsed

            let (feedback, visual) = AlarmCoordinator.policy(for: warning.severity,
                                                              silent: silentMode,
                                                              fullScreen: fullScreenAlertsEnabled)
            result.append(AlarmAction(
                kind: AlarmCoordinator.kind(for: warning.severity),
                feedback: feedback,
                visualLevel: visual,
                message: warning.message,
                repeatAfter: AlarmCoordinator.repeatInterval(for: warning.severity),
                sourceWarning: warning.kind))
        }

        // Kritik durumun devam ettiğini izle (ekranın kırmızı kalması için)
        activeCritical = warnings.contains { $0.severity == .critical }
        return result
    }

    private func shouldFire(_ warning: DiveWarning, elapsed: TimeInterval) -> Bool {
        guard let last = lastFiredAt[warning.kind] else { return true }
        return elapsed - last >= cooldown
    }

    /// Yeni dalışta alarm geçmişini temizler.
    public mutating func reset() {
        lastFiredAt.removeAll()
        activeCritical = false
    }

    /// Şu anda kritik alarm durumu sürüyor mu? (ekran rengi için)
    public var isCriticalActive: Bool { activeCritical }

    // MARK: - Politika

    static func policy(for severity: DiveWarning.Severity,
                       silent: Bool,
                       fullScreen: Bool) -> (AlarmAction.HapticFeedback, AlarmAction.VisualLevel) {
        if silent {
            switch severity {
            case .info: return (.none, .none)
            case .caution: return (.none, .subtle)
            case .warning: return (.none, .prominent)
            case .critical: return (.none, fullScreen ? .fullScreenAlert : .prominent)
            }
        }
        switch severity {
        case .info: return (.notification, .none)
        case .caution: return (.notification, .subtle)
        case .warning: return (.notification, .prominent)
        case .critical: return (.critical, fullScreen ? .fullScreenAlert : .prominent)
        }
    }

    static func repeatInterval(for severity: DiveWarning.Severity) -> TimeInterval {
        switch severity {
        case .info: return 0
        case .caution: return 30
        case .warning: return 20
        case .critical: return 6      // hızlı çıkış sırasında tekrar tekrar uyar
        }
    }

    static func kind(for severity: DiveWarning.Severity) -> AlarmKind {
        switch severity {
        case .info: return .info
        case .caution: return .caution
        case .warning: return .warning
        case .critical: return .critical
        }
    }
}

/// Dokunsal geri bildirimi uygular.
///
/// watchOS'ta `WatchHapticEngine` bu protokolü uygular ve
/// `WKInterfaceDevice.current().play(...)` çağırır. Çekirdek modül bu arayüzü
/// tanımlar; testlerde sahte (mock) motor kullanılır.
@MainActor
public protocol HapticEngine: AnyObject {
    /// Alarm listesini uygular (uygulama kararı bu katmanda verilir).
    func perform(_ actions: [AlarmAction])
    /// Kullanıcı dokunduğunda kısa onay tıkırtısı.
    func tapFeedback()
    /// Alarmı susturur (kullanıcı onayladı).
    func acknowledge()
}

/// Testlerde kullanılan sahte motor — çağrıları kaydeder.
@MainActor
public final class RecordingHapticEngine: HapticEngine {

    public init() {}

    public private(set) var performed: [AlarmAction] = []
    public private(set) var tapCount = 0
    public private(set) var acknowledgeCount = 0

    /// Toplam dokunsal geri bildirim sayısı
    public var totalFeedbackCount: Int {
        performed.filter { $0.feedback != .none }.count
    }

    public func perform(_ actions: [AlarmAction]) {
        performed.append(contentsOf: actions)
    }

    public func tapFeedback() { tapCount += 1 }
    public func acknowledge() { acknowledgeCount += 1 }

    public func reset() {
        performed.removeAll()
        tapCount = 0
        acknowledgeCount = 0
    }
}