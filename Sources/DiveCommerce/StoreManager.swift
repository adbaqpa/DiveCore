#if canImport(StoreKit) && (os(iOS) || os(watchOS))
import Foundation
import StoreKit
import DiveCore

/// ADIM 1 — **StoreKit 2** satın alma servisi.
///
/// ## Tasarım
///
/// 1. **Tek doğruluk kaynağı** — yetkiler yalnızca StoreKit işlemlerinden
///    (`Transaction.currentEntitlements`) türetilir. Uygulama içinde
///    "satın alındı" bayrağı tutulmaz; bu, iptal/iptal dönüşü ve yenileme
///    hatalarında "hayalet Pro" durumunu ortadan kaldırır.
/// 2. **Çevrimdışı dayanıklılık** — işlemler `Transaction` ile imzalıdır;
///    bağlantı yoksa `entitlements` boş döner, **hata fırlatmaz**.
/// 3. **Dinleme** — `Transaction.updates` ve `Transaction.currentEntitlements`
///    dinlenir; yenileme/iptal anında UI kendiliğinden güncellenir.
/// 4. **Güvenlik ayrımı** — bu servis `FeatureGate`'i besler, tersi değil.
///    `SafetyPolicy` bu servise hiç dokunmaz.
///
/// ## Thread güvenliği
/// `@MainActor` işaretlidir; tüm StoreKit yüzeyleri ana aktörde çalışır.
@MainActor
@Observable
public final class StoreManager {

    // MARK: - Durum

    /// Ürünlerin yüklenip yüklenmediği.
    public private(set) var isLoadingProducts = false
    /// Satın alma işlemi sürüyor mu.
    public private(set) var isPurchasing: Bool = false
    /// Yenileme işlemi sürüyor mu.
    public private(set) var isRestoring: Bool = false
    /// Ürün hatası.
    public private(set) var errorMessage: String?

    /// StoreKit'ten gelen ürünler.
    public private(set) var products: [String: Product] = [:]
    /// Etkin yetkiler.
    public private(set) var entitlements: EntitlementSet = .none

    /// Dinleme görevleri (yenileme sırasında iptal için saklanır).
    private var updateTask: Task<Void, Never>?
    private var listenerTasks: [Task<Void, Never>] = []

    /// Testlerde sahte ürün enjekte etmek için.
    #if DEBUG
    public init(products: [String: Product] = [:], entitlements: EntitlementSet = .none) {
        self.products = products
        self.entitlements = entitlements
    }
    #else
    public init() {}
    #endif

    // MARK: - Yaşam döngüsü

    isolated deinit {
        updateTask?.cancel()
        listenerTasks.forEach { $0.cancel() }
    }

    /// Uygulama açılışında çağrılır: ürünleri yükler, işlemleri dinler,
    /// mevcut yetkileri tazeler.
    public func bootstrap() async {
        startTransactionListener()
        async let load: Void = loadProducts()
        async let refresh: Void = refreshEntitlements()
        _ = await (load, refresh)
    }

    // MARK: - Ürünler

    /// Katalogdaki tüm ürünleri yükler.
    public func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let identifiers = ProductCatalog.allIdentifiers
            let fetched = try await Product.products(for: identifiers)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            errorMessage = nil
        } catch {
            // Ürünler yüklenemezse uygulama **bozuk olmaz**; yalnızca
            // satın alma düğmeleri devre dışı kalır.
            errorMessage = Self.describe(error)
        }
    }

    /// Belirli bir kapsamın ürünü.
    public func product(for tier: DiveTier) -> Product? {
        guard let id = ProductCatalog.identifier(for: tier) else { return nil }
        return products[id]
    }

    /// Teklif listesi (StoreKit fiyatları doldurulmuş).
    public func offerings() -> [ProductCatalog.Offering] {
        ProductCatalog.offerings().map { offering in
            var updated = offering
            if let product = products[offering.productIdentifier] {
                updated.title = offering.title
            }
            return updated
        }
    }

    // MARK: - Satın alma

    /// Satın alma başlatır.
    ///
    /// - Parameter result: satın alma sonucunu bildiren geri çağırma.
    /// - Returns: İşlem tamamlandıysa `true`.
    @discardableResult
    public func purchase(tier: DiveTier) async -> Bool {
        guard let product = product(for: tier) else {
            errorMessage = "Ürün yüklenemedi. Bağlantınızı kontrol edin."
            return false
        }
        return await purchase(product: product)
    }

    /// Ürünle satın alma.
    @discardableResult
    public func purchase(product: Product) async -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                // **Kritik**: işlem sonlandırılmalı, yoksa işlem
                // yeniden teslim edilir ve uygulama açılışında tekrar
                // işlenir.
                await transaction.finish()
                await refreshEntitlements()
                errorMessage = nil
                return true

            case .userCancelled:
                return false

            case .pending:
                // Aile Paylaşımı / onay bekleyen ödeme
                errorMessage = "Satın alma onay bekliyor."
                return false

            @unknown default:
                errorMessage = "Bilinmeyen satın alma sonucu."
                return false
            }
        } catch {
            errorMessage = Self.describe(error)
            return false
        }
    }

    // MARK: - Yenileme

    /// "Satın Alınanları Geri Yükle".
    ///
    /// - Note: Apple, geri yüklemeyi zorunlu kılar: kullanıcı aynı Apple
    ///   hesabıyla başka bir cihazda Pro'yu görmelidir.
    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            errorMessage = nil
            if entitlements.isEmpty {
                errorMessage = "Bu Apple hesabında bulunan bir satın alım yok."
            }
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    // MARK: - Yetkiler

    /// Etkin işlemlerden yetkileri türetir.
    public func refreshEntitlements() async {
        var identifiers = Set<String>()
        var expiration: Date?
        var isAnnual = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard let known = ProductCatalog.tier(for: transaction.productID) else { continue }

            identifiers.insert(transaction.productID)
            if known == .lifetime {
                expiration = nil
            } else if let expiry = transaction.expirationDate {
                if known == .proAnnual { isAnnual = true }
                // StoreKit 1'den gelen veya daha uzun bir bitiş varsa koru
                expiration = max(expiration ?? .distantPast, expiry)
            }
        }

        entitlements = EntitlementSet.make(
            transactionIDs: identifiers,
            expiration: expiration,
            now: Date())
        // Yıllık bilgisi yalnızca gösterim için saklanır
        if isAnnual {
            entitlements.activeProductIdentifiers.insert(ProductCatalog.annualIdentifier)
        }
    }

    /// Feature gate (görünüm katmanına verilir).
    public var featureGate: FeatureGate {
        FeatureGate(entitlements: entitlements)
    }

    /// Etkin kapsam.
    public var tier: DiveTier { entitlements.tier() }

    /// Kullanıcı daha önce bir şey satın aldı mı?
    public var hasAnyPurchase: Bool { !entitlements.isEmpty }

    /// Abonelik yenilemesi kapatılabilir mi (yalnızca otomatik yenilenebilir).
    public var canManageSubscription: Bool { entitlements.isAutoRenewable }

    // MARK: - Dinleme

    /// İşlem güncellemelerini dinlemeye başlar.
    ///
    /// - Note: Yenileme, iptal, geri ödeme ve aile paylaşımı değişiklikleri
    ///   buradan gelir. `refreshEntitlements()` çağrısı yetkileri
    ///   yeniden hesaplar.
    public func startTransactionListener() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? Self.checkVerified(result) {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    /// İşlem geçmişini dinler (analitik ve hata ayıklama için).
    public func startUnfinishedTransactionListener() {
        let task = Task { [weak self] in
            for await result in Transaction.unfinished {
                guard let self else { return }
                if let transaction = try? Self.checkVerified(result) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
        listenerTasks.append(task)
    }

    // MARK: - Yardımcılar

    /// StoreKit doğrulaması.
    ///
    /// - Throws: `StoreError.failedVerification` — imza geçersizse.
    static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw StoreError.failedVerification(error)
        case .verified(let safe):
            return safe
        }
    }

    static func describe(_ error: Error) -> String {
        guard let storeError = error as? StoreError else {
            return error.localizedDescription
        }
        switch storeError {
        case .failedVerification:
            return "Satın alma doğrulanamadı. Lütfen yeniden deneyin."
        case .unknown:
            return "Bilinmeyen bir hata oluştu."
        }
    }

    /// Hizmet hataları.
    public enum StoreError: Error, LocalizedError {
        case failedVerification(Error)
        case unknown

        public var errorDescription: String? {
            switch self {
            case .failedVerification: return "Satın alma doğrulanamadı."
            case .unknown: return "Bilinmeyen hata."
            }
        }
    }

    // MARK: - Kalıcılık

    /// Yetkileri kullanıcı varsayılanlarına yazar (çevrimdışı önbellek).
    ///
    /// - Note: **Güvenlik nedeniyle yalnızca olumlu bilgi saklanır** (Pro
    ///   alındıysa). Temel sürüm bilgisi saklanmaz; böylece bir kullanıcı
    ///   cihazını sıfırladığında "hayalet Pro" oluşmaz.
    public func persistEntitlements(to defaults: UserDefaults = .standard) {
        if entitlements.hasAnyPurchase {
            defaults.set(true, forKey: Self.cacheKey)
            defaults.set(entitlements.expiration, forKey: Self.expirationKey)
        } else {
            defaults.removeObject(forKey: Self.cacheKey)
            defaults.removeObject(forKey: Self.expirationKey)
        }
    }

    static let cacheKey = "com.divelog.entitlements.cached"
    static let expirationKey = "com.divelog.entitlements.expiration"

    /// Kuyruğa alınmış (henüz doğrulanmamış) yetkiler.
    ///
    /// - Note: **Yalnızca arayüz ipucu** olarak kullanılır (ör. "Pro özellikleri
    ///   açık" rozeti). Gerçek kararlar `refreshEntitlements()` sonrası
    ///   verilir; aksi halde iptal edilmiş bir abonelik hayalet Pro yaratırdı.
    public static func cachedGrant(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: cacheKey)
    }
}
#endif
