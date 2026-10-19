import XCTest
@testable import DiveCore

/// ADIM 1 — **güvenlik garantisi**: hiçbir kapsamda güvenlik özelliği
/// kilitlenmemelidir.
///
/// Bu test dosyası bilinçli olarak ayrı tutulmuştur: ADIM 1'in en
/// önemli kabul kriteri budur. Bir dalış bilgisayarında dekompresyon veya
/// alarmın kilitlenmesi **hayat kurtarıcı niteliktedir** ve hem
/// kullanıcıya hem denetleyiciye zarar verir.
final class CommerceSafetyTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func gateForAllTiers() -> [(DiveTier, FeatureGate)] {
        let free = FeatureGate(entitlements: .none, now: base)
        let monthly = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.monthlyIdentifier],
            expiration: base.addingTimeInterval(86400), now: base), now: base)
        let annual = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.annualIdentifier],
            expiration: base.addingTimeInterval(365 * 86400), now: base), now: base)
        let lifetime = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.lifetimeIdentifier],
            expiration: nil, now: base), now: base)
        // Süresi dolmuş abonelik
        let expired = FeatureGate(entitlements: EntitlementSet.make(
            transactionIDs: [ProductCatalog.monthlyIdentifier],
            expiration: base, now: base), now: base)
        return [(.free, free), (.proMonthly, monthly), (.proAnnual, annual),
                (.lifetime, lifetime), (.free, expired)]
    }

    // MARK: - Temel kural

    /// Her kapsamda, her güvenlik kabiliyeti açık olmalıdır.
    func testNoSafetyCapabilityIsEverLocked() {
        for (tier, gate) in gateForAllTiers() {
            XCTAssertEqual(gate.lockedSafetyCapabilityCount, 0,
                           "\(tier) kapsamında güvenlik kabiliyeti kilitlenmiş")
            for capability in SafetyCapability.allCases {
                XCTAssertTrue(gate.canPerform(capability),
                              "\(tier): \(capability.rawValue) kilitli")
                XCTAssertFalse(gate.isSafetyCapabilityLocked(capability),
                               "\(tier): \(capability.rawValue) kilitli görünüyor")
            }
        }
    }

    /// Temel sürümde tüm güvenlik kabiliyetleri açık olmalıdır.
    func testFreeTierHasFullSafety() {
        let gate = FeatureGate(entitlements: .none, now: base)
        XCTAssertEqual(gate.freeSafetyCapabilities.count, SafetyCapability.allCases.count)
    }

    // MARK: - Dekompresyon çekirdeği hiç kilitlenmemeli

    func testDecompressionCapabilitiesAreSafety() {
        let mustBeFree: [SafetyCapability] = [
            .noDecompressionLimit, .ceiling, .decoStops, .timeToSurface,
            .gf99, .tissueLoading, .speedLimits
        ]
        for capability in mustBeFree {
            XCTAssertTrue(capability.isAlwaysFreeByPolicy,
                          "\(capability.rawValue) güvenlik dışı işaretlenmiş")
        }
    }

    func testAlarmCapabilitiesAreSafety() {
        let mustBeFree: [SafetyCapability] = [
            .ascentRateAlarm, .ceilingAlarm, .ndlWarning, .oxygenWarnings,
            .modWarning
        ]
        for capability in mustBeFree {
            XCTAssertTrue(capability.isAlwaysFreeByPolicy,
                          "\(capability.rawValue) güvenlik dışı işaretlenmiş")
        }
    }

    func testEmergencyCapabilitiesAreSafety() {
        let mustBeFree: [SafetyCapability] = [
            .emergencyMenu, .ascentAdvisor, .waterLock, .emergencyActionButton
        ]
        for capability in mustBeFree {
            XCTAssertTrue(capability.isAlwaysFreeByPolicy,
                          "\(capability.rawValue) güvenlik dışı işaretlenmiş")
        }
    }

    func testLiveMeasurementCapabilitiesAreSafety() {
        let mustBeFree: [SafetyCapability] = [
            .liveDepth, .diveTime, .maxDepth, .averageDepth,
            .temperature, .ascentRate, .heading, .diveComputerCore
        ]
        for capability in mustBeFree {
            XCTAssertTrue(capability.isAlwaysFreeByPolicy,
                          "\(capability.rawValue) güvenlik dışı işaretlenmiş")
        }
    }

    func testDataIntegrityCapabilitiesAreSafety() {
        // Dalış kaydı **silinmez**, yalnızca erişim sınırlanır.
        XCTAssertTrue(SafetyCapability.saveDiveLog.isAlwaysFreeByPolicy)
        XCTAssertTrue(SafetyCapability.viewActiveDive.isAlwaysFreeByPolicy)
    }

    // MARK: - Kilitlenebilir özellikler güvenlik olmamalı

    /// Kilitlenebilir özellik listesinde güvenlik kabiliyeti **olmamalıdır**.
    func testNoProFeatureIsSafetyCritical() {
        for feature in FeatureKey.allCases {
            XCTAssertFalse(feature.isSafetyCritical,
                           "\(feature.rawValue) güvenlik olarak işaretlenmiş")
            XCTAssertEqual(feature.requiredTier, .proMonthly)
        }
    }

    /// Hiçbir Pro özelliğinin başlığı bir güvenlik kabiliyetiyle eşleşmemeli.
    func testProFeaturesDoNotCoverSafetyCapabilities() {
        let safetyTitles = Set(SafetyCapability.allCases.map(\.title))
        for feature in FeatureKey.allCases {
            XCTAssertFalse(safetyTitles.contains(feature.title),
                           "\(feature.rawValue) bir güvenlik kabiliyetiyle çakışıyor")
        }
    }

    /// Özellik adları ile kabiliyet adları kesişmemeli.
    func testFeatureAndSafetyNamesAreDisjoint() {
        let featureNames = Set(FeatureKey.allCases.map(\.rawValue))
        for capability in SafetyCapability.allCases {
            XCTAssertFalse(featureNames.contains(capability.rawValue),
                           "\(capability.rawValue) iki listede de var")
        }
    }

    // MARK: - Kapsam bağımsızlığı

    /// Yetkiler **hiçbir güvenlik tipine** bağlı olmamalıdır.
    ///
    /// - Note: `DiveSessionController`, `DecoEngine`, `AlarmCoordinator` gibi
    ///   güvenlik bileşenlerinin dosyalarında `EntitlementSet` veya
    ///   `FeatureGate` **geçmemelidir**. Bu test kaynak taramasıyla bunu
    ///   doğrular (paket kökünde çalışıyorsa).
    func testSafetyFilesDoNotReferenceCommerce() throws {
        let root = FileManager.default.currentDirectoryPath
        let files = ["DecoEngine.swift", "AlarmCoordinator.swift", "TissueModel.swift",
                     "AscentAdvisor.swift", "DiveSessionController.swift",
                     "AscentRateMonitor.swift", "DeepStopCalculator.swift",
                     "OxygenToxicity.swift", "DiveState.swift", "DecoStopPlan.swift"]
        for file in files {
            let candidates = [
                "\(root)/Sources/DiveCore/Services/\(file)",
                "\(root)/Sources/DiveCore/Managers/\(file)",
                "\(root)/Sources/DiveCore/Models/\(file)"
            ]
            guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            else { continue }
            let text = try String(contentsOfFile: path, encoding: .utf8)
            for forbidden in ["EntitlementSet", "FeatureGate", "DiveTier", "ProductCatalog"] {
                // Yalnızca gerçek kod referanslarını ara (yorumları atla)
                for (index, line) in text.split(separator: "\n").enumerated()
                where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    XCTAssertFalse(line.contains(forbidden),
                                   "\(file):\(index + 1) güvenlik dosyası \(forbidden) kullanıyor")
                }
            }
        }
    }

    // MARK: - Politika

    func testSafetyPolicyIsAlwaysOpen() {
        for capability in SafetyCapability.allCases {
            XCTAssertTrue(SafetyPolicy.isAvailable(capability))
            XCTAssertFalse(SafetyPolicy.isLocked(capability))
        }
    }

    func testSafetyPolicySummary() {
        XCTAssertTrue(SafetyPolicy.alwaysFreeSummary.contains("\(SafetyCapability.allCases.count)"))
    }

    func testEverySafetyCapabilityIsDocumented() {
        for capability in SafetyCapability.allCases {
            XCTAssertFalse(capability.title.isEmpty, capability.rawValue)
            XCTAssertFalse(capability.explanation.isEmpty, capability.rawValue)
        }
    }

    // MARK: - Aktif dalış her zaman görüntülenebilir

    @MainActor
    func testActiveDiveAlwaysVisibleEvenOnFreeTier() {
        let gate = FeatureGate(entitlements: .none, now: base)
        // Aktif dalış günlükten bağımsızdır; kapsam onu etkilemez
        XCTAssertTrue(gate.canPerform(.viewActiveDive))
        XCTAssertTrue(gate.canPerform(.liveDepth))
        XCTAssertTrue(gate.canPerform(.diveTime))
    }

    /// Dalış kaydı **her zaman** yazılabilir (Temel sürümde de).
    @MainActor
    func testDiveLogCanAlwaysBeSaved() {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))
        XCTAssertNotNil(log, "Temel sürümde de dalış kaydedilebilmeli")
        XCTAssertFalse(log!.samples.isEmpty, "Örnekler kaydedilmeli")
    }

    // MARK: - Nitrox: MOD hesabı güvenlik, planlayıcı Pro

    /// MOD uyarısı Temel sürümde de çalışır; yalnızca **planlama** Pro'dur.
    func testModWarningIsFreeEvenThoughPlanningIsPro() {
        XCTAssertTrue(SafetyCapability.modWarning.isAlwaysFreeByPolicy)
        // Nitrox planlama özelliği Pro
        XCTAssertTrue(FeatureKey.nitroxSupport.isLocked(in: .free))
    }

    func testNitroxModCalculationWorksRegardlessOfTier() {
        // Model katmanı kapsamdan bağımsızdır
        let mod = GasMix.nitrox(32)?.maximumOperatingDepth(maxPO2: 1.4)
        XCTAssertNotNil(mod)
        XCTAssertGreaterThan(mod ?? 0, 30)
    }
}

// MARK: - Yardımcı

extension SafetyCapability {
    /// Politika düzeyinde her zaman açık mı?
    var isAlwaysFreeByPolicy: Bool { SafetyPolicy.isAvailable(self) }
}

extension SafetyPolicy {
    /// Kilitli kabiliyet var mı (her zaman 0).
    static var lockedCount: Int {
        SafetyCapability.allCases.filter { SafetyPolicy.isLocked($0) }.count
    }
}
