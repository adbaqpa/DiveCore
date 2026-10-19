import Foundation

/// ADIM 3 — App Store Connect **App Privacy** beyanı.
///
/// ## Neden kodda?
/// App Store Connect'teki "App Privacy" bölümü onlarca veri tipi sunar ve
/// yanlış seçim hem reddi hem de kullanıcı yanıltmasına yol açar. Beyan
/// burada tanımlanır ve **gerçek kod davranışıyla** karşılaştırılabilir;
/// yeni bir veri toplama eklendiğinde beyanın güncellenmesi gerektiği
/// testlerle hatırlatılır.
///
/// ## Kritik ayrım: "toplama" ne demek?
/// Apple, verinin **uygulama dışına çıkması** hâlinde "Collected" der.
/// Veri yalnızca **cihazda** kalıyorsa `Not Collected` denir ve
/// "işlenmeden önce şifrelenir" gibi ifadeler gerekmez. DiveLog'da
/// durumlar aşağıda açıkça ayrılmıştır.
public enum AppPrivacy {

    // MARK: - Apple veri tipleri (App Store Connect listesiyle eşleşir)

    /// Veri tipi.
    public enum DataType: String, CaseIterable, Codable, Sendable, Identifiable {
        case healthAndFitness
        case location
        case userContent
        case identifiers
        case purchases
        case diagnostics

        public var id: String { rawValue }

        /// App Store Connect'teki görünen ad (TR).
        public var turkishName: String {
            switch self {
            case .healthAndFitness: return "Sağlık ve Fitness"
            case .location: return "Konum"
            case .userContent: return "Kullanıcı İçeriği"
            case .identifiers: return "Tanımlayıcılar"
            case .purchases: return "Satın Alımlar"
            case .diagnostics: return "Tanılama"
            }
        }

        /// Bağlı alt tipler.
        public var subtypes: [String] {
            switch self {
            case .healthAndFitness:
                return ["Dalış verileri", "Deri temizlenmesi (dekompresyon)"]
            case .location:
                return ["Kaba konum", " Hassas konum"]
            case .userContent:
                return ["Dalış günlüğü ve notlar"]
            case .identifiers:
                return ["Cihaz Kimliği"]
            case .purchases:
                return ["Satın alma geçmişi"]
            case .diagnostics:
                return ["Çökme ve performans"]
            }
        }
    }

    /// Toplama biçimi.
    public enum Collection: String, Codable, Sendable {
        /// Cihaz dışına çıkmaz
        case notCollected
        /// Yalnızca iCloud (Apple'ın özel kapsayıcısı) içinde
        case privateCloudOnly
        /// Uygulamanın kendi sunucusuna gider
        case appServer
    }

    /// Kullanım amacı.
    public enum Purpose: String, Codable, Sendable {
        case appFunctionality
        case analytics
        case advertising
    }

    // MARK: - Beyan girdisi

    /// Tek bir beyan satırı.
    public struct Declaration: Equatable, Codable, Sendable, Identifiable {
        public let dataType: DataType
        public let collection: Collection
        public let purposes: [Purpose]
        public let isLinkedToUser: Bool
        public let isUsedForTracking: Bool
        /// Yalnızca iCloud özel alanına gidiyorsa veriler şifrelenir
        public let isEncryptedAtRest: Bool
        /// Kullanıcıdan silme talebi alınabiliyor mu
        public let supportsDeletion: Bool

        public var id: String { dataType.rawValue }

        public init(dataType: DataType,
                    collection: Collection,
                    purposes: [Purpose],
                    isLinkedToUser: Bool,
                    isUsedForTracking: Bool,
                    isEncryptedAtRest: Bool,
                    supportsDeletion: Bool) {
            self.dataType = dataType
            self.collection = collection
            self.purposes = purposes
            self.isLinkedToUser = isLinkedToUser
            self.isUsedForTracking = isUsedForTracking
            self.isEncryptedAtRest = isEncryptedAtRest
            self.supportsDeletion = supportsDeletion
        }
    }

    // MARK: - Beyan listesi

    /// Bu uygulamanın beyanı.
    ///
    /// - Important: **Tracking (izleme) hiçbir veri tipi için `true`
    ///   değildir.** Apple, ATT (App Tracking Transparency) zorunluluğunu
    ///   tetikleyen bir beyanı reklam amaçlı veri aktarımı sayar. DiveLog
    ///   reklam ağı kullanmadığı için hiçbir veri tipinde izleme bildirilmez
    ///   ve `NSUserTrackingUsageDescription` gerekmez.
    public static let declarations: [Declaration] = [
        Declaration(dataType: .location,
                    collection: .privateCloudOnly,
                    purposes: [.appFunctionality],
                    isLinkedToUser: true,
                    isUsedForTracking: false,
                    isEncryptedAtRest: true,
                    supportsDeletion: true),

        Declaration(dataType: .healthAndFitness,
                    collection: .privateCloudOnly,
                    purposes: [.appFunctionality],
                    isLinkedToUser: true,
                    isUsedForTracking: false,
                    isEncryptedAtRest: true,
                    supportsDeletion: true),

        Declaration(dataType: .userContent,
                    collection: .privateCloudOnly,
                    purposes: [.appFunctionality],
                    isLinkedToUser: true,
                    isUsedForTracking: false,
                    isEncryptedAtRest: true,
                    supportsDeletion: true),

        // Cihaz kimliği senkronizasyonda karşılaştırma anahtarı olarak
        // kullanılır; cihaz dışına çıkmaz.
        Declaration(dataType: .identifiers,
                    collection: .notCollected,
                    purposes: [.appFunctionality],
                    isLinkedToUser: false,
                    isUsedForTracking: false,
                    isEncryptedAtRest: false,
                    supportsDeletion: true),

        // Satın alma bilgisi Apple'ın kendi sisteminde tutulur; uygulama
        // Apple sunucusuna veri göndermez.
        Declaration(dataType: .purchases,
                    collection: .notCollected,
                    purposes: [.appFunctionality],
                    isLinkedToUser: false,
                    isUsedForTracking: false,
                    isEncryptedAtRest: false,
                    supportsDeletion: true)
    ]

    // MARK: - SSS

    /// Sık sorulan sorulara doğrudan cevaplar (App Store Connect'te
    /// açıklama alanlarına yazılacak).
    public struct FAQ: Equatable, Sendable, Identifiable {
        public let question: String
        public let answer: String
        public var id: String { question }
    }

    public static let faq: [FAQ] = [
        FAQ(question: "Verileriniz sunucularınıza gönderiliyor mu?",
            answer: "Hayır. Tüm dalış verileri cihazda ve kullanıcının kendi "
                 + "iCloud gizli alanında saklanır. Uygulamanın çalışması için "
                 + "gereken tek ağ trafiği Apple'ın StoreKit ve HealthKit "
                 + "sistemleridir."),

        FAQ(question: "Reklam veya izleme yapıyor musunuz?",
            answer: "Hayır. Uygulamada üçüncü taraf reklam SDK'sı, analitik "
                 + "servisi veya çerez/pazarlama teknolojisi bulunmaz. "
                 + "App Tracking Transparency uyarısı gösterilmez."),

        FAQ(question: "Veriler üçüncü taraflarla paylaşılıyor mu?",
            answer: "Yalnızca kullanıcı kendi isteğiyle dışa aktarma veya "
                 + "sistem paylaşımı yaparsa. Bu durumda veri, kullanıcının "
                 + "seçtiği uygulamaya gider ve o uygulamanın gizlilik "
                 + "politikası geçerlidir."),

        FAQ(question: "Hesap açmam gerekiyor mu?",
            answer: "Hayır. Uygulamada kullanıcı hesabı, oturum açma veya "
                 + "şifre yoktur. Tek kimlik doğrulama, Apple'ın ödeme sistemidir."),

        FAQ(question: "Konumumu sürekli izliyor musunuz?",
            answer: "Hayır. Konum yalnızca dalış sırasında ve yüzeyde "
                 + "okunur (su altında GPS çözünürlüğü düşük ve pil tüketir). "
                 + "Arka planda konum izleme yapılmaz."),

        FAQ(question: "Verilerimi nasıl silerim?",
            answer: "Ayarlar → Tüm Verileri Sil, ya da uygulamayı silmek. "
                 + "iCloud senkronizasyonu açıksa Apple'dan da silinmelidir.")
    ]

    // MARK: - Sorgu yardımcıları

    public static func declaration(for dataType: DataType) -> Declaration? {
        declarations.first { $0.dataType == dataType }
    }

    /// Sunucuya gönderilen veri var mı? (olmamalı)
    public static var hasAppServerData: Bool {
        declarations.contains { $0.collection == .appServer }
    }

    /// Reklam/izleme amaçlı kullanılan veri var mı? (olmamalı)
    public static var hasTracking: Bool {
        declarations.contains { $0.isUsedForTracking }
    }

    /// Analitik amaçlı kullanılan veri var mı? (olmamalı)
    public static var hasAnalytics: Bool {
        declarations.contains { $0.purposes.contains(.analytics) }
    }

    /// Veriler silinebilir mi? (tümü için olmalı)
    public static var allSupportDeletion: Bool {
        declarations.allSatisfy(\.supportsDeletion)
    }
}
