import Foundation

/// ADIM 13 — uygulama dağıtım gereksinimleri (TestFlight / App Store).
///
/// ## Neden çekirdekte?
/// `Info.plist` içeriği, arka plan modları ve izin metinleri sık sık
/// unutulan ve sürüm güncellemelerinde bozulan şeylerdir. Bu gereksinimleri
/// **veri olarak** burada tanımlayıp, gerçek `Info.plist` sözlüğüne karşı
/// doğruluyoruz: eksik izin metni, yanlış arka plan modu veya sürüm
/// numarası hatası derlemeden yakalanır.
///
/// ## Kapsam
/// - `watchOS` ana uygulaması
/// - `iOS` eşlikçi uygulaması
/// - `WidgetKit` komplikasyon uzantısı
public enum AppDistribution {

    // MARK: - Kimlik

    /// Bundle kimlikleri (üç hedef).
    public enum BundleID {
        public static let watchApp = "com.divelog.watch"
        public static let watchAppExtensionSuffix = ".watchkitapp"
        public static let iOSApp = "com.divelog.iphone"
        public static let widgetExtension = "com.divelog.watch.complications"

        /// watchOS hedefinin tam kimliği.
        public static var watchAppFull: String { watchApp + watchAppExtensionSuffix }
    }

    /// Sürümleme kuralı: `MAJOR.MINOR.PATCH` + monoton artan build.
    public static let minimumMarketingVersion = "1.0.0"
    public static let minimumBuildNumber = 1
    public static let currentVersion = "1.0.0"
    public static let currentBuild = 1

    /// Sürüm dizesi geçerli mi? (`1.2.3` biçimi)
    public static func isValidVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".")
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return false }
            return Int(part) != nil
        }
    }

    /// Build numarası pozitif tam sayı mı?
    public static func isValidBuildNumber(_ build: Int) -> Bool { build >= 1 }

    /// İki sürümü **sayısal** olarak karşılaştırır.
    ///
    /// - Note: Sözlüksel karşılaştırma yanlış sonuç verir: `"9.0" < "10.0"`
    ///   ifadesi `true` dönerken doğrusu `false` olmalıdır (9 < 10).
    ///   Bu hata MinimumOSVersion denetimini sessizce geçersiz kılardı.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        if left == right { return .orderedSame }
        for (l, r) in zip(left, right) where l != r {
            return l < r ? .orderedAscending : .orderedDescending
        }
        // Uzunluk farkı: eksik bileşenler 0 sayılır (1.0 < 1.0.1)
        return left.count < right.count ? .orderedAscending : .orderedDescending
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    // MARK: - Kullanım açıklama metinleri

    /// `NS…UsageDescription` anahtarları — iOS tarafı.
    ///
    /// - Note: Apple, **her** izin için kullanıcıya gösterilecek açıklama
    ///   metni zorunlu kılar; eksik metin App Store incelemesinde reddedilir.
    public static let iOSUsageDescriptions: [String: String] = [
        "NSLocationWhenInUseUsageDescription":
            "Dalış rotanızı haritada gösterebilmek için konumunuzu kullanır. "
            + "Konum yalnızca dalış sırasında ve yüzeyde kaydedilir.",
        "NSLocationAlwaysAndWhenInUseUsageDescription":
            "Dalış sonrası uçuş yasağı sayacını ve dalış günlüğünü güncel tutmak "
            + "için arka planda konumunuzu kullanır.",
        "NSMotionUsageDescription":
            "Derinlik ve hareket verisinden dalış profilini oluşturur.",
        "NSHealthShareUsageDescription":
            "Dalış verilerinizi Apple Health ile paylaşmak isterseniz okuma izni istenir.",
        "NSHealthUpdateUsageDescription":
            "Dalış kayıtlarınızı Apple Health'e yazmak için yazma izni istenir.",
        "NSBluetoothAlwaysUsageDescription":
            "Su altı sensör verisini watch'ınıza aktarmak için Bluetooth kullanır."
    ]

    /// `NS…UsageDescription` anahtarları — watchOS tarafı.
    public static let watchUsageDescriptions: [String: String] = [
        "NSLocationWhenInUseUsageDescription":
            "Dalış noktanızı günlüğe kaydetmek için konumunuzu kullanır.",
        "NSMotionUsageDescription":
            "Dalış derinliğinizi CoreMotion sensöründen ölçmek için hareket "
            + "verilerinizi kullanır."
    ]

    /// Kullanım açıklaması olması **zorunlu** olan izinler.
    public static let requiredUsageDescriptionKeys: Set<String> = [
        "NSLocationWhenInUseUsageDescription",
        "NSMotionUsageDescription"
    ]

    // MARK: - Arka plan modları

    /// `UIBackgroundModes` değerleri.
    public enum BackgroundMode {
        /// Konum takibi (dalış noktası, uçuş yasağı)
        public static let location = "location"
        /// Workout oturumu (Apple Watch'ta dalış = workout)
        public static let workout = "workout-processing"
        /// Sensör verisi toplama
        public static let processing = "processing"
        /// Dalış bilgisayarı arka planı (dekomp.)
        public static let diveComputer = "dive-computer"
    }

    /// watchOS uygulaması için gereken arka plan modları.
    ///
    /// - Note: `dive-computer` ve `workout-processing` birlikte kullanılır:
    ///   workout oturumu su altı kaydını, dive-computer modu ise dalış
    ///   dışındayken uçuş yasağı takibini sürdürür.
    public static let watchBackgroundModes: [String] = [
        BackgroundMode.workout,
        BackgroundMode.diveComputer,
        BackgroundMode.location
    ]

    /// iOS uygulaması için gereken arka plan modları.
    ///
    /// - Note: `processing` + `BGTaskSchedulerPermittedIdentifiers` eşliğinde
    ///   senkronizasyonu; `fetch` eşlikçiden gelen anlık tetikleme.
    public static let iOSBackgroundModes: [String] = [
        BackgroundMode.processing,
        "fetch"
    ]

    /// `BGTaskScheduler` görev tanımlayıcıları (plist ile eşleşmeli).
    public static let backgroundTaskIdentifiers: [String] = [
        "com.divelog.iphone.sync"
    ]

    /// Widget uzantısı için gereken arka plan modları (genellikle yoktur).
    public static let widgetBackgroundModes: [String] = []

    // MARK: - Zorunlu Info.plist anahtarları

    /// Her hedefte bulunması gereken anahtarlar.
    public static let requiredKeys: Set<String> = [
        "CFBundleDevelopmentRegion",
        "CFBundleExecutable",
        "CFBundleIdentifier",
        "CFBundleInfoDictionaryVersion",
        "CFBundleName",
        "CFBundlePackageType",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "LSRequiresIPhoneOS",
        "UIRequiredDeviceCapabilities",
        "UISupportedInterfaceOrientations"
    ]

    // MARK: - watchOS hedefi

    /// Bir platformun doğrulama gereksinimleri.
    public struct Requirements: Sendable {
        public let name: String
        public let requiredKeys: Set<String>
        public let usageDescriptions: [String: String]
        public let requiredBackgroundModes: [String]
        public let expectedBundleID: String
        public let minimumSystemVersion: String
        public let deviceFamilies: [Int]

        public init(name: String,
                    requiredKeys: Set<String>,
                    usageDescriptions: [String: String],
                    requiredBackgroundModes: [String],
                    expectedBundleID: String,
                    minimumSystemVersion: String,
                    deviceFamilies: [Int]) {
            self.name = name
            self.requiredKeys = requiredKeys
            self.usageDescriptions = usageDescriptions
            self.requiredBackgroundModes = requiredBackgroundModes
            self.expectedBundleID = expectedBundleID
            self.minimumSystemVersion = minimumSystemVersion
            self.deviceFamilies = deviceFamilies
        }
    }

    /// watchOS uygulaması gereksinimleri.
    public static let watchAppRequirements = Requirements(
        name: "watchOS App",
        requiredKeys: requiredKeys,
        usageDescriptions: watchUsageDescriptions,
        requiredBackgroundModes: watchBackgroundModes,
        expectedBundleID: BundleID.watchAppFull,
        minimumSystemVersion: "10.0",
        deviceFamilies: [4])            // 4 = watch

    /// iOS eşlikçi gereksinimleri.
    public static let iOSAppRequirements = Requirements(
        name: "iOS App",
        requiredKeys: requiredKeys,
        usageDescriptions: iOSUsageDescriptions,
        requiredBackgroundModes: iOSBackgroundModes,
        expectedBundleID: BundleID.iOSApp,
        minimumSystemVersion: "17.0",
        deviceFamilies: [1, 2])          // 1 = iPhone, 2 = iPad

    /// Widget uzantısı gereksinimleri.
    public static let widgetRequirements = Requirements(
        name: "WidgetKit Extension",
        requiredKeys: requiredKeys,
        usageDescriptions: [:],
        requiredBackgroundModes: widgetBackgroundModes,
        expectedBundleID: BundleID.widgetExtension,
        minimumSystemVersion: "10.0",
        deviceFamilies: [4])

    /// Tüm hedeflerin gereksinimleri.
    public static let allRequirements: [Requirements] = [
        watchAppRequirements, iOSAppRequirements, widgetRequirements
    ]

    // MARK: - Doğrulama

    /// Doğrulama sonucu.
    public struct Validation: Equatable, Sendable, Identifiable {
        public enum Severity: String, Equatable, Sendable, Comparable {
            case error, warning
            public static func < (lhs: Severity, rhs: Severity) -> Bool {
                lhs == .error && rhs == .warning
            }
        }

        public let id: String
        public let severity: Severity
        public let message: String

        public init(id: String, severity: Severity, message: String) {
            self.id = id
            self.severity = severity
            self.message = message
        }
    }

    /// Bir `Info.plist` sözlüğünü gereksinimlere karşı doğrular.
    ///
    /// - Parameters:
    ///   - plist: Yüklenmiş `Info.plist` sözlüğü
    ///   - requirements: Hedef gereksinimleri
    public static func validate(plist: [String: Any],
                                requirements: Requirements) -> [Validation] {
        var results: [Validation] = []

        // 1) Zorunlu anahtarlar
        for key in requirements.requiredKeys.sorted() {
            if plist[key] == nil {
                results.append(Validation(id: "missing.\(key)", severity: .error,
                                          message: "Zorunlu anahtar eksik: \(key)"))
            }
        }

        // 2) Bundle kimliği
        if let bundleID = plist["CFBundleIdentifier"] as? String,
           bundleID != requirements.expectedBundleID {
            results.append(Validation(
                id: "bundleID", severity: .error,
                message: "Bundle kimliği \(bundleID) beklenen \(requirements.expectedBundleID) değil"))
        }

        // 3) Sürümleme
        if let version = plist["CFBundleShortVersionString"] as? String {
            if !isValidVersion(version) {
                results.append(Validation(id: "version", severity: .error,
                                          message: "Sürüm biçimi geçersiz: \(version)"))
            } else if compare(version, minimumMarketingVersion) == .orderedAscending {
                results.append(Validation(
                    id: "version", severity: .warning,
                    message: "Sürüm \(version) minimum \(minimumMarketingVersion) altında"))
            }
        }
        if let build = plist["CFBundleVersion"] as? Int {
            if !isValidBuildNumber(build) {
                results.append(Validation(id: "build", severity: .error,
                                          message: "Build numarası geçersiz: \(build)"))
            }
        } else if plist["CFBundleVersion"] != nil {
            results.append(Validation(id: "build", severity: .error,
                                      message: "CFBundleVersion tam sayı olmalı"))
        }

        // 4) Kullanım açıklamaları
        for key in requiredUsageDescriptionKeys.sorted()
        where requirements.usageDescriptions[key] != nil {
            let value = plist[key] as? String ?? ""
            if value.isEmpty {
                results.append(Validation(
                    id: "usage.\(key)", severity: .error,
                    message: "Kullanım açıklaması boş: \(key) (App Store reddi)"))
            } else if value.count < 20 {
                results.append(Validation(
                    id: "usage.\(key)", severity: .warning,
                    message: "Kullanım açıklaması çok kısa: \(key)"))
            }
        }
        // Tanımlı ama plistte olmayan açıklamalar
        for key in requirements.usageDescriptions.keys.sorted()
        where plist[key] == nil {
            results.append(Validation(
                id: "usage.missing.\(key)", severity: .error,
                message: "İzin metni tanımlı ama plistte yok: \(key)"))
        }

        // 5) Arka plan modları
        let modes = plist["UIBackgroundModes"] as? [String] ?? []
        for mode in requirements.requiredBackgroundModes where !modes.contains(mode) {
            results.append(Validation(
                id: "background.\(mode)", severity: .error,
                message: "Arka plan modu eksik: \(mode)"))
        }
        // İzin verilmeyen modlar
        let allowed = Set(requirements.requiredBackgroundModes)
        for mode in modes.sorted() where !allowed.contains(mode) {
            results.append(Validation(
                id: "background.unexpected.\(mode)", severity: .warning,
                message: "Tanımlı olmayan arka plan modu: \(mode)"))
        }

        // 6) Minimum sistem sürümü
        if let minOS = plist["MinimumOSVersion"] as? String,
           compare(minOS, requirements.minimumSystemVersion) == .orderedAscending {
            results.append(Validation(
                id: "minOS", severity: .error,
                message: "MinimumOSVersion \(minOS) < \(requirements.minimumSystemVersion)"))
        }

        // 7) Cihaz ailesi
        if let families = plist["UIDeviceFamily"] as? [Int] {
            let expected = Set(requirements.deviceFamilies)
            for family in families where !expected.contains(family) {
                results.append(Validation(
                    id: "deviceFamily.\(family)", severity: .warning,
                    message: "Beklenmeyen cihaz ailesi: \(family)"))
            }
        }

        return results
    }

    /// Doğrulamanın geçip geçmediği.
    public static func passes(_ validations: [Validation]) -> Bool {
        !validations.contains { $0.severity == .error }
    }

    // MARK: - Yetkilendirme (entitlements)

    /// Gerekli yetkilendirme anahtarları.
    public static let requiredEntitlements: [String] = [
        "com.apple.developer.healthkit",
        "com.apple.developer.healthkit.access"
    ]

    /// Yetki doğrulaması.
    public static func validate(entitlements: [String: Any]) -> [Validation] {
        var results: [Validation] = []
        for key in requiredEntitlements {
            if entitlements[key] == nil {
                results.append(Validation(id: "entitlement.\(key)", severity: .error,
                                          message: "Yetkilendirme eksik: \(key)"))
            }
        }
        return results
    }

    // MARK: - Sürüm kontrol listesi

    /// Bir bölüm (checklist adımı).
    public struct ChecklistItem: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String
        public let isRequired: Bool
    }

    /// TestFlight öncesi kontrol listesi.
    public static let releaseChecklist: [ChecklistItem] = [
        ChecklistItem(id: "plist.watch", title: "watchOS Info.plist",
                      detail: "Tüm zorunlu anahtarlar, izin metinleri ve "
                            + "arka plan modları (workout, dive-computer, location) doğrulanmalı",
                      isRequired: true),
        ChecklistItem(id: "plist.ios", title: "iOS Info.plist",
                      detail: "Konum, hareket ve HealthKit izin metinleri eksiksiz olmalı",
                      isRequired: true),
        ChecklistItem(id: "plist.widget", title: "Widget Info.plist",
                      detail: "Komplikasyon uzantısı tanımlayıcısı ve sürüm eşleşmeli",
                      isRequired: true),
        ChecklistItem(id: "version", title: "Sürüm ve build numarası",
                      detail: "MAJOR.MINOR.PATCH biçiminde; build sayı artırılmış olmalı",
                      isRequired: true),
        ChecklistItem(id: "signing", title: "İmzalama",
                      detail: "Otomatik imzalama, Apple Development ve Distribution "
                            + "profilleri ekipte tanımlı olmalı",
                      isRequired: true),
        ChecklistItem(id: "entitlements", title: "Entitlements",
                      detail: "HealthKit açık olmalı; capability her hedefte ayrı ayrı eklenmeli",
                      isRequired: true),
        ChecklistItem(id: "icons", title: "Uygulama simgeleri",
                      detail: "watchOS tek boyut (1024), iOS tüm boyutlar; 1024 kare PNG "
                            + "olmadan **yüklenemez**",
                      isRequired: true),
        ChecklistItem(id: "complications", title: "Komplikasyon önizlemeleri",
                      detail: "Dört modül aile için ayrı önizleme görseli gerekli",
                      isRequired: false),
        ChecklistItem(id: "privacy", title: "Gizlilik bildirimi",
                      detail: "Konum, hareket ve sağlık verisi için App Store "
                            + "veri toplama beyanı güncellenmeli",
                      isRequired: true),
        ChecklistItem(id: "hardware", title: "Gerçek cihaz testi",
                      detail: "Apple Watch Ultra'da derinlik sensörü kalibrasyonu ve "
                            + "su kilidi akışı doğrulanmalı",
                      isRequired: true)
    ]
}
