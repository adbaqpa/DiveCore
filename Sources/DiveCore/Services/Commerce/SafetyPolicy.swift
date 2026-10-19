import Foundation

/// ADIM 1 — **güvenlik kabiliyetleri**.
///
/// ## Neden ayrı bir liste?
/// Monetizasyon bir dalış bilgisayarında çok hassas bir konudur: deko
/// hesabı, alarm veya emniyet durağı kilitlenirse uygulama **tehlikeli**
/// hâle gelir ve App Store incelemesinde "güvenlik özelliği ücretli"
/// gerekçesiyle reddedilir. Bu yüzden güvenlik kabiliyetleri
/// `FeatureKey` listesinde **bulunmaz**; bunun yerine burada ayrı bir
/// enum olarak tanımlanır ve `SafetyPolicy` tarafından her zaman açık
/// olduğu doğrulanır.
///
/// `FeatureKey` listesiyle kesişim **testlerle yasaktır**: yeni bir
/// kilitlenebilir özellik eklerken yanlışlıkla bir güvenlik kabiliyetini
/// kapsama almak derhal yakalanır.
public enum SafetyCapability: String, CaseIterable, Codable, Sendable {
    // MARK: Canlı ölçüm
    /// Anlık derinlik (sensörden)
    case liveDepth
    /// Dalış süresi
    case diveTime
    /// Maksimum derinlik
    case maxDepth
    /// Ortalama derinlik
    case averageDepth
    /// Sıcaklık
    case temperature
    /// Yükseliş/iniş hızı
    case ascentRate
    /// Pusola yönü
    case heading

    // MARK: Dekompresyon (çekirdek)
    /// NDL (kalan dekompresyon limitsiz süre)
    case noDecompressionLimit
    /// Tavan (ceiling)
    case ceiling
    /// Zorunlu deko durakları
    case decoStops
    /// Yüzeye çıkış süresi (TTS)
    case timeToSurface
    /// GF99
    case gf99
    /// Doku/gaz yükü takibi
    case tissueLoading
    /// Uçuş yasağı hesabı (güvenlikle ilgili)
    case noFlyTime
    /// Emniyet durağı (5 m / 3 dk)
    case safetyStop
    /// Gerçekçi hız sınırları ve yasak profiller
    case speedLimits

    // MARK: Alarm ve acil durum
    /// Hızlı çıkış alarmı
    case ascentRateAlarm
    /// Tavan ihlali alarmı
    case ceilingAlarm
    /// NDL uyarısı
    case ndlWarning
    /// Oksijen (PO₂/CNS/OTU) uyarıları
    case oxygenWarnings
    /// MOD uyarısı
    case modWarning
    /// Acil durum menüsü (güvenli çıkış rehberi)
    case emergencyMenu
    /// Çıkış rehberi (AscentAdvisor)
    case ascentAdvisor

    // MARK: Cihaz güvenliği
    /// Su kilidi ve su atma
    case waterLock
    /// Action Button acil durum tetiği
    case emergencyActionButton
    /// Konum/güneş referansı (dalış bilgisayarı temel çalışma gereksinimi)
    case diveComputerCore

    // MARK: Veri bütünlüğü
    /// Dalışı **kaydetme** (kayıt silinmez; yalnızca erişim sınırlanır)
    case saveDiveLog
    /// Aktif dalışın görüntülenmesi
    case viewActiveDive

    /// Kullanıcıya gösterilen ad.
    public var title: String {
        switch self {
        case .liveDepth: return "Anlık derinlik"
        case .diveTime: return "Dalış süresi"
        case .maxDepth: return "Maksimum derinlik"
        case .averageDepth: return "Ortalama derinlik"
        case .temperature: return "Su sıcaklığı"
        case .ascentRate: return "Yükseliş hızı"
        case .heading: return "Pusola"
        case .noDecompressionLimit: return "NDL"
        case .ceiling: return "Deko tavanı"
        case .decoStops: return "Deko durakları"
        case .timeToSurface: return "Yüzeye çıkış süresi"
        case .gf99: return "GF99"
        case .tissueLoading: return "Gaz yükü takibi"
        case .noFlyTime: return "Uçuş yasağı"
        case .safetyStop: return "Emniyet durağı"
        case .speedLimits: return "Hız sınırları"
        case .ascentRateAlarm: return "Hızlı çıkış alarmı"
        case .ceilingAlarm: return "Tavan ihlali alarmı"
        case .ndlWarning: return "NDL uyarısı"
        case .oxygenWarnings: return "Oksijen uyarıları"
        case .modWarning: return "MOD uyarısı"
        case .emergencyMenu: return "Acil durum menüsü"
        case .ascentAdvisor: return "Çıkış rehberi"
        case .waterLock: return "Su kilidi"
        case .emergencyActionButton: return "Acil durum butonu"
        case .diveComputerCore: return "Dalış bilgisayarı çekirdeği"
        case .saveDiveLog: return "Dalış kaydı"
        case .viewActiveDive: return "Aktif dalış görünümü"
        }
    }

    /// Kullanıcıya gösterilecek açıklama (ayarlarda "her zaman ücretsiz").
    public var explanation: String {
        "Dalış güvenliği özelliği — her kapsamda açıktır."
    }
}

/// Güvenlik politikası: kabiliyet → açık mı.
///
/// - Note: Bu tür bilinçli olarak **tabloyu boş bırakmayan** bir politika
///   sınıfıdır: `isAvailable(_:)` her zaman `true` döner. Böylece
///   "bir gün bu kabiliyeti kilitleyeyim" düşüncesi kodu değiştirmek
///   zorunda kalır ve `SafetyPolicyTests` bunu yakalar.
public enum SafetyPolicy {

    /// Kabiliyet kullanılabilir mi? **Her zaman `true`.**
    public static func isAvailable(_ capability: SafetyCapability) -> Bool {
        true
    }

    /// Kilitli güvenlik kabiliyeti var mı? **Her zaman `false`.**
    public static func isLocked(_ capability: SafetyCapability) -> Bool { false }

    /// Ücretsiz kapsamda açık olan kabiliyetler.
    public static var capabilitiesAvailableInFreeTier: [SafetyCapability] {
        SafetyCapability.allCases
    }

    /// Güvenlik kabiliyetlerinin başlıkları (ayarlarda listeleme).
    public static var alwaysFreeSummary: String {
        let count = SafetyCapability.allCases.count
        return "\(count) güvenlik özelliği tüm sürümlerde açık"
    }
}

// MARK: - FeatureGate entegrasyonu

extension FeatureGate {

    /// Güvenlik kabiliyeti kullanılabilir mi? (her zaman `true`)
    public func canPerform(_ capability: SafetyCapability) -> Bool {
        SafetyPolicy.isAvailable(capability)
    }

    /// Güvenlik kabiliyeti kilitli mi? (her zaman `false`)
    public func isSafetyCapabilityLocked(_ capability: SafetyCapability) -> Bool {
        SafetyPolicy.isLocked(capability)
    }

    /// Temel sürümde de açık olan güvenlik kabiliyetleri.
    public var freeSafetyCapabilities: [SafetyCapability] {
        SafetyPolicy.capabilitiesAvailableInFreeTier
    }

    /// Bu kapsamda **kaç** güvenlik kabiliyeti kilitli? (her zaman 0)
    public var lockedSafetyCapabilityCount: Int {
        SafetyCapability.allCases.filter { isSafetyCapabilityLocked($0) }.count
    }
}
