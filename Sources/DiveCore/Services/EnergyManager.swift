import Foundation

/// Cihazın enerji durumu — platformdan bağımsız, test edilebilir.
///
/// `DiveWatch` adaptörü `WKInterfaceDevice` ve `ProcessInfo` okur, bu tip
/// doldurulur; tüm kararlar çekirdektedir.
public struct EnergyState: Equatable, Codable, Sendable {

    // MARK: Girdiler

    /// Pil seviyesi (0...1). Bilinmiyorsa `nil` (simülatör, iPhone eşliği).
    public let batteryLevel: Double?
    /// Düşük pil modu açık mı (watchOS Low Power Mode).
    public let isLowPowerModeEnabled: Bool
    /// Termal basınç (watchOS `ProcessInfo.thermalState`).
    public let thermalState: ThermalState
    /// Ekran AOD'da mı.
    public let isAlwaysOn: Bool
    /// Aktif tema
    public let theme: DiveDisplayTheme
    /// Dalış sürüyor mu
    public let isDiving: Bool
    /// Aktif enerji profili
    public let profile: PowerProfile

    /// Termal durum (Apple'ın sınıflandırmasıyla aynı).
    public enum ThermalState: Int, Codable, Sendable, CaseIterable, Comparable {
        case nominal = 0
        case fair = 1
        case serious = 2
        case critical = 3

        public static func < (lhs: ThermalState, rhs: ThermalState) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var title: String {
            switch self {
            case .nominal: return "Normal"
            case .fair: return "Hafif ısınma"
            case .serious: return "Belirgin ısınma"
            case .critical: return "Kritik ısınma"
            }
        }
    }

    public init(batteryLevel: Double? = nil,
                isLowPowerModeEnabled: Bool = false,
                thermalState: ThermalState = .nominal,
                isAlwaysOn: Bool = false,
                theme: DiveDisplayTheme = .standard,
                isDiving: Bool = false,
                profile: PowerProfile = .balanced) {
        self.batteryLevel = batteryLevel.map { $0.clamped(to: 0...1) }
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalState = thermalState
        self.isAlwaysOn = isAlwaysOn
        self.theme = theme
        self.isDiving = isDiving
        self.profile = profile
    }

    // MARK: Türetilmiş durumlar

    /// Pil bilinmiyor mu (iPhone eşliği, simülatör)?
    public var isBatteryUnknown: Bool { batteryLevel == nil }

    /// Pil seviyesi yüzde olarak (bilinmiyorsa 100).
    public var batteryPercent: Int { Int(((batteryLevel ?? 1) * 100).rounded()) }

    /// Pil kritik mi? (< %15) — kullanıcıyı uyarırız.
    public var isBatteryCritical: Bool { (batteryLevel ?? 1) < 0.15 }

    /// Pil düşük mü? (< %30) — gece modu önerilir.
    public var isBatteryLow: Bool { (batteryLevel ?? 1) < 0.30 }

    /// Termal olarak kısıtlanmalı mı?
    public var isThermallyConstrained: Bool { thermalState >= .serious }

    /// Kullanıcı ya da sistem pil tasarrufu istiyor mu?
    public var shouldConserve: Bool {
        isLowPowerModeEnabled || isBatteryLow || isThermallyConstrained
    }
}

/// Enerji profili — kullanıcının seçtiği öncelik.
public enum PowerProfile: String, Equatable, Codable, Sendable, CaseIterable, Identifiable {
    /// En uzun pil, kısa oturum (güvenlik verisi azaltılır **değil**,
    /// yalnızca arka plan işleri kısılır)
    case saver
    /// Dengeli (varsayılan)
    case balanced
    /// En canlı veri, daha kısa pil
    case performance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .saver: return "Pil Tasarrufu"
        case .balanced: return "Dengeli"
        case .performance: return "Performans"
        }
    }

    public var detail: String {
        switch self {
        case .saver: return "Arka plan güncellemeleri seyrekleşir, 1 Hz→0.2 Hz"
        case .balanced: return "Varsayılan; deko tamlığını koruyan aralık"
        case .performance: return "Her saniye tazelenir, en pahalı görünüm"
        }
    }

    /// Temel örnekleme aralığı (saniye) — profil bunu belirler.
    ///
    /// - Note: `performance` 2 Hz'de çalışır; hızlı çıkış ve tavan
    ///   yakınlığı tespitinde iki kat çözünürlük sağlar.
    public var baseInterval: TimeInterval {
        switch self {
        case .saver: return 5
        case .balanced: return 1
        case .performance: return 0.5
        }
    }

    /// Profil, sistem kısıtlaması nedeniyle kısıtlanabilir mi?
    public func constrained(by state: EnergyState) -> PowerProfile {
        // Termal kritik veya çok düşük pilde performans modu kabul edilmez.
        if state.thermalState >= .serious || state.batteryPercent < 10 {
            return self == .performance ? .balanced : self
        }
        if state.isLowPowerModeEnabled, self == .performance {
            return .balanced
        }
        return self
    }
}

/// Enerji bütçesi — kalan pilin **ne kadar süre yeteceğini** tahmin eder.
///
/// ## Model
///
/// Tüketicimiz dört kalemdir ve her biri ölçülebilir bir tüketim hızına
/// (mW) karşılık gelir:
///
/// | Kalem | Tüketim (mW) | Not |
/// |---|---|---|
/// | Dekompresyon motoru | 18 | 16 kompartman × saniyelik adım |
/// | Sensör + CoreMotion | 45 | en pahalı kalem |
/// | Ekran (AOD açık) | 90 | OLED, tema bağımlı |
/// | Ekran (AOD kapalı) | 25 | |
/// | Arka plan (konum/bLE) | 30 | |
///
/// Ortalama bir çift modelli dalışta sensör + ekran toplamının büyük
/// kısmını oluşturur; bu nedenle **ekran teması** ve **örnekleme aralığı**
/// en büyük kazançları sağlar. Değerler Apple'ın yayımladığı mutlak
/// pil ölçümlerinden değil, **göreli** kıyaslama için kullanılır.
public enum EnergyBudget {

    /// Tüketim kalemleri (mW).
    public enum Component: String, CaseIterable, Codable, Sendable {
        case engine
        case sensor
        case display
        case background

        /// Taban tüketim (mW) — bu profildeki ek yük olmadan.
        public var baseMilliwatts: Double {
            switch self {
            case .engine: return 18
            case .sensor: return 45
            case .display: return 55
            case .background: return 25
            }
        }
    }

    /// Apple Watch Ultra pil kapasitesi (yaklaşık mAh), enerji bütçesi için.
    public static let batteryCapacityMah: Double = 1250

    /// Ekranın ortalama yanık kalma oranı — AOD dışında ekran yalnızca
    /// kol kaldırıldığında kısa sürelerle yanar.
    public static let activeScreenFraction: Double = 0.25

    /// Bir temaya göre ekran tüketimi (mW).
    ///
    /// - Note: AOD açıkken ekran sürekli yanık olduğundan tema doğrudan
    ///   belirleyicidir. AOD kapalıyken ekran yalnızca kullanıcı kollarını
    ///   kaldırdığında yanar; bu yüzden tema etkisi
    ///   `activeScreenFraction` (≈ %25) ile ölçeklenir. Böylece gece modu
    ///   her iki durumda da ölçülebilir bir kazanç sağlar.
    public static func displayMilliwatts(theme: DiveDisplayTheme,
                                        isAlwaysOn: Bool,
                                        heroFraction: Double = 0.28,
                                        secondaryFraction: Double = 0.10) -> Double {
        let spec = DiveThemeCatalog.spec(for: theme)
        let power = spec.estimatedPower(heroFraction: heroFraction,
                                        secondaryFraction: secondaryFraction)
        let dutyCycle = isAlwaysOn ? 1.0 : activeScreenFraction
        return Component.display.baseMilliwatts + power * 90 * dutyCycle
    }

    /// Sensör tüketimi örnekleme aralığına bağlıdır.
    ///
    /// CoreMotion her 1 saniyede bir işlem yaptığında sabit bir taban
    /// maliyet + işlem başına değişken maliyet öder. Aralık 5 saniyeye
    /// çıktığında işlem sayısı 5 kat azalır.
    public static func sensorMilliwatts(interval: TimeInterval) -> Double {
        let seconds = max(0.2, interval)
        // 1 Hz'de 45 mW; 0.2 Hz'de ~18 mW (aşırı düşük — hata bırakır).
        return 12 + 33 / seconds
    }

    /// Toplam anlık tüketim (mW).
    public static func totalMilliwatts(theme: DiveDisplayTheme,
                                       isAlwaysOn: Bool,
                                       samplingInterval: TimeInterval,
                                       isDiving: Bool,
                                       backgroundActive: Bool = true) -> Double {
        var sum = Component.engine.baseMilliwatts
        sum += isDiving ? sensorMilliwatts(interval: samplingInterval) : 4
        sum += displayMilliwatts(theme: theme, isAlwaysOn: isAlwaysOn)
        if isDiving {
            sum += backgroundActive ? Component.background.baseMilliwatts : 4
        }
        return sum
    }

    /// Kalan pilin kaç saat dayanacağı (tahmin).
    public static func projectedHoursRemaining(batteryLevel: Double?,
                                               milliamps: Double,
                                               capacityMah: Double = batteryCapacityMah) -> Double {
        guard let batteryLevel, batteryLevel > 0, milliamps > 0 else { return .infinity }
        let availableMah = capacityMah * batteryLevel
        return availableMah / milliamps
    }

    /// Bir profilin tahmini dayanma süresi (saat).
    public static func projectedHours(for state: EnergyState,
                                      samplingInterval: TimeInterval) -> Double {
        let milliwatts = totalMilliwatts(theme: state.theme,
                                         isAlwaysOn: state.isAlwaysOn,
                                         samplingInterval: samplingInterval,
                                         isDiving: state.isDiving)
        return projectedHoursRemaining(batteryLevel: state.batteryLevel, milliamps: milliwatts)
    }
}

/// ADIM 11 — **güç yöneticisi**.
///
/// ## Ne yapar?
/// 1. Aktif enerji profilini sistem kısıtlamalarına göre seçer,
/// 2. Pil/termal durumuna göre **ekran temasını** zorlar,
/// 3. Önerilen örnekleme aralığını hesaplar (`AdaptiveSampler`),
/// 4. Kalan pilin tahmini dayanma süresini raporlar,
/// 5. Kullanıcıyı bilgilendiren uyarılar üretir.
///
/// ## Güvenlik sınırı
/// Bu yönetici **asla** dekompresyon doğruluğunu ödünlüğüne koymaz:
/// `AdaptiveSampler` her koşulda emniyet sınırını korur, yalnızca
/// *fazın* kendisi (ör. dipte hareketsiz bekleme) seyrekleşir.
public struct EnergyManager: Equatable, Sendable {

    public private(set) var state: EnergyState
    /// Kullanıcının tercih ettiği profil (sistem kısıtlaması uygulanmış).
    public private(set) var profile: PowerProfile
    /// Kullanıcının gece modu tercihi.
    public private(set) var nightModePreference: NightModePreference
    /// Aktif tema.
    public private(set) var theme: DiveDisplayTheme
    /// Önerilen örnekleme aralığı (saniye).
    public private(set) var recommendedInterval: TimeInterval

    /// Gece modu tercihi.
    public enum NightModePreference: String, Equatable, Codable, Sendable, CaseIterable {
        /// Kullanıcı seçmez; pil durumuna göre uygulama karar verir.
        case auto
        /// Gece modu daima açık.
        case forced
        /// Tema hiç değişmez (standart).
        case off

        public var title: String {
            switch self {
            case .auto: return "Otomatik"
            case .forced: return "Her zaman Açık"
            case .off: return "Kapalı"
            }
        }
    }

    // MARK: - Kurulum

    public init(state: EnergyState = EnergyState(),
                nightModePreference: NightModePreference = .auto) {
        self.state = state
        self.nightModePreference = nightModePreference
        self.profile = state.profile.constrained(by: state)
        self.theme = EnergyManager.resolveTheme(state: state,
                                                preference: nightModePreference)
        self.recommendedInterval = EnergyManager.baseInterval(for: self.profile, state: state)
    }

    // MARK: - Güncelleme

    /// Yeni enerji durumu.
    public mutating func update(state newState: EnergyState) {
        state = newState
        profile = newState.profile.constrained(by: newState)
        theme = EnergyManager.resolveTheme(state: newState, preference: nightModePreference)
        recommendedInterval = EnergyManager.baseInterval(for: profile, state: newState)
    }

    /// Gece modu tercihini değiştir.
    public mutating func setNightMode(_ preference: NightModePreference) {
        nightModePreference = preference
        theme = EnergyManager.resolveTheme(state: state, preference: preference)
    }

    /// Profili değiştir.
    public mutating func setProfile(_ newProfile: PowerProfile) {
        state = EnergyState(batteryLevel: state.batteryLevel,
                            isLowPowerModeEnabled: state.isLowPowerModeEnabled,
                            thermalState: state.thermalState,
                            isAlwaysOn: state.isAlwaysOn,
                            theme: state.theme,
                            isDiving: state.isDiving,
                            profile: newProfile)
        profile = newProfile.constrained(by: state)
        recommendedInterval = EnergyManager.baseInterval(for: profile, state: state)
    }

    // MARK: - Tema çözümlemesi

    /// Enerji durumuna göre etkin tema.
    ///
    /// Öncelik:
    /// 1. AOD'da **her zaman** `alwaysOnRed` (Apple AOD kısıtları zaten
    ///    yalnızca kırmızı tonlarına izin verir; biz de buna uyarız),
    /// 2. `forced` tercihi → `nightShift`,
    /// 3. `auto`: pil < %30 veya gece (kullanıcı saati) → `nightShift`,
    /// 4. aksi halde `standard`.
    public static func resolveTheme(state: EnergyState,
                                     preference: NightModePreference,
                                     now: Date = Date()) -> DiveDisplayTheme {
        if state.isAlwaysOn { return .alwaysOnRed }
        switch preference {
        case .forced:
            return .nightShift
        case .off:
            return .standard
        case .auto:
            if state.isBatteryLow || state.isLowPowerModeEnabled { return .nightShift }
            // Gece saatleri (21:00–06:00) — kullanıcı çoğunlukla gece dalışı yapar
            let hour = Calendar.current.component(.hour, from: now)
            if hour >= 21 || hour < 6 { return .nightShift }
            return .standard
        }
    }

    // MARK: - Örnekleme

    /// Profilin taban aralığı (saniye).
    public static func baseInterval(for profile: PowerProfile, state: EnergyState) -> TimeInterval {
        var interval = profile.baseInterval
        if state.isThermallyConstrained { interval *= 2 }
        if state.isLowPowerModeEnabled { interval = max(interval, 5) }
        if state.isBatteryCritical { interval = max(interval, 5) }
        return min(interval, 10)
    }

    // MARK: - Raporlama

    /// Kalan pilin tahmini dayanma süresi (saat) — mevcut öneriyle.
    ///
    /// - Note: **Çözülmüş** tema (`theme`) kullanılır; `state.theme` henüz
    ///   uygulanmamış bir giriş olabilir (ör. AOD açılana kadar standart).
    public var projectedHours: Double {
        var effective = state
        effective = EnergyState(batteryLevel: state.batteryLevel,
                                isLowPowerModeEnabled: state.isLowPowerModeEnabled,
                                thermalState: state.thermalState,
                                isAlwaysOn: state.isAlwaysOn,
                                theme: theme,
                                isDiving: state.isDiving,
                                profile: profile)
        return EnergyBudget.projectedHours(for: effective,
                                           samplingInterval: recommendedInterval)
    }

    /// Anlık tüketim (mW).
    public var currentMilliwatts: Double {
        EnergyBudget.totalMilliwatts(theme: theme,
                                     isAlwaysOn: state.isAlwaysOn,
                                     samplingInterval: recommendedInterval,
                                     isDiving: state.isDiving)
    }

    /// Kullanıcı bilgilendirmesi.
    public var guidance: [Guidance] {
        Guidance.make(state: state, profile: profile, theme: theme)
    }

    /// Kullanıcıya gösterilecek kısa metin (ayar ekranı için).
    public var summaryText: String {
        let battery = state.isBatteryUnknown
            ? "Pil: —"
            : "Pil: %\(state.batteryPercent)"
        let projected = projectedHours.isFinite
            ? "≈ \(Int(projectedHours * 60)) dk öngörü"
            : "öngörü yok"
        return "\(battery) · \(profile.title) · \(theme.title) · \(projected)"
    }

    /// Kullanıcı bilgilendirmesi.
    public struct Guidance: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case info, caution, critical
        }

        public let id: String
        public let kind: Kind
        public let message: String
        public let action: String?

        public init(id: String, kind: Kind, message: String, action: String? = nil) {
            self.id = id
            self.kind = kind
            self.message = message
            self.action = action
        }

        static func make(state: EnergyState, profile: PowerProfile,
                         theme: DiveDisplayTheme) -> [Guidance] {
            var items: [Guidance] = []

            if state.isBatteryCritical {
                items.append(Guidance(
                    id: "batteryCritical", kind: .critical,
                    message: "Pil %\(state.batteryPercent) — dalışı uzatmayın, yüzeye dönün.",
                    action: "Pil tasarrufu moduna geçildi"))
            } else if state.isBatteryLow {
                items.append(Guidance(
                    id: "batteryLow", kind: .caution,
                    message: "Pil %\(state.batteryPercent) — ekran kırmızı gece moduna alındı.",
                    action: nil))
            }

            if state.thermalState == .serious {
                items.append(Guidance(
                    id: "thermalSerious", kind: .caution,
                    message: "Cihaz belirgin ısındı (\(state.thermalState.title)).",
                    action: "Örnekleme aralığı iki katına çıkarıldı"))
            } else if state.thermalState == .critical {
                items.append(Guidance(
                    id: "thermalCritical", kind: .critical,
                    message: "Cihaz kritik sıcaklıkta; işlem hızı düşürüldü.",
                    action: nil))
            }

            if state.isLowPowerModeEnabled {
                items.append(Guidance(
                    id: "lowPowerMode", kind: .info,
                    message: "Sistem düşük pil modu açık.",
                    action: nil))
            }

            if theme == .alwaysOnRed {
                items.append(Guidance(
                    id: "aodRed", kind: .info,
                    message: "AOD kırmızı mod: yalnızca derinlik ve uyarılar gösteriliyor.",
                    action: nil))
            }

            if profile == .saver {
                items.append(Guidance(
                    id: "saverProfile", kind: .info,
                    message: "Pil tasarrufu profili etkin.",
                    action: nil))
            }

            return items
        }
    }
}
