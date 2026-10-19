import Foundation

/// ADIM 1 — özellik kapısı (feature gate).
///
/// Kullanıcı hangi özelliğe erişebilir, hangisinde paywall açılmalı? Bu
/// karar **tek** bir yerde verilir ve test edilir; görünüm katmanı
/// `decision(for:)` sonucuna uyar.
///
/// ## Güvenlik sınırı
/// `FeatureKey.isSafetyCritical` her zaman `false` döner. Bu yüzden
/// `DiveSessionController`, `AlarmCoordinator`, `DecoEngine`,
/// `AscentAdvisor`, `DiveLockController` gibi güvenlik bileşenleri
/// **hiçbir zaman** bu kapıdan geçmez — bu bileşenler `ProductCatalog`
/// veya `EntitlementSet` bilmez bile. Böylece bir abonelik hatası
/// dekompresyon hesabını veya alarmı etkileyemez.
public struct FeatureGate: Equatable, Sendable {

    /// Kullanıcının yetkileri.
    public let entitlements: EntitlementSet
    /// Değerlendirme anı (test edilebilirlik için)
    public let now: Date

    public init(entitlements: EntitlementSet, now: Date = Date()) {
        self.entitlements = entitlements
        self.now = now
    }

    /// Etkin kapsam.
    public var tier: DiveTier { entitlements.tier(at: now) }

    /// Temel sürüm mü?
    public var isFreeTier: Bool { !tier.unlocksPro }

    // MARK: - Temel karar

    /// Bir özelliğe erişim kararı.
    public struct Decision: Equatable, Sendable {
        public let feature: FeatureKey
        public let isAllowed: Bool
        /// Kilitliyse paywall açılmalı mı
        public let shouldShowPaywall: Bool
        /// Kilit nedeni (kullanıcıya gösterilecek metin)
        public let reason: String?

        public init(feature: FeatureKey,
                    isAllowed: Bool,
                    shouldShowPaywall: Bool,
                    reason: String?) {
            self.feature = feature
            self.isAllowed = isAllowed
            self.shouldShowPaywall = shouldShowPaywall
            self.reason = reason
        }
    }

    /// Özelliğe erişilebilir mi?
    ///
    /// - Note: Güvenlik özellikleri her zaman `isAllowed = true` döner.
    public func decision(for feature: FeatureKey) -> Decision {
        if feature.isSafetyCritical {
            return Decision(feature: feature, isAllowed: true,
                            shouldShowPaywall: false, reason: nil)
        }
        let allowed = !feature.isLocked(in: tier)
        return Decision(feature: feature,
                        isAllowed: allowed,
                        shouldShowPaywall: !allowed,
                        reason: allowed ? nil : ProductCatalog.lockReason(for: feature))
    }

    /// Kısayol.
    public func allows(_ feature: FeatureKey) -> Bool {
        decision(for: feature).isAllowed
    }

    /// Kilitliyse paywall açılmalı mı?
    public func shouldShowPaywall(for feature: FeatureKey) -> Bool {
        decision(for: feature).shouldShowPaywall
    }

    // MARK: - Toplu kararlar

    /// Kilitli özelliklerin listesi.
    public var lockedFeatures: [FeatureKey] {
        FeatureKey.allCases.filter { $0.isLocked(in: tier) }
    }

    /// Kilidi açılmış özelliklerin listesi.
    public var unlockedFeatures: [FeatureKey] {
        FeatureKey.allCases.filter { !$0.isLocked(in: tier) }
    }

    /// Aileye göre kilitli özellikler (paywall grupları).
    public func lockedFeatures(in group: FeatureKey.Group) -> [FeatureKey] {
        FeatureKey.lockedFeatures(in: tier, group: group)
    }

    /// Bir özellik grubunun tamamı açık mı?
    public func allowsAll(in group: FeatureKey.Group) -> Bool {
        FeatureKey.allCases.filter { $0.group == group }
            .allSatisfy { allows($0) }
    }

    // MARK: - Sayısal sınırlar

    /// Görüntülenebilecek en fazla dalış sayısı.
    public var visibleLogLimit: Int {
        tier.unlocksPro ? Int.max : ProductCatalog.freeTierLogLimit
    }

    /// Verilen günlük listesini sınıra göre kırpar.
    public func visibleDives<T>(_ dives: [T]) -> [T] {
        Array(ProductCatalog.visibleDives(dives, tier: tier))
    }

    /// Gizli dalış sayısı.
    public func hiddenDiveCount(total: Int) -> Int {
        ProductCatalog.hiddenDiveCount(total: total, tier: tier)
    }

    /// Nitrox kullanılabilir mi? (MOD hesabı Temel'de de çalışır, bu yüzden
    /// özellik **açık**; yalnızca planlayıcı kilitlidir)
    public var allowsNitroxPlanning: Bool { allows(.nitroxSupport) }

    /// Dışa aktarma yapılabilir mi?
    public var allowsExport: Bool { allows(.dataExport) }

    // MARK: - Sunum durumu

    /// Paywall'ın hangi nedenle açıldığı (paywall başlığı için).
    public enum PaywallTrigger: Equatable, Sendable {
        case feature(FeatureKey)
        case logHistory(hidden: Int)
        case manual

        /// Başlık metni.
        public var headline: String {
            switch self {
            case .feature(let feature):
                return "\(feature.title) Pro'da"
            case .logHistory(let hidden):
                return "\(hidden) dalışınız kilitli"
            case .manual:
                return "DiveLog Pro"
            }
        }

        /// Açıklama metni.
        public var message: String {
            switch self {
            case .feature(let feature):
                return feature.benefit
            case .logHistory:
                return "Temel sürümde son \(ProductCatalog.freeTierLogLimit) dalış "
                     + "görüntülenebilir. Tüm geçmişinize sınırsız erişin."
            case .manual:
                return "Tüm gelişmiş özellikler, tek bir adımda."
            }
        }
    }

    /// Belirli bir özelliğe tıklandığında paywall tetiklenmeli mi?
    public func paywallTrigger(for feature: FeatureKey) -> PaywallTrigger? {
        guard shouldShowPaywall(for: feature) else { return nil }
        return .feature(feature)
    }

    /// Eski bir dalışa tıklandığında tetik (kilitli günlük).
    public func paywallTrigger(diveIndex: Int, totalDives: Int) -> PaywallTrigger? {
        guard !canViewDive(at: diveIndex) else { return nil }
        return .logHistory(hidden: hiddenDiveCount(total: totalDives))
    }

    /// Bu dalış görüntülenebilir mi?
    public func canViewDive(at index: Int) -> Bool {
        ProductCatalog.canViewDive(at: index, tier: tier)
    }
}

extension FeatureGate {

    /// `DiveSettings` ile tümleştirme: ayarlar ekranında hangi bölümler
    /// kilitli gösterilecek.
    public func lockedSettingsSections() -> [FeatureKey] {
        var sections: [FeatureKey] = []
        if !allows(.advancedGradientFactors) { sections.append(.advancedGradientFactors) }
        if !allows(.customGradientFactors) { sections.append(.customGradientFactors) }
        if !allows(.nitroxSupport) { sections.append(.nitroxSupport) }
        if !allows(.deepStops) { sections.append(.deepStops) }
        return sections
    }

    /// Günlük ekranında gösterilecek bölümler.
    public func lockedLogbookSections() -> [FeatureKey] {
        var sections: [FeatureKey] = []
        if !allows(.unlimitedLogHistory) { sections.append(.unlimitedLogHistory) }
        if !allows(.longTermStatistics) { sections.append(.longTermStatistics) }
        if !allows(.profileCharts) { sections.append(.profileCharts) }
        return sections
    }

    /// iPhone eşlikçisinde gösterilecek bölümler.
    public func lockedCompanionSections() -> [FeatureKey] {
        var sections: [FeatureKey] = []
        if !allows(.companionMap) { sections.append(.companionMap) }
        if !allows(.dataExport) { sections.append(.dataExport) }
        return sections
    }
}
