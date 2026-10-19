import Foundation

/// Oksijen riski (PO₂ / CNS / OTU) anlık değerlendirmesi.
///
/// ADIM 4: derin iniş/çıkış ve **CNS alarmları** için tek kaynak.
/// Seviyeler hem ekran rengini hem alarm şiddetini belirler.
public struct OxygenStatus: Equatable, Codable, Sendable {

    /// Risk seviyesi (görsel + alarm ortak kullanımı).
    public enum Level: String, Equatable, Codable, Sendable, Comparable {
        case ok
        case caution
        case warning
        case critical

        private var order: Int {
            switch self {
            case .ok: return 0
            case .caution: return 1
            case .warning: return 2
            case .critical: return 3
            }
            }
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.order < rhs.order }

        /// Etiket (dalış sonu özetinde kullanılır).
        public var label: String {
            switch self {
            case .ok: return "Güvenli"
            case .caution: return "Sınıra yakın"
            case .warning: return "Sınır aşıldı"
            case .critical: return "Tehlikeli"
            }
        }
    }

    public let po2: Double
    public let maximumOperatingDepth: Double
    public let cnsPercent: Double
    public let otuUnits: Double
    public let otuPercent: Double
    public let po2Level: Level
    public let cnsLevel: Level
    public let otuLevel: Level

    public init(po2: Double, maximumOperatingDepth: Double,
                cnsPercent: Double, otuUnits: Double, otuPercent: Double,
                po2Level: Level, cnsLevel: Level, otuLevel: Level) {
        self.po2 = po2
        self.maximumOperatingDepth = maximumOperatingDepth
        self.cnsPercent = cnsPercent
        self.otuUnits = otuUnits
        self.otuPercent = otuPercent
        self.po2Level = po2Level
        self.cnsLevel = cnsLevel
        self.otuLevel = otuLevel
    }

    /// En yüksek risk seviyesi (alarm şiddeti buna göre belirlenir).
    public var overallLevel: Level {
        max(po2Level, max(cnsLevel, otuLevel))
    }

    /// CNS/OTU alarmı tetikleniyor mu? (ekran uyarısı)
    public var isAlarm: Bool { overallLevel >= .warning }

    /// Birincil mesaj (en kritik ölçüte göre) — `nil` ise sorun yok.
    public var message: String? {
        if po2Level >= .warning {
            return String(format: "PO₂ %.2f bar (azami %.1f)", po2, DiveSafetyLimits.maximumPO2)
        }
        if cnsLevel >= .warning {
            return String(format: "CNS %%%.0f — günlük sınıra yaklaşıldı", cnsPercent)
        }
        if otuLevel >= .warning {
            return String(format: "OTU %%%.0f (%.0f birim)", otuPercent, otuUnits)
        }
        if po2Level == .caution { return String(format: "PO₂ %.2f bar — sınıra yakın", po2) }
        if cnsLevel == .caution { return String(format: "CNS %%%.0f", cnsPercent) }
        if otuLevel == .caution { return String(format: "OTU %%%.0f", otuPercent) }
        return nil
    }

    // MARK: - Değerlendirme

    /// Anlık değerlendirme.
    ///
    /// - Parameters:
    ///   - po2: Oksijen basıncı (bar)
    ///   - depth: Mevcut derinlik (m) — MOD aşımı tespiti
    ///   - maximumOperatingDepth: Gazın MOD'u (m)
    ///   - cnsPercent / otuUnits / otuPercent: oksijen toksisitesi birikimi
    ///   - maxPO2: Azami PO₂ (bar)
    ///   - warningPercent: CNS/OTU uyarı eşiği (%)
    ///   - dailyOTULimit: Günlük OTU limiti (%)
    public static func evaluate(po2: Double,
                                depth: Double = 0,
                                maximumOperatingDepth: Double = .greatestFiniteMagnitude,
                                cnsPercent: Double = 0,
                                otuUnits: Double = 0,
                                otuPercent: Double = 0,
                                maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                warningPercent: Double = DiveSafetyLimits.oxygenWarningPercent,
                                dailyOTULimit: Double = 80) -> OxygenStatus {
        let po2Level: Level
        if po2 > maxPO2 { po2Level = .critical }
        else if po2 > maxPO2 * 0.9 { po2Level = .caution }
        else { po2Level = .ok }

        let cnsLevel = level(forPercent: cnsPercent, warningPercent: warningPercent)
        let otuLevel = level(forPercent: otuPercent, warningPercent: dailyOTULimit)

        return OxygenStatus(
            po2: po2, maximumOperatingDepth: maximumOperatingDepth,
            cnsPercent: cnsPercent, otuUnits: otuUnits, otuPercent: otuPercent,
            po2Level: po2Level, cnsLevel: cnsLevel, otuLevel: otuLevel)
    }

    /// `DiveState`'ten anlık durum.
    public static func evaluate(state: DiveState,
                                maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                warningPercent: Double = DiveSafetyLimits.oxygenWarningPercent,
                                dailyOTULimit: Double = 80) -> OxygenStatus {
        evaluate(po2: state.oxygenPartialPressure,
                 depth: state.currentDepth,
                 maximumOperatingDepth: state.maximumOperatingDepth,
                 cnsPercent: state.cnsPercent,
                 otuUnits: state.otuUnits,
                 otuPercent: state.otuPercent,
                 maxPO2: maxPO2,
                 warningPercent: warningPercent,
                 dailyOTULimit: dailyOTULimit)
    }

    /// MOD aşımı var mı?
    public var isAboveMaximumOperatingDepth: Bool {
        maximumOperatingDepth < .greatestFiniteMagnitude
            && po2 > DiveSafetyLimits.maximumPO2 + 1e-9
    }

    private static func level(forPercent percent: Double, warningPercent: Double) -> Level {
        if percent >= 100 { return .critical }
        if percent >= warningPercent { return .warning }
        if percent >= warningPercent * 0.6 { return .caution }
        return .ok
    }
}