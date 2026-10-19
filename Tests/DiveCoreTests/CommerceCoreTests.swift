import XCTest
@testable import DiveCore

/// ADIM 1 — ticaret çekirdeği: kapsamlar, katalog, yetkiler ve özellik kapısı.
final class CommerceCoreTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Kapsamlar

    func testTierBasics() {
        XCTAssertFalse(DiveTier.free.unlocksPro)
        XCTAssertTrue(DiveTier.proMonthly.unlocksPro)
        XCTAssertTrue(DiveTier.proAnnual.unlocksPro)
        XCTAssertTrue(DiveTier.lifetime.unlocksPro)

        XCTAssertTrue(DiveTier.proMonthly.isSubscription)
        XCTAssertTrue(DiveTier.proAnnual.isSubscription)
        XCTAssertFalse(DiveTier.lifetime.isSubscription)
    }

    func testTierRanks() {
        XCTAssertLessThan(DiveTier.free.rank, DiveTier.proMonthly.rank)
        XCTAssertEqual(DiveTier.proMonthly.rank, DiveTier.proAnnual.rank,
                       "Aylık ve yıllık aynı özellik setini açar")
        XCTAssertGreaterThan(DiveTier.lifetime.rank, DiveTier.proAnnual.rank,
                             "Ömür boyu abonelikten üstündür")
    }

    func testTierTitlesAndDetails() {
        for tier in DiveTier.allCases {
            XCTAssertFalse(tier.title.isEmpty)
            XCTAssertFalse(tier.detail.isEmpty)
        }
    }

    // MARK: - Ürün kataloğu

    func testProductIdentifiersAreUnique() {
        XCTAssertEqual(Set(ProductCatalog.allIdentifiers).count,
                       ProductCatalog.allIdentifiers.count)
        XCTAssertEqual(ProductCatalog.allIdentifiers.count, 3)
    }

    func testTierIdentifierRoundTrip() {
        for tier in [DiveTier.proMonthly, .proAnnual, .lifetime] {
            let id = ProductCatalog.identifier(for: tier)
            XCTAssertNotNil(id)
            XCTAssertEqual(ProductCatalog.tier(for: id!), tier)
        }
        XCTAssertNil(ProductCatalog.identifier(for: .free))
    }

    func testUnknownProductIsRejected() {
        XCTAssertNil(ProductCatalog.tier(for: "com.something.else"))
        XCTAssertFalse(ProductCatalog.isKnownProduct("com.something.else"))
        XCTAssertTrue(ProductCatalog.isKnownProduct(ProductCatalog.monthlyIdentifier))
    }

    func testSubscriptionIdentifiers() {
        XCTAssertEqual(ProductCatalog.subscriptionIdentifiers.count, 2)
        XCTAssertFalse(ProductCatalog.subscriptionIdentifiers
            .contains(ProductCatalog.lifetimeIdentifier),
            "Ömür boyu abonelik değildir")
    }

    func testOfferingsCoverAllPaidTiers() {
        let offerings = ProductCatalog.offerings()
        XCTAssertEqual(offerings.count, 3)
        XCTAssertEqual(Set(offerings.map(\.tier)),
                       [DiveTier.proMonthly, .proAnnual, .lifetime])
        for offering in offerings {
            XCTAssertFalse(offering.title.isEmpty)
            XCTAssertFalse(offering.subtitle.isEmpty)
            XCTAssertFalse(offering.features.isEmpty, "Her teklif özellik listelemeli")
        }
    }

    func testExactlyOneOfferingIsRecommended() {
        let offerings = ProductCatalog.offerings()
        XCTAssertEqual(offerings.filter { $0.isRecommended }.count, 1)
        XCTAssertEqual(ProductCatalog.recommendedOffering().tier, .proAnnual)
    }

    func testAnnualCanBeUnrecommended() {
        let offerings = ProductCatalog.offerings(isRecommendedAnnual: false)
        XCTAssertEqual(offerings.filter { $0.isRecommended }.count, 1,
                       "Yıllık vurgulanmazsa başka bir teklif vurgulanmalı")
        XCTAssertEqual(offerings.first(where: \.isRecommended)?.tier, .lifetime)
    }

    func testOfferingsListEveryFeature() {
        let offering = ProductCatalog.offerings().first!
        XCTAssertEqual(Set(offering.features), Set(FeatureKey.allCases))
    }

    // MARK: - Yetkiler

    func testNoEntitlementIsFreeTier() {
        let set = EntitlementSet.none
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.tier(at: base), .free)
        XCTAssertFalse(set.hasAnyPurchase)
    }

    func testSubscriptionEntitlementExpires() {
        let set = EntitlementSet.make(
            transactionIDs: [ProductCatalog.monthlyIdentifier],
            expiration: base.addingTimeInterval(30 * 24 * 3600),
            now: base)
        XCTAssertEqual(set.tier(at: base), .proMonthly)
        // Bitiş + 1 gün: tolerans penceresinde hâlâ Pro
        XCTAssertEqual(set.tier(at: base.addingTimeInterval(31 * 24 * 3600)), .proMonthly)
        // Bitiş + 8 gün: tolerans bitti, Temel
        XCTAssertEqual(set.tier(at: base.addingTimeInterval(38 * 24 * 3600)), .free)
    }

    func testGracePeriodKeepsAccessBriefly() {
        let expiration = base
        let set = EntitlementSet.make(transactionIDs: [ProductCatalog.monthlyIdentifier],
                                      expiration: expiration, now: base)
        // 1 gün sonra hâlâ Pro (ödeme yöntemi bildirimi gecikmesi)
        XCTAssertEqual(set.tier(at: base.addingTimeInterval(24 * 3600)), .proMonthly)
        // 10 gün sonra Temel
        XCTAssertEqual(set.tier(at: base.addingTimeInterval(10 * 24 * 3600)), .free)
    }

    func testLifetimeNeverExpires() {
        let set = EntitlementSet.make(transactionIDs: [ProductCatalog.lifetimeIdentifier],
                                      expiration: nil, now: base)
        XCTAssertEqual(set.tier(at: base), .lifetime)
        XCTAssertEqual(set.tier(at: base.addingTimeInterval(10 * 365 * 24 * 3600)), .lifetime,
                       "Ömür boyu asla süresi dolmaz")
    }

    func testLifetimeWinsOverSubscription() {
        let set = EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier,
                             ProductCatalog.annualIdentifier],
            expiration: base, now: base)
        XCTAssertEqual(set.tier(at: base), .lifetime)
    }

    func testSubscriptionWithoutExpirationIsFree() {
        // StoreKit 1'den gelen veya bozuk veri: güvenli taraf → Temel
        let set = EntitlementSet.make(transactionIDs: [ProductCatalog.monthlyIdentifier],
                                      expiration: nil, now: base)
        XCTAssertEqual(set.tier(at: base), .free)
    }

    func testAnnualDetection() {
        let annual = EntitlementSet.make(transactionIDs: [ProductCatalog.annualIdentifier],
                                        expiration: base.addingTimeInterval(365 * 24 * 3600),
                                        now: base)
        XCTAssertTrue(annual.isAnnual(at: base))
        XCTAssertTrue(annual.isAutoRenewable)

        let monthly = EntitlementSet.make(transactionIDs: [ProductCatalog.monthlyIdentifier],
                                          expiration: base.addingTimeInterval(30 * 24 * 3600),
                                          now: base)
        XCTAssertFalse(monthly.isAnnual(at: base))
    }

    func testLifetimeIsNotAutoRenewable() {
        let set = EntitlementSet.make(transactionIDs: [ProductCatalog.lifetimeIdentifier],
                                      expiration: nil, now: base)
        XCTAssertFalse(set.isAutoRenewable)
    }

    func testEntitlementRoundTrip() throws {
        let set = EntitlementSet.make(
            transactionIDs: [ProductCatalog.annualIdentifier],
            expiration: base.addingTimeInterval(86400), now: base)
        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(try JSONDecoder().decode(EntitlementSet.self, from: data), set)
    }

    // MARK: - Özellik kapısı

    func testFreeTierLocksProFeatures() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertEqual(gate.tier, .free)
        XCTAssertTrue(gate.isFreeTier)
        XCTAssertEqual(gate.lockedFeatures.count, FeatureKey.allCases.count)
    }

    func testProTierUnlocksEverything() {
        let gate = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.monthlyIdentifier],
            expiration: base.addingTimeInterval(86400), now: base), now: base)
        XCTAssertTrue(gate.lockedFeatures.isEmpty)
        XCTAssertEqual(gate.unlockedFeatures.count, FeatureKey.allCases.count)
    }

    func testLifetimeUnlocksEverything() {
        let gate = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier],
            expiration: nil, now: base), now: base)
        XCTAssertTrue(gate.lockedFeatures.isEmpty)
    }

    func testExpiredSubscriptionRelocks() {
        let entitlements = EntitlementSet.make(
            transactionIDs: [ProductCatalog.monthlyIdentifier],
            expiration: base, now: base)
        // Bitiş anında henüz Pro
        XCTAssertTrue(FeatureGate(entitlements: entitlements, now: base)
            .lockedFeatures.isEmpty)
        // Tolerans penceresi (7 gün) içinde de Pro
        XCTAssertTrue(FeatureGate(entitlements: entitlements,
                                  now: base.addingTimeInterval(5 * 24 * 3600))
            .lockedFeatures.isEmpty)
        // 30 gün sonra Temel → özellikler yeniden kilitlenir
        XCTAssertEqual(FeatureGate(entitlements: entitlements,
                                   now: base.addingTimeInterval(30 * 24 * 3600))
            .lockedFeatures.count, FeatureKey.allCases.count)
    }

    func testDecisionForLockedFeature() {
        let gate = FeatureGate(entitlements: .none, now: base)
        let decision = gate.decision(for: .nitroxSupport)
        XCTAssertFalse(decision.isAllowed)
        XCTAssertTrue(decision.shouldShowPaywall)
        XCTAssertNotNil(decision.reason)
    }

    func testDecisionForUnlockedFeature() {
        let gate = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier],
            expiration: nil, now: base), now: base)
        let decision = gate.decision(for: .nitroxSupport)
        XCTAssertTrue(decision.isAllowed)
        XCTAssertFalse(decision.shouldShowPaywall)
        XCTAssertNil(decision.reason)
    }

    func testGroupQueries() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertEqual(gate.lockedFeatures(in: .gases).count, 2)
        XCTAssertEqual(gate.lockedFeatures(in: .companion).count, 2)
        XCTAssertFalse(gate.allowsAll(in: .gases))
    }

    // MARK: - Günlük sınırı

    func testFreeTierShowsThreeDives() {
        let dives = Array(repeating: 0, count: 10)
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertEqual(gate.visibleDives(dives).count, 3)
        XCTAssertEqual(gate.visibleLogLimit, 3)
        XCTAssertEqual(gate.hiddenDiveCount(total: 10), 7)
    }

    func testProTierShowsAllDives() {
        let dives = Array(repeating: 0, count: 10)
        let gate = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier],
            expiration: nil, now: base), now: base)
        XCTAssertEqual(gate.visibleDives(dives).count, 10)
        XCTAssertEqual(gate.hiddenDiveCount(total: 10), 0)
    }

    func testFreeTierWithFewDives() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertEqual(gate.visibleDives([1, 2]).count, 2)
        XCTAssertEqual(gate.hiddenDiveCount(total: 2), 0)
    }

    func testCanViewDiveByIndex() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertTrue(gate.canViewDive(at: 0))
        XCTAssertTrue(gate.canViewDive(at: 2))
        XCTAssertFalse(gate.canViewDive(at: 3))
    }

    func testHiddenDiveNeverExceedsTotal() {
        let gate = FeatureGate(entitlements: .none, now: base)
        for total in 0...20 {
            XCTAssertLessThanOrEqual(gate.hiddenDiveCount(total: total), total)
        }
    }

    // MARK: - Paywall tetikleri

    func testPaywallTriggerForLockedFeature() {
        let gate = FeatureGate(entitlements: .none, now: base)
        let trigger = gate.paywallTrigger(for: .dataExport)
        XCTAssertEqual(trigger, .feature(.dataExport))
        XCTAssertEqual(trigger?.headline, "UDDF / FIT dışa aktarma Pro'da")
        XCTAssertFalse(trigger?.message.isEmpty ?? true)
    }

    func testNoPaywallTriggerForUnlockedFeature() {
        let gate = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.annualIdentifier],
            expiration: base.addingTimeInterval(86400), now: base), now: base)
        XCTAssertNil(gate.paywallTrigger(for: .dataExport))
    }

    func testPaywallTriggerForHiddenDive() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertNil(gate.paywallTrigger(diveIndex: 2, totalDives: 10))
        let trigger = gate.paywallTrigger(diveIndex: 5, totalDives: 10)
        XCTAssertEqual(trigger, .logHistory(hidden: 7))
        XCTAssertEqual(trigger?.headline, "7 dalışınız kilitli")
    }

    func testTriggerHeadlinesAndMessages() {
        let triggers: [FeatureGate.PaywallTrigger] = [
            .feature(.companionMap), .logHistory(hidden: 5), .manual
        ]
        for trigger in triggers {
            XCTAssertFalse(trigger.headline.isEmpty)
            XCTAssertFalse(trigger.message.isEmpty)
        }
    }

    // MARK: - Bölüm kilitleri

    func testLockedSections() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertEqual(gate.lockedSettingsSections().count, 4)
        XCTAssertEqual(gate.lockedLogbookSections().count, 3)
        XCTAssertEqual(gate.lockedCompanionSections().count, 2)
    }

    func testNoLockedSectionsWhenPro() {
        let gate = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier],
            expiration: nil, now: base), now: base)
        XCTAssertTrue(gate.lockedSettingsSections().isEmpty)
        XCTAssertTrue(gate.lockedLogbookSections().isEmpty)
        XCTAssertTrue(gate.lockedCompanionSections().isEmpty)
    }

    // MARK: - Özellik tanımları

    func testEveryFeatureHasPresentation() {
        for feature in FeatureKey.allCases {
            XCTAssertFalse(feature.title.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.benefit.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.symbolName.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.group.rawValue.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.id.isEmpty)
        }
    }

    func testFeatureGroupsPartitionAllFeatures() {
        for group in FeatureKey.Group.allCases {
            let inGroup = FeatureKey.allCases.filter { $0.group == group }
            XCTAssertFalse(inGroup.isEmpty, "\(group.rawValue) boş olmamalı")
        }
        // Her özellik tam olarak bir grupta
        var total = 0
        for group in FeatureKey.Group.allCases {
            total += FeatureKey.allCases.filter { $0.group == group }.count
        }
        XCTAssertEqual(total, FeatureKey.allCases.count)
    }

    func testConvenienceAccessors() {
        let free = FeatureGate(entitlements: .none, now: base)
        XCTAssertFalse(free.allowsNitroxPlanning)
        XCTAssertFalse(free.allowsExport)

        let pro = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier],
            expiration: nil, now: base), now: base)
        XCTAssertTrue(pro.allowsNitroxPlanning)
        XCTAssertTrue(pro.allowsExport)
    }

    // MARK: - Metinler

    func testCommerceTextIsComplete() {
        XCTAssertFalse(CommerceText.safetyNoticeShort.isEmpty)
        XCTAssertFalse(CommerceText.safetyNoticeLong.isEmpty)
        XCTAssertFalse(CommerceText.subscriptionTerms.isEmpty)
        XCTAssertFalse(CommerceText.lifetimeTerms.isEmpty)
        XCTAssertFalse(LegalText.termsAndPrivacy.isEmpty)
        XCTAssertTrue(CommerceText.safetyNoticeLong.contains("ücretsiz"))
    }

    func testCommerceTextFeatureMessages() {
        for feature in FeatureKey.allCases {
            XCTAssertTrue(CommerceText.lockedTitle(feature).contains(feature.title))
            XCTAssertEqual(CommerceText.lockedMessage(feature), feature.benefit)
        }
    }

    func testPurchaseTitle() {
        XCTAssertEqual(CommerceText.purchaseTitle(tier: .lifetime), "Ömür Boyu Satın Al")
        XCTAssertTrue(CommerceText.purchaseTitle(tier: .proAnnual).contains("Yıllık"))
    }

    func testHiddenDiveTitle() {
        XCTAssertTrue(CommerceText.hiddenDiveTitle(count: 1).contains("1"))
        XCTAssertTrue(CommerceText.hiddenDiveTitle(count: 7).contains("7"))
    }
}
