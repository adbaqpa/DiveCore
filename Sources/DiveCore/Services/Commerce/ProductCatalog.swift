import Foundation

/// ADIM 1 — App Store ürün kataloğu.
///
/// ## Ürün kimlikleri (App Store Connect'te **birebir** aynı olmalı)
/// - `com.divelog.pro.monthly`
/// - `com.divelog.pro.annual`
/// - `com.divelog.pro.lifetime`
///
/// Abonelikler bir abonelik grubuna (`DiveLog Pro`) ait olmalıdır; yaşam
/// boyu satın alım aynı grupta tanımlanır ve StoreKit bunu
/// "non-renewing subscription" olarak işaretler.
///
/// ## Neden çekirdekte?
/// Ürün kimlikleri görünüm katmanında dağınık hâlde bulunursa
/// (paywall, ayarlar, hata mesajları) bir gün biri unutulur. Tek kaynak
/// burada; StoreKit servisi ve paywall yalnızca bu kataloğu okur.
public enum ProductCatalog {

    /// Bundle kimlikleri (AppDistribution ile hizalı).
    private static var bundleID: String { AppDistribution.BundleID.iOSApp }

    // MARK: - Ürün kimlikleri

    public static let monthlyIdentifier = "com.divelog.pro.monthly"
    public static let annualIdentifier = "com.divelog.pro.annual"
    public static let lifetimeIdentifier = "com.divelog.pro.lifetime"

    /// Abonelik grubu adı (App Store Connect'te tanımlanır).
    public static let subscriptionGroupName = "DiveLog Pro"

    /// Tüm abonelik ürünleri.
    public static let subscriptionIdentifiers: [String] = [
        monthlyIdentifier, annualIdentifier
    ]

    /// Tüm ürünler.
    public static let allIdentifiers: [String] = [
        monthlyIdentifier, annualIdentifier, lifetimeIdentifier
    ]

    // MARK: - Kapsam eşlemesi

    /// Ürün kimliği → kapsam.
    public static func tier(for identifier: String) -> DiveTier? {
        switch identifier {
        case monthlyIdentifier: return .proMonthly
        case annualIdentifier: return .proAnnual
        case lifetimeIdentifier: return .lifetime
        default: return nil
        }
    }

    /// Kapsam → ürün kimliği.
    public static func identifier(for tier: DiveTier) -> String? {
        switch tier {
        case .free: return nil
        case .proMonthly: return monthlyIdentifier
        case .proAnnual: return annualIdentifier
        case .lifetime: return lifetimeIdentifier
        }
    }

    /// Ürün kimliği geçerli mi (uygulamanın tanıdığı bir ürün mü)?
    public static func isKnownProduct(_ identifier: String) -> Bool {
        allIdentifiers.contains(identifier)
    }

    // MARK: - Sunum (yerel, StoreKit'ten bağımsız)

    /// Ürünün gösterim bilgisi.
    public struct Offering: Equatable, Sendable, Identifiable {
        public let tier: DiveTier
        public let productIdentifier: String
        public let title: String
        public let subtitle: String
        public let badge: String?
        /// Yıllık abonelikte aylık maliyet karşılığı (yerel para biriminde)
        public let equivalentMonthlyPrice: String?
        public let features: [FeatureKey]
        /// Bu teklif vurgulanmalı mı (en iyi değer / önerilen)
        public var isRecommended: Bool

        public var id: String { productIdentifier }

        public init(tier: DiveTier,
                    productIdentifier: String,
                    title: String,
                    subtitle: String,
                    badge: String?,
                    equivalentMonthlyPrice: String?,
                    features: [FeatureKey],
                    isRecommended: Bool) {
            self.tier = tier
            self.productIdentifier = productIdentifier
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.equivalentMonthlyPrice = equivalentMonthlyPrice
            self.features = features
            self.isRecommended = isRecommended
        }
    }

    /// Paywall'da gösterilecek teklifler.
    ///
    /// - Parameter isRecommendedAnnual: Yıllık abonelik vurgulanacak mı?
    ///   Apple, daha yüksek dönüşüm için yıllığı önermemizi destekler
    ///   (abonelik gelirinin ~%50'si yıllıktan gelir).
    public static func offerings(isRecommendedAnnual: Bool = true) -> [Offering] {
        [
            Offering(tier: .proMonthly,
                     productIdentifier: monthlyIdentifier,
                     title: "Aylık",
                     subtitle: "Her ay yenilenir, istediğiniz an iptal edin",
                     badge: nil,
                     equivalentMonthlyPrice: nil,
                     features: FeatureKey.allCases,
                     isRecommended: false),
            Offering(tier: .proAnnual,
                     productIdentifier: annualIdentifier,
                     title: "Yıllık",
                     subtitle: "Yılda bir ödeme",
                     badge: "EN İYİ DEĞER",
                     equivalentMonthlyPrice: "≈ %67 tasarruf",
                     features: FeatureKey.allCases,
                     isRecommended: isRecommendedAnnual),
            Offering(tier: .lifetime,
                     productIdentifier: lifetimeIdentifier,
                     title: "Ömür Boyu",
                     subtitle: "Tek ödeme, hiç yenilenmez",
                     badge: "BİR KEZ ÖDE",
                     equivalentMonthlyPrice: nil,
                     features: FeatureKey.allCases,
                     isRecommended: !isRecommendedAnnual)
        ]
    }

    /// Önerilen teklif (paywall'da vurgulanan).
    public static func recommendedOffering(
        isRecommendedAnnual: Bool = true) -> Offering {
        offerings(isRecommendedAnnual: isRecommendedAnnual)
            .first { $0.isRecommended }
            ?? offerings(isRecommendedAnnual: false)[1]
    }

    // MARK: - Kilit metinleri

    /// Bir özellik kilitliyken gösterilecek kısa gerekçe.
    public static func lockReason(for feature: FeatureKey) -> String {
        "\(feature.title) Pro özelliğidir."
    }

    /// Kilitli özellik sayısı (badge için).
    public static func lockedCount(in tier: DiveTier) -> Int {
        FeatureKey.allCases.filter { $0.isLocked(in: tier) }.count
    }

    // MARK: - Kilit durumunu sınırlara uygulama

    /// Temel sürümde görüntülenebilecek en fazla dalış sayısı.
    ///
    /// - Note: Kullanıcı "sınırlı log kaydı, maksimum son 3 dalış" dediği
    ///   için 3. **Veri silinmez**; yalnızca arayüzde gösterilmez. Böylece
    ///   kullanıcı Pro'ya yükselince tüm geçmişi anında erişir.
    public static let freeTierLogLimit = 3

    /// Görüntülenebilir dalışlar (sınır uygulanmış).
    public static func visibleDives<T>(_ dives: [T], tier: DiveTier) -> ArraySlice<T> {
        let limit = tier.unlocksPro ? dives.count : freeTierLogLimit
        return dives.prefix(max(0, limit))
    }

    /// Kullanıcı bu dalışı görebilir mi?
    public static func canViewDive(at index: Int, tier: DiveTier) -> Bool {
        tier.unlocksPro || index < freeTierLogLimit
    }

    /// Kilitli dalış sayısı (paywall metni için).
    public static func hiddenDiveCount(total: Int, tier: DiveTier) -> Int {
        guard !tier.unlocksPro else { return 0 }
        return max(0, total - freeTierLogLimit)
    }
}
