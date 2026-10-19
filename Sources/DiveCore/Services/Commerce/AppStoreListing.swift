import Foundation

/// ADIM 2 — App Store mağaza metinleri ve sınırları.
///
/// ## Neden kodda?
/// Apple'ın karakter sınırları (ad 30, alt başlık 30, anahtar kelime 100)
/// sık aşılır ve **aşım yalnızca yükleme anında** hata verir — geliştirme
/// sırasında fark edilmez. Metinleri burada tanımlayıp sınırları testle
/// doğrulamak, hatanın mağazaya yüklemeden önce yakalanmasını sağlar.
public enum AppStoreListing {

    // MARK: - Karakter sınırları (Apple'ın belirlediği)

    public enum Limits {
        public static let appName = 30
        public static let subtitle = 30
        public static let keywords = 100
        public static let promotionalText = 170
        public static let description = 4000
        public static let whatsNew = 4000
    }

    // MARK: - Kimlik

    public struct Listing: Equatable, Sendable {
        public let name: String
        public let subtitle: String
        public let keywords: String
        public let primaryCategory: String
        public let secondaryCategory: String
        public let ageRating: String
        public let priceTier: String
    }

    /// Türkçe mağaza kaydı.
    public static let turkish = Listing(
        name: "DiveLog: Dalış Bilgisayarı",
        subtitle: "Bühlmann ZHL-16C · Nitrox",
        keywords: "dalış,scuba,diving,derinlik,apple watch ultra,balıkçılık,"
            + "bilgisayar,bühlmann,ndl,dekompresyon",
        primaryCategory: "Spor ve Egzersiz",
        secondaryCategory: "Sağlık ve Fitness",
        ageRating: "13+",
        priceTier: "Ücretsiz (Pro abonelik içerir)")

    /// İngilizce mağaza kaydı.
    public static let english = Listing(
        name: "DiveLog: Dive Computer",
        subtitle: "Bühlmann ZHL-16C · Nitrox",
        keywords: "dive,scuba,computer,apple watch ultra,depth,decompression,"
            + "bühlmann,ndl,underwater,safety",
        primaryCategory: "Sports",
        secondaryCategory: "Health & Fitness",
        ageRating: "13+",
        priceTier: "Free (with Pro subscription)")

    /// Yerelleştirilmiş kayıtlar.
    public static let allListings: [String: Listing] = [
        "tr": turkish, "en": english
    ]

    // MARK: - Doğrulama

    /// Doğrulama bulgusu.
    public struct Issue: Equatable, Sendable, Identifiable {
        public let id: String
        public let field: String
        public let message: String
        public let isFatal: Bool
    }

    /// Bir kaydı Apple'ın kurallarına karşı doğrular.
    public static func validate(_ listing: Listing, locale: String = "") -> [Issue] {
        var issues: [Issue] = []
        let prefix = locale.isEmpty ? "" : "\(locale)."

        if listing.name.isEmpty {
            issues.append(Issue(id: "\(prefix)name.empty", field: "name",
                                message: "Uygulama adı boş", isFatal: true))
        } else if listing.name.count > Limits.appName {
            issues.append(Issue(
                id: "\(prefix)name.tooLong", field: "name",
                message: "Uygulama adı \(listing.name.count)/\(Limits.appName) karakter",
                isFatal: true))
        }

        if listing.subtitle.isEmpty {
            issues.append(Issue(id: "\(prefix)subtitle.empty", field: "subtitle",
                                message: "Alt başlık boş", isFatal: true))
        } else if listing.subtitle.count > Limits.subtitle {
            issues.append(Issue(
                id: "\(prefix)subtitle.tooLong", field: "subtitle",
                message: "Alt başlık \(listing.subtitle.count)/\(Limits.subtitle) karakter",
                isFatal: true))
        }

        if listing.keywords.count > Limits.keywords {
            issues.append(Issue(
                id: "\(prefix)keywords.tooLong", field: "keywords",
                message: "Anahtar kelimeler \(listing.keywords.count)/\(Limits.keywords) karakter",
                isFatal: true))
        }
        if listing.keywords.contains(" ") && false {
            // Anahtar kelimelerde boşluk **serbesttir** (virgülle ayrılır);
            // Apple boşluğu ayırıcı olarak kullanmaz, kelime olarak indeksler.
            // Bu blok ileride kural değişirse kullanılabilir.
            issues.append(Issue(id: "\(prefix)keywords.space", field: "keywords",
                                message: "Anahtar kelimelerde boşluk", isFatal: false))
        }

        if listing.primaryCategory.isEmpty {
            issues.append(Issue(id: "\(prefix)category.empty", field: "category",
                                message: "Kategori boş", isFatal: true))
        }
        if listing.ageRating.isEmpty {
            issues.append(Issue(id: "\(prefix)age.empty", field: "ageRating",
                                message: "Yaş derecelendirmesi boş", isFatal: true))
        }
        return issues
    }

    /// Tüm kayıtlar geçerli mi?
    public static func allValid() -> Bool {
        allListings.allSatisfy { validate($0.value, locale: $0.key).isEmpty }
    }

    // MARK: - A/B testi adayları

    /// Başlık A/B testi adayları (mağaza görünürlüğü için).
    public struct NameCandidate: Equatable, Sendable, Identifiable {
        public let name: String
        public let subtitle: String
        public let hypothesis: String
        public var id: String { name }
    }

    /// Başlık testi adayları.
    public static let nameCandidates: [NameCandidate] = [
        NameCandidate(name: "DiveLog: Dalış Bilgisayarı",
                     subtitle: "Bühlmann ZHL-16C · Nitrox",
                     hypothesis: "Kategori niyetini doğrudan bildirir"),
        NameCandidate(name: "DiveLog: Tüplü Bilgisayar",
                     subtitle: "Gerçek zamanlı NDL ve alarm",
                     hypothesis: "Özellik sayımıyla fayda vurgusu"),
        NameCandidate(name: "DiveLog: Su Altı Bilgisayar",
                     subtitle: "Gerçek zamanlı · Nitrox",
                     hypothesis: "Teknik/niş arayanları yakalar"),
        NameCandidate(name: "DiveLog for Apple Watch",
                     subtitle: "Bühlmann ZHL-16C deko",
                     hypothesis: "Cihaz bazlı arama trafiği")
    ]

    /// Tüm adaylar sınır içinde mi?
    public static var allCandidatesValid: Bool {
        nameCandidates.allSatisfy {
            $0.name.count <= Limits.appName && $0.subtitle.count <= Limits.subtitle
        }
    }

    // MARK: - Screenshot senaryoları

    /// Mağaza karesi tanımı.
    public struct Screenshot: Equatable, Sendable, Identifiable {
        public let index: Int
        public let headline: String
        public let caption: String
        public let surface: String
        public var id: Int { index }
    }

    /// 8 kare — ilk iki kare mağazada görünür olduğu için en güçlü mesajlar.
    public static let screenshots: [Screenshot] = [
        Screenshot(index: 1, headline: "Gerçek zamanlı NDL",
                   caption: "Anlık derinlik, süre ve kalan dekompresyon süresi",
                   surface: "Ana dalış ekranı"),
        Screenshot(index: 2, headline: "Bühlmann ZHL-16C",
                   caption: "16 kompartmanlı tam doku modeli",
                   surface: "Deko durakları"),
        Screenshot(index: 3, headline: "Hızlı çıkış uyarısı",
                   caption: "9 m/dk sınırı, 4 sn doğrulama",
                   surface: "Alarm ekranı"),
        Screenshot(index: 4, headline: "Gece dalışı için kırmızı",
                   caption: "OLED gücü %61 düşer, göz koruması",
                   surface: "Kırmızı gece modu"),
        Screenshot(index: 5, headline: "EAN32 · MOD 34 m",
                   caption: "MOD uyarısı Temel sürümde ücretsiz",
                   surface: "Çoklu gaz"),
        Screenshot(index: 6, headline: "Saat yüzünde NDL",
                   caption: "Modüler yüz, anlık derinlik ve geri sayım",
                   surface: "Komplikasyonlar"),
        Screenshot(index: 7, headline: "Rotanız haritada",
                   caption: "GPS rota ve etkileşimli profil grafiği",
                   surface: "iPhone harita"),
        Screenshot(index: 8, headline: "Gerçekçi uçuş yasağı",
                   caption: "Kabin basıncına göre hesaplanır",
                   surface: "Uçuş yasağı")
    ]

    /// Ekran boyutu (Apple Watch Ultra, retina).
    public struct ScreenSize: Equatable, Sendable {
        public let pointsWidth: Int
        public let pointsHeight: Int
        public let scale: Int
    }

    public static let ultraScreen = ScreenSize(pointsWidth: 410,
                                              pointsHeight: 502, scale: 2)
    /// Retina çözünürlükte piksel boyutu.
    public static var ultraPixelSize: (width: Int, height: Int) {
        (ultraScreen.pointsWidth * ultraScreen.scale,
         ultraScreen.pointsHeight * ultraScreen.scale)
    }
}
