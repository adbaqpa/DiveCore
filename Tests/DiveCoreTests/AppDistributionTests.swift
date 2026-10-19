import XCTest
@testable import DiveCore

/// ADIM 13 — dağıtım hazırlığı: `Info.plist` gereksinimleri, sürümleme,
/// yetkilendirme ve kontrol listesi.
///
/// ## Neden test?
/// `Info.plist` hataları derlemede **görünmez**; uygulama yüklenir, App
/// Store'a gider ve orada reddedilir. Bu testler, gereksinimleri gerçek
/// plist dosyalarına karşı doğrular; CI'a eklenebilir.
final class AppDistributionTests: XCTestCase {

    // MARK: - Yardımcılar

    /// Tüm zorunlu alanları taşıyan geçerli bir plist.
    private func validWatchPlist() -> [String: Any] {
        var plist: [String: Any] = [:]
        for key in AppDistribution.requiredKeys {
            switch key {
            case "CFBundleVersion": plist[key] = 1
            case "LSRequiresIPhoneOS": plist[key] = true
            case "UIRequiredDeviceCapabilities": plist[key] = ["arm64"]
            case "UISupportedInterfaceOrientations": plist[key] = ["UIInterfaceOrientationPortrait"]
            default: plist[key] = "deger"
            }
        }
        plist["CFBundleIdentifier"] = AppDistribution.BundleID.watchAppFull
        plist["CFBundleShortVersionString"] = AppDistribution.currentVersion
        plist["MinimumOSVersion"] = AppDistribution.watchAppRequirements.minimumSystemVersion
        plist["UIDeviceFamily"] = AppDistribution.watchAppRequirements.deviceFamilies
        for (key, text) in AppDistribution.watchUsageDescriptions {
            plist[key] = text
        }
        plist["UIBackgroundModes"] = AppDistribution.watchBackgroundModes
        return plist
    }

    // MARK: - Sürümleme

    func testVersionFormat() {
        XCTAssertTrue(AppDistribution.isValidVersion("1.0.0"))
        XCTAssertTrue(AppDistribution.isValidVersion("2.13.4"))
        XCTAssertFalse(AppDistribution.isValidVersion("1.0"))
        XCTAssertFalse(AppDistribution.isValidVersion("1.0.0.0"))
        XCTAssertFalse(AppDistribution.isValidVersion("1.0.x"))
        XCTAssertFalse(AppDistribution.isValidVersion(""))
    }

    func testBuildNumberIsPositive() {
        XCTAssertTrue(AppDistribution.isValidBuildNumber(1))
        XCTAssertTrue(AppDistribution.isValidBuildNumber(999))
        XCTAssertFalse(AppDistribution.isValidBuildNumber(0))
        XCTAssertFalse(AppDistribution.isValidBuildNumber(-1))
    }

    func testCurrentVersionMeetsMinimums() {
        XCTAssertTrue(AppDistribution.isValidVersion(AppDistribution.currentVersion))
        XCTAssertTrue(AppDistribution.isValidBuildNumber(AppDistribution.currentBuild))
        XCTAssertGreaterThanOrEqual(AppDistribution.currentVersion,
                                    AppDistribution.minimumMarketingVersion)
    }

    /// Sözlüksel karşılaştırma hatasına karşı koruma:
    /// "9.0" sözlüksel olarak "10.0"dan büyüktür ama sayısal olarak küçüktür.
    func testVersionComparisonIsNumericNotLexical() {
        XCTAssertEqual(AppDistribution.compare("1.0.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(AppDistribution.compare("9.0", "10.0"), .orderedAscending)
        XCTAssertEqual(AppDistribution.compare("10.0", "9.0"), .orderedDescending)
        XCTAssertEqual(AppDistribution.compare("1.2", "1.10"), .orderedAscending)
        XCTAssertEqual(AppDistribution.compare("1.0.1", "1.0.0"), .orderedDescending)
    }

    func testBundleIdentifiersAreDistinct() {
        let ids = [AppDistribution.BundleID.watchAppFull,
                   AppDistribution.BundleID.iOSApp,
                   AppDistribution.BundleID.widgetExtension]
        XCTAssertEqual(Set(ids).count, 3, "Bundle kimlikleri benzersiz olmalı")
        XCTAssertTrue(ids.allSatisfy { $0.hasSuffix("divelog") || $0.contains("divelog") })
    }

    // MARK: - Geçerli plist

    func testValidWatchPlistPasses() {
        let results = AppDistribution.validate(plist: validWatchPlist(),
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(AppDistribution.passes(results),
                      "Geçerli plist doğrulamadan geçmeli: \(results.map(\.message))")
    }

    // MARK: - Eksik anahtarlar

    func testMissingRequiredKeyIsError() {
        var plist = validWatchPlist()
        plist.removeValue(forKey: "CFBundleName")
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains {
            $0.id == "missing.CFBundleName" && $0.severity == .error
        })
        XCTAssertFalse(AppDistribution.passes(results))
    }

    func testAllRequiredKeysAreChecked() {
        var plist = validWatchPlist()
        for key in AppDistribution.requiredKeys { plist.removeValue(forKey: key) }
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        let missing = results.filter { $0.id.hasPrefix("missing.") }
        XCTAssertEqual(missing.count, AppDistribution.requiredKeys.count)
    }

    // MARK: - Bundle kimliği

    func testWrongBundleIDIsError() {
        var plist = validWatchPlist()
        plist["CFBundleIdentifier"] = "com.somethingelse"
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains { $0.id == "bundleID" && $0.severity == .error })
    }

    // MARK: - Sürüm hataları

    func testInvalidVersionIsError() {
        var plist = validWatchPlist()
        plist["CFBundleShortVersionString"] = "1.0"
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains { $0.id == "version" && $0.severity == .error })
    }

    func testNonNumericBuildIsError() {
        var plist = validWatchPlist()
        plist["CFBundleVersion"] = "one"
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains { $0.id == "build" && $0.severity == .error })
    }

    // MARK: - İzin metinleri

    func testEmptyUsageDescriptionIsError() {
        var plist = validWatchPlist()
        plist["NSMotionUsageDescription"] = ""
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains {
            $0.id.hasPrefix("usage.NSMotion") && $0.severity == .error
        })
    }

    func testShortUsageDescriptionIsWarning() {
        var plist = validWatchPlist()
        plist["NSMotionUsageDescription"] = "Hareket"
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        let warning = results.first { $0.id == "usage.NSMotionUsageDescription" }
        XCTAssertEqual(warning?.severity, .warning,
                       "Kısa metin reddedilmez ama uyarılır")
        XCTAssertTrue(AppDistribution.passes(results))
    }

    func testMissingUsageDescriptionIsError() {
        var plist = validWatchPlist()
        plist.removeValue(forKey: "NSLocationWhenInUseUsageDescription")
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains {
            $0.id == "usage.missing.NSLocationWhenInUseUsageDescription"
            && $0.severity == .error
        })
    }

    func testAllIOSUsageDescriptionsAreMeaningful() {
        for (key, text) in AppDistribution.iOSUsageDescriptions {
            XCTAssertTrue(key.hasPrefix("NS"), "\(key) NS öneki taşımalı")
            XCTAssertGreaterThan(text.count, 20, "\(key) metni anlamlı uzunlukta olmalı")
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertTrue(AppDistribution.iOSUsageDescriptions.keys
            .contains("NSLocationWhenInUseUsageDescription"))
        XCTAssertTrue(AppDistribution.iOSUsageDescriptions.keys
            .contains("NSHealthShareUsageDescription"))
    }

    func testWatchUsageDescriptionsAreSubsetOfIOS() {
        for key in AppDistribution.watchUsageDescriptions.keys {
            XCTAssertTrue(AppDistribution.iOSUsageDescriptions.keys.contains(key),
                          "\(key) iOS tarafında da tanımlı olmalı")
        }
    }

    // MARK: - Arka plan modları

    func testMissingBackgroundModeIsError() {
        var plist = validWatchPlist()
        plist["UIBackgroundModes"] = [AppDistribution.BackgroundMode.workout]
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains {
            $0.id == "background.dive-computer" && $0.severity == .error
        })
    }

    func testAllWatchBackgroundModesRequired() {
        var plist = validWatchPlist()
        plist["UIBackgroundModes"] = []
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        let missing = results.filter {
            $0.severity == .error && $0.id.hasPrefix("background.")
        }
        XCTAssertEqual(missing.count, AppDistribution.watchBackgroundModes.count)
    }

    func testDiveComputerAndWorkoutModesPresent() {
        XCTAssertTrue(AppDistribution.watchBackgroundModes
            .contains(AppDistribution.BackgroundMode.diveComputer),
                      "Dalış bilgisayarı arka plan modu zorunlu")
        XCTAssertTrue(AppDistribution.watchBackgroundModes
            .contains(AppDistribution.BackgroundMode.workout))
    }

    func testUnexpectedBackgroundModeIsWarning() {
        var plist = validWatchPlist()
        plist["UIBackgroundModes"] = AppDistribution.watchBackgroundModes + ["voip"]
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        let warning = results.first { $0.id == "background.unexpected.voip" }
        XCTAssertEqual(warning?.severity, .warning)
        XCTAssertTrue(AppDistribution.passes(results))
    }

    func testWidgetHasNoBackgroundModes() {
        XCTAssertTrue(AppDistribution.widgetBackgroundModes.isEmpty,
                      "Widget uzantısında arka plan modu bildirilmez")
    }

    // MARK: - Platform

    func testMinimumOSVersionChecked() {
        var plist = validWatchPlist()
        plist["MinimumOSVersion"] = "9.0"
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertTrue(results.contains { $0.id == "minOS" && $0.severity == .error })
    }

    func testDeviceFamilyChecked() {
        var plist = validWatchPlist()
        plist["UIDeviceFamily"] = [1, 2]     // iPhone/iPad, watch değil
        let results = AppDistribution.validate(plist: plist,
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertFalse(results.filter { $0.id.hasPrefix("deviceFamily") }.isEmpty)
    }

    func testWatchOnlyTargetsWatch() {
        XCTAssertEqual(AppDistribution.watchAppRequirements.deviceFamilies, [4])
        XCTAssertEqual(AppDistribution.iOSAppRequirements.deviceFamilies, [1, 2])
    }

    // MARK: - Yetkilendirme

    func testHealthKitEntitlementRequired() {
        let results = AppDistribution.validate(entitlements: [:])
        XCTAssertEqual(results.count, AppDistribution.requiredEntitlements.count)
        XCTAssertTrue(results.allSatisfy { $0.severity == .error })
    }

    func testValidEntitlementsPass() {
        var entitlements: [String: Any] = [:]
        for key in AppDistribution.requiredEntitlements { entitlements[key] = true }
        XCTAssertTrue(AppDistribution.passes(
            AppDistribution.validate(entitlements: entitlements)))
    }

    // MARK: - Kontrol listesi

    func testChecklistHasRequiredItems() {
        XCTAssertFalse(AppDistribution.releaseChecklist.isEmpty)
        let required = AppDistribution.releaseChecklist.filter(\.isRequired)
        XCTAssertGreaterThanOrEqual(required.count, 8)
        for item in AppDistribution.releaseChecklist {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.detail.isEmpty)
        }
    }

    func testChecklistCoversCriticalAreas() {
        let ids = Set(AppDistribution.releaseChecklist.map(\.id))
        for expected in ["plist.watch", "plist.ios", "version", "signing",
                         "entitlements", "icons", "privacy", "hardware"] {
            XCTAssertTrue(ids.contains(expected), "\(expected) listede olmalı")
        }
    }

    func testChecklistIdsAreUnique() {
        let ids = AppDistribution.releaseChecklist.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Gereksinim modeli

    func testAllRequirementsAreWellFormed() {
        for requirement in AppDistribution.allRequirements {
            XCTAssertFalse(requirement.name.isEmpty)
            XCTAssertFalse(requirement.requiredKeys.isEmpty)
            XCTAssertFalse(requirement.expectedBundleID.isEmpty)
            XCTAssertFalse(requirement.minimumSystemVersion.isEmpty)
            XCTAssertTrue(AppDistribution.isValidVersion(
                AppDistribution.currentVersion))
        }
    }

    func testRequiredKeysAreSubsetOfEveryRequirement() {
        for requirement in AppDistribution.allRequirements {
            XCTAssertTrue(AppDistribution.requiredKeys.isSubset(of: requirement.requiredKeys))
        }
    }

    func testBackgroundTaskIdentifiersAreVersioned() {
        for identifier in AppDistribution.backgroundTaskIdentifiers {
            XCTAssertTrue(identifier.contains("."), identifier)
            XCTAssertTrue(identifier.hasSuffix(".sync"))
        }
    }

    // MARK: - Boş plist

    func testEmptyPlistFails() {
        let results = AppDistribution.validate(plist: [:],
                                              requirements: AppDistribution.watchAppRequirements)
        XCTAssertFalse(AppDistribution.passes(results))
    }

    // MARK: - Gerçek plist dosyaları (yalnızca paket kökünde varsa)

    private func plist(at path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
    }

    /// Depodaki gerçek `App/*/Info.plist` dosyaları doğrulamadan geçmeli.
    ///
    /// - Note: Çalışma dizini farklıysa test atlanır (paket dışından
    ///   çalıştırıldığında sessiz hata vermektense atlamak daha iyidir).
    func testRepositoryPlistsAreValid() {
        let root = FileManager.default.currentDirectoryPath
        let cases: [(String, AppDistribution.Requirements)] = [
            ("App/watchOS/Info.plist", AppDistribution.watchAppRequirements),
            ("App/iOS/Info.plist", AppDistribution.iOSAppRequirements),
            ("App/WidgetExtension/Info.plist", AppDistribution.widgetRequirements)
        ]
        for (path, requirements) in cases {
            guard let plist = plist(at: "\(root)/\(path)") else {
                // Paket dışından çalıştırıldığında dosya yoktur; sessizce geç
                return
            }
            let results = AppDistribution.validate(plist: plist,
                                                  requirements: requirements)
            let errors = results.filter { $0.severity == .error }
            XCTAssertTrue(errors.isEmpty,
                          "\(path): \(errors.map(\.message).joined(separator: ", "))")
        }
    }

    /// `Config/*.xcconfig` dosyaları sürümleme değerlerini taşımalı.
    func testXcconfigFilesDeclareVersioning() {
        let root = FileManager.default.currentDirectoryPath
        let path = "\(root)/Config/Base.xcconfig"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return   // paket dışından çalıştırıldığında dosya yok
        }
        XCTAssertTrue(text.contains("MARKETING_VERSION = \(AppDistribution.currentVersion)"),
                      "xcconfig sürümü çekirdekle eşleşmeli")
        XCTAssertTrue(text.contains("CURRENT_PROJECT_VERSION = \(AppDistribution.currentBuild)"))
    }
}
