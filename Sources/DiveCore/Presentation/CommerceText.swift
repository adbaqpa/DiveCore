import Foundation

/// ADIM 1 — paywall ve uyarı metinleri (tek kaynak).
///
/// - Note: Kullanıcıya gösterilen **her** ticari metin burada toplanır;
///   görünümler yalnızca bu değerleri okur. Böylece metinler A/B
///   testine ve çeviriye hazır, kod ise metinlerden bağımsız olur.
public enum CommerceText {

    // MARK: - Kilit uyarıları

    /// Kilitli bir özelliğe tıklandığında gösterilen başlık.
    public static func lockedTitle(_ feature: FeatureKey) -> String {
        "\(feature.title) Pro'da"
    }

    /// Kilitli bir özelliğe tıklandığında gösterilen açıklama.
    public static func lockedMessage(_ feature: FeatureKey) -> String {
        feature.benefit
    }

    /// Kilitli dalış görüntülenmeye çalışıldığında.
    public static func hiddenDiveTitle(count: Int) -> String {
        count == 1 ? "1 eski dalış kilitli" : "\(count) eski dalış kilitli"
    }

    public static let hiddenDiveMessage = "Temel sürümde son \(ProductCatalog.freeTierLogLimit) dalış görüntülenebilir."

    // MARK: - Güvenlik

    public static let safetyNoticeShort = "Güvenlik özellikleri her zaman ücretsiz."
    public static let safetyNoticeLong = "Dekompresyon, alarm ve emniyet durakları "
        + "tüm sürümlerde ücretsizdir. Pro yalnızca analiz, ayar ve dışa aktarma "
        + "özelliklerini açar; hiçbir güvenlik hesabı kilitlenmez."

    // MARK: - Satın alma

    public static let purchase = "Satın Al"
    public static let restore = "Satın Alınanları Geri Yükle"
    public static let cancel = "Kapat"
    public static let terms = "Kullanım Koşulları ve Gizlilik Politikası"
    public static let loadingPrice = "Fiyat yükleniyor…"
    public static let loadingFailed = "Ürünler yüklenemedi. Bağlantınızı kontrol edin."

    public static func purchaseTitle(tier: DiveTier) -> String {
        tier == .lifetime ? "Ömür Boyu Satın Al" : "\(tier.title) Abonelik"
    }

    public static let subscriptionTerms = "Abonelik otomatik yenilenir. "
        + "Apple Hesabı Ayarları › Abonelikler'den iptal edebilirsiniz; iptal mevcut dönemin sonunda geçerlidir."

    public static let lifetimeTerms = "Tek seferlik ödemedir; yenilenmez ve iade edilmez."

    public static let noPurchaseFound = "Bu Apple hesabında bulunan bir satın alım yok."

    // MARK: - Yönetim

    public static let manageSubscription = "Aboneliği Yönet"
    public static let proActive = "DiveLog Pro etkin"
    public static let proAnnualActive = "Pro Yıllık etkin · yenileme \(ProductCatalog.annualIdentifier)"
    public static let proMonthlyActive = "Pro Aylık etkin"
    public static let lifetimeActive = "Ömür Boyu Pro"

    public static func expirationText(date: Date) -> String {
        "Yenilenir: " + DateFormatter.trShort.string(from: date)
    }

    // MARK: - Rozetler

    public static func proBadge(lockedCount: Int) -> String {
        lockedCount == 0 ? "Pro" : "+\(lockedCount)"
    }
}

/// Paywall'daki yasal metinler.
public enum LegalText {

    public static let termsAndPrivacy = """
    KULLANIM KOŞULLARI

    1. Kapsam. DiveLog bir eğitim ve referans amaçlı dalış bilgisayarıdır. \
    Gerçek dalışlarda kullanmadan önce üretici yazılımlarıyla ve deneyimli \
    bir eğitmenle çapraz doğrulayın.

    2. Güvenlik. Dekompresyon, alarm ve emniyet durakları tüm sürümlerde açıktır \
    ve satın alımla açılmaz. Su geçirmezlik, pil ömrü ve sensör doğruluğu cihazla \
    sınırlıdır.

    3. Abonelikler. Aylık ve yıllık abonelikler Apple Hesabınız üzerinden otomatik \
    yenilenir. İptal, mevcut dönemin sonunda yürürlüğe girer.

    4. Ömür boyu satın alım. Tek seferlik ödemedir, yenilenmez ve iade edilmez.

    5. Sorumluluk. Uygulama, üretici cihazlarının yerine geçmez. Kullanıcı, \
    dalış planlamasından ve güvenlik kararlarından kendisi sorumludur.

    GİZLİLİK POLİTİKASI

    Topladığımız veri. Dalış kayıtları (derinlik, süre, sıcaklık, gaz), \
    varsa GPS konumu ve tercih ayarları.

    Nerede saklanır. Tüm veriler yalnızca cihazınızda ve (varsa) Apple \
    iCloud gizli alanınızda saklanır. Sunucuya gönderim, analiz veya \
    reklam amaçlı üçüncü taraf erişimi yoktur.

    Nereleri okuruz. Konum, hareket ve Apple Health verileri yalnızca \
    sizin etkinleştirdiğiniz özellikler için ve cihazınızda işlenir.

    Kontrolünüz. Ayarlar bölümünden tüm verileri silebilir, dışa aktarabilir \
    veya iCloud senkronizasyonunu kapatabilirsiniz.
    """
}

// MARK: - Yardımcı biçimlendiriciler

extension DateFormatter {
    /// Kısa Türkçe tarih (ayarlar ekranı için).
    public static let trShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
}
