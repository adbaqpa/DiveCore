import Foundation
import DiveCore

/// ADIM 13 — dağıtım yapılandırması doğrulayıcı.
///
/// `Info.plist` dosyalarını uygulama gereksinimlerine karşı doğrular ve
/// TestFlight öncesi kontrol listesini basar.
///
/// Kullanım:
/// ```sh
/// swift run PlistCheck                # tüm plist'leri doğrular
/// swift run PlistCheck --checklist    # kontrol listesi
/// swift run PlistCheck --usage        # izin metinleri
/// ```
///
/// Araç Xcode olmadan da çalışır; CI'a eklenebilir.

func section(_ title: String) {
    print("")
    print(String(repeating: "=", count: 70))
    print("  " + title)
    print(String(repeating: "=", count: 70))
}

func validatePlist(path: String, requirements: AppDistribution.Requirements) -> Bool {
    let shortPath = (path as NSString).lastPathComponent
    guard FileManager.default.fileExists(atPath: path) else {
        print("  ✗ \(shortPath) bulunamadı: \(path)")
        return false
    }
    guard let data = FileManager.default.contents(atPath: path),
          let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else {
        print("  ✗ \(shortPath) okunamadı (geçerli plist değil)")
        return false
    }

    let results = AppDistribution.validate(plist: plist, requirements: requirements)
    let errors = results.filter { $0.severity == .error }
    let warnings = results.filter { $0.severity == .warning }

    print("  \(errors.isEmpty ? "✓" : "✗") \(requirements.name) — \(shortPath)")
    print("    anahtar: \(plist.count) · izin metni: \(requirements.usageDescriptions.count)"
          + " · arka plan modu: \(requirements.requiredBackgroundModes.count)")

    for warning in warnings {
        print("    ! \(warning.message)")
    }
    for error in errors {
        print("    ✗ \(error.message)")
    }
    if results.isEmpty {
        print("    tüm gereksinimler karşılandı")
    }
    return errors.isEmpty
}

func runReleaseChecklist() {
    section("TestFlight Kontrol Listesi")
    let required = AppDistribution.releaseChecklist.filter(\.isRequired)
    let optional = AppDistribution.releaseChecklist.filter { !$0.isRequired }

    print("  Zorunlu (\(required.count)):")
    for (index, item) in required.enumerated() {
        print("   \(index + 1). [ ] \(item.title)")
        print("        \(item.detail)")
    }
    print("  Önerilen (\(optional.count)):")
    for item in optional {
        print("   • [ ] \(item.title) — \(item.detail)")
    }

    section("Sürümleme")
    print("  pazarlama sürümü : \(AppDistribution.currentVersion)")
    print("  build numarası   : \(AppDistribution.currentBuild)")
    print("  biçim geçerli    : \(AppDistribution.isValidVersion(AppDistribution.currentVersion))")
    print("  bundle kimlikleri:")
    print("    watchOS  \(AppDistribution.BundleID.watchAppFull)")
    print("    iOS      \(AppDistribution.BundleID.iOSApp)")
    print("    widget   \(AppDistribution.BundleID.widgetExtension)")
}

func runUsageReport() {
    section("Kullanım Açıklamaları")
    print("  iOS:")
    for (key, text) in AppDistribution.iOSUsageDescriptions.sorted(by: { $0.key < $1.key }) {
        print("    \(key)")
        print("      \(text)")
    }
    print("  watchOS:")
    for (key, text) in AppDistribution.watchUsageDescriptions.sorted(by: { $0.key < $1.key }) {
        print("    \(key)")
        print("      \(text)")
    }
}

let root = FileManager.default.currentDirectoryPath
var allValid = true

section("Info.plist Doğrulaması")
allValid = validatePlist(path: "\(root)/App/watchOS/Info.plist",
                         requirements: AppDistribution.watchAppRequirements) && allValid
allValid = validatePlist(path: "\(root)/App/iOS/Info.plist",
                         requirements: AppDistribution.iOSAppRequirements) && allValid
allValid = validatePlist(path: "\(root)/App/WidgetExtension/Info.plist",
                         requirements: AppDistribution.widgetRequirements) && allValid

let arguments = Set(CommandLine.arguments.dropFirst())
if arguments.contains("--checklist") || !allValid {
    runReleaseChecklist()
}
if arguments.contains("--usage") {
    runUsageReport()
}

print("")
if allValid {
    print("SONUÇ: TÜM DOĞRULAMALAR GEÇTİ ✓")
} else {
    print("SONUÇ: DOĞRULAMA HATALARI VAR ✗")
    exit(1)
}
