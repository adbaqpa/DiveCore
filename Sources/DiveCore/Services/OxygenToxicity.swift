import Foundation

/// Oksijen toksisitesi hesapları: **CNS** (merkezi sinir sistemi) ve **OTU**.
///
/// ## CNS — NOAA tek doz limitleri
/// CNS yüzdesi, PO2 seviyesine göre değişen "tek doz limit süresi"ne göre artar:
/// ```
/// CNS% += 100 * dt_dakika / limit_dakika(PO2)
/// ```
/// Bu yöntem NOAA 2015 kılavuzundaki "CNS clock" yaklaşımıdır.
///
/// ## OTU — NOAA eşdeğer doz süresi
/// ```
/// OTU/dakika = 0.5 / (PO2 - 0.5)^0.83     (PO2 > 0.5 bar)
/// ```
/// OTU 24 saatlik kümülatif bir dozdur; günlük üst sınırı ~80 OTU olarak
/// kabul edilir (UPTD - NOAA `Cx` limiti). Bu nedenle OTU doğrudan "yüzde"
/// değil, "günlük limitin yüzdesi" olarak sunulur.
public struct OxygenToxicity: Equatable, Codable, Sendable {

    // MARK: - Ayarlanabilir limitler

    /// Azami oksijen basıncı (bar).
    public var maxPO2: Double

    /// Günlük OTU limiti (OTU). NOAA önerisi: 80.
    public var dailyOTULimit: Double

    /// CNS uyarı eşiği (%).
    public var cnsWarningPercent: Double

    /// OTU uyarı eşiği (%).
    public var otuWarningPercent: Double

    // MARK: - Birikimli sayaçlar

    /// Birikimli CNS yüzdesi (0...100+).
    public private(set) var cnsPercent: Double

    /// Birikimli OTU (24 saatlik kümülatif).
    public private(set) var otuUnits: Double

    /// Başlangıçta sıfırlananların zaman damgası / sıfırlama gerekip gerekmediği işareti.
    /// (Uygulama katmanı `Date` ile yönetir; çekirdek modül tarih bilmez.)
    public private(set) var didExceedLimits: Bool

    public init(
        maxPO2: Double = DiveSafetyLimits.maximumPO2,
        dailyOTULimit: Double = 80.0,
        cnsWarningPercent: Double = DiveSafetyLimits.oxygenWarningPercent,
        otuWarningPercent: Double = DiveSafetyLimits.oxygenWarningPercent,
        cnsPercent: Double = 0,
        otuUnits: Double = 0
    ) {
        self.maxPO2 = maxPO2
        self.dailyOTULimit = max(0.01, dailyOTULimit)
        self.cnsWarningPercent = cnsWarningPercent
        self.otuWarningPercent = otuWarningPercent
        self.cnsPercent = cnsPercent
        self.otuUnits = otuUnits
        self.didExceedLimits = false
    }

    // MARK: - Tablolar

    /// NOAA CNS tek doz limit süreleri: alt PO2 eşiği (bar) -> dakika.
    public static let cnsTable: [(po2: Double, minutes: Double)] = [
        (0.5, 720), (0.6, 570), (0.7, 450), (0.8, 360), (0.9, 300),
        (1.0, 240), (1.1, 210), (1.2, 180), (1.3, 150), (1.4, 120),
        (1.5, 45), (1.6, 1)
    ]

    /// NOAA CNS tek doz limiti (dakika). PO2 < 0.5 bar ise sınırsız (720 dk sınırı).
    public static func cnsLimitMinutes(po2: Double) -> Double {
        guard po2 >= 0.5 else { return 720 }
        for row in cnsTable {
            if po2 < row.po2 + 0.1 { return row.minutes }
        }
        return 1 // PO2 >= 1.6
    }

    /// NOAA OTU oranı: dakika başına OTU. PO2 <= 0.5 bar ise sıfır.
    public static func otuPerMinute(po2: Double) -> Double {
        guard po2 > 0.5 else { return 0 }
        return 0.5 / pow(po2 - 0.5, 0.83)
    }

    /// OTU'nun günlük limitin yüzdesi olarak ifadesi (0...100+).
    public var otuPercent: Double {
        guard dailyOTULimit > 0 else { return 0 }
        return otuUnits / dailyOTULimit * 100.0
    }

    // MARK: - Güncelleme

    /// Verilen süre boyunca oksijen toksisitesini biriktirir.
    ///
    /// - Parameters:
    ///   - po2: Solunan oksijen basıncı (bar)
    ///   - duration: Geçen süre (saniye)
    public mutating func accumulate(po2: Double, duration: TimeInterval) {
        guard duration > 0 else { return }
        let minutes = duration / 60.0

        // CNS — yalnızca PO2 > 0.5 bar ise birikir
        if po2 > 0.5 {
            let limit = OxygenToxicity.cnsLimitMinutes(po2: po2)
            cnsPercent += 100.0 * minutes / limit
        }

        // OTU
        otuUnits += OxygenToxicity.otuPerMinute(po2: po2) * minutes

        if po2 > maxPO2 || cnsPercent > 100 {
            didExceedLimits = true
        }
    }

    /// Gün sonu / yüzey aralığında CNS ve OTU sayaçlarını sıfırlar.
    public mutating func reset() {
        cnsPercent = 0
        otuUnits = 0
        didExceedLimits = false
    }

    // MARK: - Değerlendirme

    /// Uyarı seviyesi.
    public enum WarningLevel: String, Equatable, Sendable {
        case none
        case caution
        case warning
        case danger

        public var severity: Int {
            switch self {
            case .none: return 0
            case .caution: return 1
            case .warning: return 2
            case .danger: return 3
            }
        }
    }

    /// Mevcut CNS/OTU/PO2 durumuna göre uyarı seviyesi.
    public func warningLevel(currentPO2: Double) -> WarningLevel {
        if cnsPercent > 80 || otuPercent > otuWarningPercent || currentPO2 > maxPO2 { return .danger }
        if cnsPercent > 50 || otuPercent > otuWarningPercent * 0.5 { return .warning }
        if cnsPercent > cnsWarningPercent * 0.5 || otuPercent > otuWarningPercent * 0.25 || currentPO2 > maxPO2 * 0.9 {
            return .caution
        }
        return .none
    }

    /// OTU tahmini yarılanma süresi (dakika, günlük limitin %50'sine düşmesi için).
    /// NOT: Kaba bir doz-söküm tahminidir; yalnızca bilgilendirme amaçlıdır.
    public var otuHalfLifeMinutes: Double {
        let currentRate = dailyOTULimit * 0.5
        let estimate = max(0, otuUnits - currentRate)
        return estimate / 0.55 // yaklaşık OTU saatlik azalma oranı
    }
}