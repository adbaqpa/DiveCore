import XCTest
@testable import DiveCore

/// ADIM 2 — App Store metinleri: karakter sınırları ve içerik kuralları.
final class StoreTextTests: XCTestCase {

    // MARK: - Sınırlar

    func testLimitConstantsMatchAppleRules() {
        XCTAssertEqual(AppStoreListing.Limits.appName, 30)
        XCTAssertEqual(AppStoreListing.Limits.subtitle, 30)
        XCTAssertEqual(AppStoreListing.Limits.keywords, 100)
    }

    func testTurkishListingFitsLimits() {
        XCTAssertLessThanOrEqual(AppStoreListing.turkish.name.count,
                                 AppStoreListing.Limits.appName)
        XCTAssertLessThanOrEqual(AppStoreListing.turkish.subtitle.count,
                                 AppStoreListing.Limits.subtitle)
        XCTAssertLessThanOrEqual(AppStoreListing.turkish.keywords.count,
                                 AppStoreListing.Limits.keywords)
    }

    func testEnglishListingFitsLimits() {
        XCTAssertLessThanOrEqual(AppStoreListing.english.name.count,
                                 AppStoreListing.Limits.appName)
        XCTAssertLessThanOrEqual(AppStoreListing.english.subtitle.count,
                                 AppStoreListing.Limits.subtitle)
        XCTAssertLessThanOrEqual(AppStoreListing.english.keywords.count,
                                 AppStoreListing.Limits.keywords)
    }

    func testAllListingsAreValid() {
        for (locale, listing) in AppStoreListing.allListings {
            let issues = AppStoreListing.validate(listing, locale: locale)
            XCTAssertTrue(issues.isEmpty,
                          "\(locale): \(issues.map(\.message).joined(separator: ", "))")
        }
        XCTAssertTrue(AppStoreListing.allValid())
    }

    // MARK: - Anahtar kelimeler

    /// Apple, anahtar kelime alanında **çok kelimeli ifadeleri** de
    /// destekler (virgülle ayrılmış her parça bir anahtar kelimedir).
    /// Bu nedenle yasak olan şey boşluk değil, **baştaki/sondaki boşluk**
    /// ve boş girdilerdir.
    func testKeywordsAreCommaSeparatedAndTrimmed() {
        for (locale, listing) in AppStoreListing.allListings {
            XCTAssertFalse(listing.keywords.hasPrefix(","), locale)
            XCTAssertFalse(listing.keywords.hasSuffix(","), locale)
            XCTAssertFalse(listing.keywords.contains(",,"), locale)

            let keywords = listing.keywords
                .split(separator: ",", omittingEmptySubsequences: false)
                .map(String.init)
            XCTAssertGreaterThanOrEqual(keywords.count, 5, locale)
            for raw in keywords {
                XCTAssertFalse(raw.isEmpty, "\(locale): boş anahtar kelime")
                XCTAssertEqual(raw, raw.trimmingCharacters(in: .whitespaces),
                               "\(locale): '\(raw)' boşlukla başlıyor/ bitiyor")
            }
        }
    }

    func testKeywordsHaveNoDuplicates() {
        for (locale, listing) in AppStoreListing.allListings {
            let keywords = listing.keywords.split(separator: ",").map(String.init)
            XCTAssertEqual(Set(keywords).count, keywords.count,
                           "\(locale): yinelenen anahtar kelime")
        }
    }

    func testKeywordsAvoidCompetitorBrands() {
        // Rakip marka adları ASO'da yasaktır; Apple reddi riski taşır
        let banned = ["garmin", "subsurface", "shearwater", "suunto", "divesite"]
        for (locale, listing) in AppStoreListing.allListings {
            let lower = listing.keywords.lowercased()
            for brand in banned {
                XCTAssertFalse(lower.contains(brand),
                               "\(locale): rakip marka '\(brand)' anahtar kelimelerde")
            }
        }
    }

    func testKeywordsCoverCoreTerms() {
        let turkish = AppStoreListing.turkish.keywords
        for term in ["dalış", "derinlik", "bühlmann", "dekompresyon"] {
            XCTAssertTrue(turkish.contains(term), "eksik anahtar kelime: \(term)")
        }
        let english = AppStoreListing.english.keywords
        for term in ["dive", "depth", "decompression"] {
            XCTAssertTrue(english.contains(term), "missing keyword: \(term)")
        }
    }

    func testKeywordsAvoidMoneyIntent() {
        // "ücretsiz" / "free" kötü eşleşme çeker
        XCTAssertFalse(AppStoreListing.turkish.keywords.contains("ücretsiz"))
        XCTAssertFalse(AppStoreListing.english.keywords.contains("free"))
    }

    // MARK: - Başlık adayları

    func testNameCandidatesFitLimits() {
        for candidate in AppStoreListing.nameCandidates {
            XCTAssertLessThanOrEqual(candidate.name.count,
                                     AppStoreListing.Limits.appName)
            XCTAssertLessThanOrEqual(candidate.subtitle.count,
                                     AppStoreListing.Limits.subtitle)
            XCTAssertFalse(candidate.hypothesis.isEmpty)
        }
        XCTAssertTrue(AppStoreListing.allCandidatesValid)
    }

    func testNameCandidatesAreDistinct() {
        let names = AppStoreListing.nameCandidates.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: - Ekran görüntüleri

    func testScreenshotCountAndOrder() {
        XCTAssertEqual(AppStoreListing.screenshots.count, 8)
        for (index, screenshot) in AppStoreListing.screenshots.enumerated() {
            XCTAssertEqual(screenshot.index, index + 1)
            XCTAssertFalse(screenshot.headline.isEmpty)
            XCTAssertFalse(screenshot.caption.isEmpty)
        }
    }

    func testFirstScreenshotsCarryStrongestMessages() {
        // İlk iki kare mağazada görünür: NDL ve deko modeli
        let first = AppStoreListing.screenshots[0].headline
        let second = AppStoreListing.screenshots[1].headline
        XCTAssertTrue(first.contains("NDL"))
        XCTAssertTrue(second.contains("Bühlmann"))
    }

    func testScreenshotHeadlineLengths() {
        for screenshot in AppStoreListing.screenshots {
            // Kısa başlık ekranda okunabilir kalmalı
            XCTAssertLessThanOrEqual(screenshot.headline.count, 28)
        }
    }

    func testUltraScreenSize() {
        let size = AppStoreListing.ultraScreen
        XCTAssertEqual(size.pointsWidth, 410)
        XCTAssertEqual(size.pointsHeight, 502)
        XCTAssertEqual(AppStoreListing.ultraPixelSize.width, 820)
        XCTAssertEqual(AppStoreListing.ultraPixelSize.height, 1004)
    }

    // MARK: - Kategori

    func testCategoryIsSport() {
        // Sağlık ve Fitness kovası daha rekabetçi
        XCTAssertTrue(AppStoreListing.turkish.primaryCategory.contains("Spor"))
        XCTAssertTrue(AppStoreListing.english.primaryCategory.contains("Sports"))
        XCTAssertFalse(AppStoreListing.turkish.secondaryCategory.isEmpty)
    }

    // MARK: - Doğrulayıcı

    func testValidatorCatchesLongName() {
        let tooLong = AppStoreListing.Listing(
            name: String(repeating: "a", count: 40),
            subtitle: AppStoreListing.turkish.subtitle,
            keywords: AppStoreListing.turkish.keywords,
            primaryCategory: "Spor", secondaryCategory: "Sağlık",
            ageRating: "13+", priceTier: "Ücretsiz")
        let issues = AppStoreListing.validate(tooLong, locale: "tr")
        XCTAssertTrue(issues.contains { $0.field == "name" && $0.isFatal })
    }

    func testValidatorCatchesLongKeywords() {
        let tooLong = AppStoreListing.Listing(
            name: "DiveLog",
            subtitle: "Dalış",
            keywords: String(repeating: "k", count: 120),
            primaryCategory: "Spor", secondaryCategory: "Sağlık",
            ageRating: "13+", priceTier: "Ücretsiz")
        let issues = AppStoreListing.validate(tooLong, locale: "tr")
        XCTAssertTrue(issues.contains { $0.field == "keywords" && $0.isFatal })
    }

    func testValidatorCatchesEmptyFields() {
        let empty = AppStoreListing.Listing(name: "", subtitle: "",
                                            keywords: "", primaryCategory: "",
                                            secondaryCategory: "x",
                                            ageRating: "", priceTier: "")
        let issues = AppStoreListing.validate(empty, locale: "tr")
        XCTAssertTrue(issues.contains { $0.field == "name" })
        XCTAssertTrue(issues.contains { $0.field == "subtitle" })
        XCTAssertTrue(issues.contains { $0.field == "category" })
        XCTAssertTrue(issues.contains { $0.field == "ageRating" })
    }

    // MARK: - Güvenlik vurgusu

    /// Mağaza metinlerinde güvenliğin ücretsiz olduğu belirtilmelidir.
    func testStoreTextPromisesFreeSafety() {
        // Mağaza açıklaması bu ifadeyi içermeli (App/Store/AppStoreMetinleri.md)
        let root = FileManager.default.currentDirectoryPath
        let path = "\(root)/App/Store/AppStoreMetinleri.md"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }
        XCTAssertTrue(text.contains("ücretsiz"),
                      "Mağaza metni güvenlik özelliklerinin ücretsiz olduğunu belirtmeli")
        XCTAssertTrue(text.contains("Bühlmann"))
    }

    /// App Privacy beyanında tracking olmamalı.
    func testPrivacyDeclarationHasNoTracking() {
        XCTAssertFalse(AppPrivacy.hasTracking)
        XCTAssertFalse(AppPrivacy.hasAnalytics)
        XCTAssertFalse(AppPrivacy.hasAppServerData)
    }

    func testPrivacySupportsDeletionEverywhere() {
        XCTAssertTrue(AppPrivacy.allSupportDeletion)
    }

    func testPrivacyCoversRequiredDataTypes() {
        for dataType in [AppPrivacy.DataType.location,
                         .healthAndFitness,
                         .userContent,
                         .identifiers,
                         .purchases] {
            XCTAssertNotNil(AppPrivacy.declaration(for: dataType),
                            "\(dataType.rawValue) beyanda yok")
        }
    }

    func testPrivacyFAQIsAnswered() {
        XCTAssertGreaterThanOrEqual(AppPrivacy.faq.count, 5)
        for item in AppPrivacy.faq {
            XCTAssertFalse(item.question.isEmpty)
            XCTAssertFalse(item.answer.isEmpty)
            XCTAssertGreaterThan(item.answer.count, 20)
        }
    }

    func testPrivacyDataTypesHaveNamesAndSubtypes() {
        for dataType in AppPrivacy.DataType.allCases {
            XCTAssertFalse(dataType.turkishName.isEmpty, dataType.rawValue)
            XCTAssertFalse(dataType.subtypes.isEmpty, dataType.rawValue)
        }
    }

    func testPrivacyEncryptedWhereCollected() {
        // Sunucuya giden veri yok; iCloud'a giden veri şifrelidir
        for declaration in AppPrivacy.declarations
        where declaration.collection == .privateCloudOnly {
            XCTAssertTrue(declaration.isEncryptedAtRest,
                          "\(declaration.dataType.rawValue) şifrelenmeli")
        }
    }
}
