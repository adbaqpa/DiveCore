import Foundation

/// ADIM 1 — kapsam (tier) tanımları.
///
/// ## Güvenlik ilkesi (değiştirilemez)
/// Dekompresyon motoru, NDL/tavan hesabı, güvenlik alarmları, deko durakları
/// ve acil durum menüsü **hiçbir kapsamda** kilitlenmez. Kilitlenen şey
/// yalnızca *analiz*, *konfor* ve *entegrasyon* özellikleridir: geçmiş
/// günlük, gelişmiş ayarlar, çoklu gaz, harita ve dışa aktarma.
///
/// Bu ilke `FeatureKey.isSafetyCritical` ile kod düzeyinde tanımlı ve
/// `CommerceSafetyTests` ile doğrulanır; bir özellik yanlışlıkla Pro
/// işaretlenirse testler kızar.
public enum DiveTier: String, Equatable, Codable, Sendable, CaseIterable {
    /// Temel sürüm — güvenlik özelliklerinin tamamı, sınırlı günlük
    case free
    /// Aylık/yıllık abonelik
    case proMonthly
    /// Yıllık abonelik
    case proAnnual
    /// Tek seferlik ömür boyu kilit açma
    case lifetime

    /// Kullanıcıya gösterilen ad.
    public var title: String {
        switch self {
        case .free: return "Temel"
        case .proMonthly: return "Pro Aylık"
        case .proAnnual: return "Pro Yıllık"
        case .lifetime: return "Ömür Boyu"
        }
    }

    /// Kısa açıklama.
    public var detail: String {
        switch self {
        case .free: return "Anlık derinlik, süre ve güvenlik alarmları"
        case .proMonthly: return "Sınırsız günlük, gelişmiş ayarlar, dışa aktarma"
        case .proAnnual: return "Pro özellikler, yılda bir ödeme ile"
        case .lifetime: return "Tüm Pro özellikler, tek seferlik ödeme"
        }
    }

    /// Bu kapsam tüm Pro özellikleri açar mı?
    ///
    /// - Note: Aylık ve yıllık abonelik aynı özellik setini açar; fark
    ///   yalnızca fiyatta ve yenileme süresinde.
    public var unlocksPro: Bool {
        switch self {
        case .free: return false
        case .proMonthly, .proAnnual, .lifetime: return true
        }
    }

    /// Abonelik mi?
    public var isSubscription: Bool {
        self == .proMonthly || self == .proAnnual
    }

    /// Kapsam sırası — "en az bu kadar yetki" anlamına gelir.
    /// Ömür boyu abonelikten daha üstündür çünkü yenilenmez.

    /// Kapsam sırası (karşılaştırma için).
    ///
    /// - Note: Aylık ve yıllık **aynı** özellik setini açar; bu yüzden
    ///   sıraları eşittir ve yalnızca yenileme aralığı farklıdır.
    public var rank: Int {
        switch self {
        case .free: return 0
        case .proMonthly, .proAnnual: return 1
        case .lifetime: return 2
        }
    }
}

/// Kilitlenebilir özellikler.
///
/// - Important: `case` listesi **güvenlik** sınıfını bilinçli olarak içermez.
public enum FeatureKey: String, Equatable, Codable, Sendable, CaseIterable, Identifiable {

    public var id: String { rawValue }
    // MARK: Analiz / günlük
    /// Sınırsız günlük geçmişi (Temel'de son 3 dalış)
    case unlimitedLogHistory
    /// Uzun dönem istatistikler (aylık toplamlar, trendler)
    case longTermStatistics
    /// Geçmiş dalış profil grafiği
    case profileCharts

    // MARK: Ayarlar
    /// Gelişmiş Bühlmann Gradient Factors ayarları
    case advancedGradientFactors
    /// Özel GF kaydırıcıları
    case customGradientFactors

    // MARK: Gaz
    /// Çoklu gaz / Nitrox desteği
    case nitroxSupport
    /// Çoklu silindir ve gaz değişim tablosu
    case multiCylinder

    // MARK: Derin durak
    /// GUE tarzı yuvarlanmış derin duraklar
    case deepStops

    // MARK: iPhone eşlikçisi
    /// GPS rota haritası
    case companionMap
    /// UDDF/FIT/JSON dışa aktarma
    case dataExport

    // MARK: Planlama
    /// Tekrar dalış hesaplayıcısı
    case repetitiveDiveCalculator
    /// Kabin basıncına göre uçuş yasağı senaryoları
    case flightPlanning

    // MARK: Komplikasyon
    /// Yüzey aralığı / uçuş yasağı komplikasyonları
    case surfaceComplications

    /// Bu özellik **güvenlik açısından kritik** mi?
    ///
    /// - Note: `true` dönen hiçbir özellik kilitlenmez. Dekompresyon, alarm,
    ///   NDL, emniyet durağı ve acil durum bu listede **yoktur** ve
    ///   eklenmemelidir.
    public var isSafetyCritical: Bool { false }

    /// Bu özellik hangi kapsamı gerektirir?
    public var requiredTier: DiveTier { .proMonthly }

    /// Kullanıcıya gösterilen başlık (paywall satırı).
    public var title: String {
        switch self {
        case .unlimitedLogHistory: return "Sınırsız dalış günlüğü"
        case .longTermStatistics: return "Uzun dönem istatistikler"
        case .profileCharts: return "Dalış profili grafikleri"
        case .advancedGradientFactors: return "Gelişmiş GF ayarları"
        case .customGradientFactors: return "Özel GF değerleri"
        case .nitroxSupport: return "Nitrox ve çoklu gaz"
        case .multiCylinder: return "Çoklu silindir planı"
        case .deepStops: return "Yuvarlanmış derin duraklar"
        case .companionMap: return "GPS rota haritası"
        case .dataExport: return "UDDF / FIT dışa aktarma"
        case .repetitiveDiveCalculator: return "Tekrar dalış hesaplayıcısı"
        case .flightPlanning: return "Uçuş planlama senaryoları"
        case .surfaceComplications: return "Yüzey aralığı komplikasyonu"
        }
    }

    /// Kısa fayda metni (paywall satırı).
    public var benefit: String {
        switch self {
        case .unlimitedLogHistory:
            return "Son 3 dalışla sınırlı kalmayın; tüm geçmişinize erişin."
        case .longTermStatistics:
            return "Aylık toplamlar, trendler ve kişisel rekorlarınız."
        case .profileCharts:
            return "Her dalışın derinlik-zaman profilini inceleyin."
        case .advancedGradientFactors:
            return "Bühlmann GF ön ayarları: konservatiften teknike kadar 6 seçenek."
        case .customGradientFactors:
            return "Kendi GF Low/High değerlerinizi kaydedin."
        case .nitroxSupport:
            return "EAN %22–40, MOD uyarısı ve gaz değişim planı."
        case .multiCylinder:
            return "Birden fazla silindir ve her derinlikte doğru gaz."
        case .deepStops:
            return "GÜE tarzı yuvarlanmış derin duraklar."
        case .companionMap:
            return "iPhone'da GPS rotanızı haritada görün."
        case .dataExport:
            return "UDDF ve FIT ile Subsurface, Garmin ve Strava'ya aktarın."
        case .repetitiveDiveCalculator:
            return "Artık gaz yüküyle bir sonraki dalışınızı önceden hesaplayın."
        case .flightPlanning:
            return "Kabin basıncına göre gerçekçi uçuş yasağı süresi."
        case .surfaceComplications:
            return "Saat yüzünde son yüzey aralığı ve uçuş yasağı geri sayımı."
        }
    }

    /// Simge adı (SF Symbol).
    public var symbolName: String {
        switch self {
        case .unlimitedLogHistory: return "clock.arrow.circlepath"
        case .longTermStatistics: return "chart.line.uptrend.xyaxis"
        case .profileCharts: return "waveform.path.ecg"
        case .advancedGradientFactors, .customGradientFactors: return "dial.medium"
        case .nitroxSupport, .multiCylinder: return "cylinder"
        case .deepStops: return "arrow.down.to.line"
        case .companionMap: return "map"
        case .dataExport: return "square.and.arrow.up"
        case .repetitiveDiveCalculator: return "arrow.triangle.2.circlepath"
        case .flightPlanning: return "airplane"
        case .surfaceComplications: return "clock.badge.checkmark"
        }
    }

    /// Özellik aileleri (paywall'da gruplama).
    public enum Group: String, CaseIterable, Sendable {
        case analytics = "Günlük ve Analiz"
        case settings = "Ayarlar"
        case gases = "Gaz Planı"
        case planning = "Planlama"
        case companion = "iPhone Eşlikçisi"
    }

    /// Bu özelliğin ait olduğu aile.
    public var group: Group {
        switch self {
        case .unlimitedLogHistory, .longTermStatistics, .profileCharts:
            return .analytics
        case .advancedGradientFactors, .customGradientFactors, .deepStops:
            return .settings
        case .nitroxSupport, .multiCylinder:
            return .gases
        case .repetitiveDiveCalculator, .flightPlanning, .surfaceComplications:
            return .planning
        case .companionMap, .dataExport:
            return .companion
        }
    }

    /// Temel sürümde bu özellik **kısıtlı** mı (kilitli mi)?
    public func isLocked(in tier: DiveTier) -> Bool {
        // Güvenlik özellikleri hiçbir zaman kilitli değildir.
        guard !isSafetyCritical else { return false }
        return !tier.unlocksPro
    }

    /// Aileye göre kilitli özellikler.
    public static func lockedFeatures(in tier: DiveTier,
                                     group: Group) -> [FeatureKey] {
        allCases.filter { $0.group == group && $0.isLocked(in: tier) }
    }
}

/// Kullanıcının sahip olduğu yetkiler.
///
/// - Note: `lifetime` bir "süre sınırsız" yetkidir; abonelikler `expiration`
///   taşır. Yetkiler cihazda ve iCloud gizli alanında saklanır, sunucu yoktur.
public struct EntitlementSet: Equatable, Codable, Sendable {
    /// Aktif abonelik bitiş tarihi (yoksa süresiz varsayılır)
    public var expiration: Date?
    /// Ömür boyu kilit açıldı mı?
    public var hasLifetimeUnlock: Bool
    /// Hangi ürünler etkin (StoreKit 2 ürün kimlikleri)
    public var activeProductIdentifiers: Set<String>
    /// Doğrulama tarihi (saatlik yenilemede güncellenir)
    public var lastVerified: Date?

    public init(expiration: Date? = nil,
                hasLifetimeUnlock: Bool = false,
                activeProductIdentifiers: Set<String> = [],
                lastVerified: Date? = nil) {
        self.expiration = expiration
        self.hasLifetimeUnlock = hasLifetimeUnlock
        self.activeProductIdentifiers = activeProductIdentifiers
        self.lastVerified = lastVerified
    }

    /// Hiçbir şey satın alınmamış.
    public static let none = EntitlementSet()

    /// Boş yetki kümesi mi?
    public var isEmpty: Bool {
        !hasLifetimeUnlock && expiration == nil && activeProductIdentifiers.isEmpty
    }

    /// `date` anında geçerli kapsam (yoksa `.free`).
    ///
    /// - Parameter gracePeriodDays: Yenilenememe (ödeme yöntemi geçersiz)
    ///   durumunda kullanıcıya tanınan süre. Apple'ın önerdiği şekilde
    ///   kullanıcıyı aniden kilitlememek için 7 gün.
    public func tier(at date: Date = Date(), gracePeriodDays: Int = 7) -> DiveTier {
        if hasLifetimeUnlock { return .lifetime }
        guard let expiration else { return .free }

        // Abonelik henüz bitmemiş
        if expiration > date { return .proMonthly }

        // Süre geçmiş ama **tolerans** penceresi içindeyiz.
        //
        // Apple'ın kabul ettiği davranış: ödeme yöntemi geçersiz olduğunda
        // veya yalnızca yıllık aboneliklerde bildirim gecikmesi yaşandığında
        // kullanıcı aniden erişim kaybetmemelidir. Bu süre içinde Pro açık
        // kalır, sonra Temel'e düşer.
        let graceEnd = expiration.addingTimeInterval(Double(gracePeriodDays) * 24 * 3600)
        if date < graceEnd { return .proMonthly }

        return .free
    }

    /// Yıllık abonelik mi (yenileme aralığı bilgisi)?
    public func isAnnual(at date: Date = Date()) -> Bool {
        guard !hasLifetimeUnlock, expiration != nil, expiration! > date else { return false }
        return activeProductIdentifiers.contains(ProductCatalog.annualIdentifier)
    }

    /// Yenileme (otomatik yenileme) açık mı?
    public var isAutoRenewable: Bool { !hasLifetimeUnlock && expiration != nil }

    /// Satın alınmış bir şey var mı (serileştirilmesi gereken)?
    public var hasAnyPurchase: Bool { !isEmpty }
}

extension EntitlementSet {

    /// StoreKit durumundan yetki kümesi üretir (saf fonksiyon — test edilebilir).
    ///
    /// - Parameters:
    ///   - transactionIDs: Etkin işlem kimlikleri
    ///   - expiration: Abonelik bitiş tarihi
    ///   - now: Değerlendirme anı
    public static func make(transactionIDs: Set<String>,
                            expiration: Date?,
                            now: Date = Date()) -> EntitlementSet {
        let lifetime = transactionIDs.contains(ProductCatalog.lifetimeIdentifier)
        let subscriptionActive = transactionIDs.contains {
            $0 == ProductCatalog.monthlyIdentifier || $0 == ProductCatalog.annualIdentifier
        }
        return EntitlementSet(
            expiration: subscriptionActive ? expiration : nil,
            hasLifetimeUnlock: lifetime,
            activeProductIdentifiers: transactionIDs,
            lastVerified: now)
    }
}
