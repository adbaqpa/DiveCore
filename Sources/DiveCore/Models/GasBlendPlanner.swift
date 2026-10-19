import Foundation

/// Çoklu gaz planı — silindirler, gaz değişim önerileri ve MOD bütünlüğü.
///
/// ADIM 6 gereksinimi: "sadece hava değil, %22–%40 Nitrox seçilebilsin ve MOD
/// hesaplaması entegre edilsin".
public struct GasPlan: Equatable, Codable, Sendable {

    /// Silindirdaki bir gaz.
    public struct Cylinder: Equatable, Codable, Sendable, Identifiable {
        public let id: UUID
        public let gas: GasMix
        /// Silindir hacmi (litre) — ekranda "12L" olarak gösterilir
        public let sizeLiters: Int
        /// Kullanılabilir gaz (bar × litre) — tüketim tahmini için
        public let fillPressure: Double
        /// Bu silindire özel PO₂ limiti (bar).
        ///
        /// - Important: Gerçek dalış planlamasında **dip gazı 1.4 bar**,
        ///   **deko O₂'si 1.6 bar** limitle kullanılır (dalış bilgisayarlarının
        ///   "O₂ MOD = 6 m" değeri 1.6 bar içindir). `nil` ise planın geneli
        ///   kullanılır.
        public let maxPO2Override: Double?

        public init(id: UUID = UUID(), gas: GasMix, sizeLiters: Int = 12,
                    fillPressure: Double = 200, maxPO2Override: Double? = nil) {
            self.id = id
            self.gas = gas
            self.sizeLiters = sizeLiters
            self.fillPressure = fillPressure
            self.maxPO2Override = maxPO2Override
        }

        /// Bu silindirin geçerli PO₂ limiti.
        public func effectiveMaxPO2(planMaxPO2: Double = DiveSafetyLimits.maximumPO2) -> Double {
            maxPO2Override ?? planMaxPO2
        }

        /// Etiket ("EAN32 · 12L").
        public var label: String { "\(gas.label) · \(sizeLiters)L" }

        /// Azami kullanım derinliği (m) — PO₂ sınırından.
        public func maximumOperatingDepth(maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                          water: DivePhysics.WaterType = .salt) -> Double {
            gas.maximumOperatingDepth(maxPO2: maxPO2, water: water)
        }

        /// Gaz değişim önerilen derinlik (m): bir sonraki gazın MOD'una eşit.
        /// (EAN → O2 değişimleri 6 m'de yapılır.)
        public func switchDepth(to next: Cylinder,
                                safetyMargin: Double = 3,
                                maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                water: DivePhysics.WaterType = .salt) -> Double {
            max(0, next.maximumOperatingDepth(maxPO2: maxPO2, water: water) - safetyMargin)
        }

        /// Bu derinlikte kullanılabilir mi?
        public func isUsable(at depth: Double,
                              maxPO2: Double = DiveSafetyLimits.maximumPO2,
                              water: DivePhysics.WaterType = .salt) -> Bool {
            depth <= maximumOperatingDepth(maxPO2: maxPO2, water: water) + 0.5
        }
    }

    public var cylinders: [Cylinder]
    public var water: DivePhysics.WaterType
    public var maxPO2: Double

    public init(cylinders: [Cylinder] = [Cylinder(gas: .air)],
                water: DivePhysics.WaterType = .salt,
                maxPO2: Double = DiveSafetyLimits.maximumPO2) {
        self.cylinders = cylinders.isEmpty ? [Cylinder(gas: .air)] : cylinders
        self.water = water
        self.maxPO2 = maxPO2
    }

    public static func air(maxPO2: Double = DiveSafetyLimits.maximumPO2) -> GasPlan {
        GasPlan(cylinders: [Cylinder(gas: .air)], maxPO2: maxPO2)
    }

    public static func single(_ gas: GasMix,
                              sizeLiters: Int = 12,
                              maxPO2: Double = DiveSafetyLimits.maximumPO2) -> GasPlan {
        GasPlan(cylinders: [Cylinder(gas: gas, sizeLiters: sizeLiters)], maxPO2: maxPO2)
    }

    /// İki silindirli tipik plan: EAN + deko gazı (saf O₂, 1.6 bar limit).
    public static func nitroxWithDeco(_ mix: GasMix,
                                      maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                      decoMaxPO2: Double = 1.6) -> GasPlan {
        GasPlan(cylinders: [Cylinder(gas: mix),
                            Cylinder(gas: .oxygen, sizeLiters: 7, maxPO2Override: decoMaxPO2)],
                maxPO2: maxPO2)
    }

    /// Tüm silindirlerin etiketleri (sırayla).
    public var labels: [String] { cylinders.map(\.label) }

    /// Başlangıç gazı.
    public var startGas: GasMix { cylinders.first?.gas ?? .air }

    /// Bir derinlikte **kullanılabilir** gazların indeksleri.
    public func usableIndices(at depth: Double) -> [Int] {
        cylinders.indices.filter {
            cylinders[$0].isUsable(at: depth,
                                   maxPO2: cylinders[$0].effectiveMaxPO2(planMaxPO2: maxPO2),
                                   water: water)
        }
    }

    /// Bir derinlikte kullanılabilecek en yüksek O₂'li gazın indeksi.
    ///
    /// - Önemli: MOD'u geçen gaz **asla** önerilmez (aşırı PO₂ → O₂ zehirlenmesi).
    public func bestIndex(at depth: Double) -> Int? {
        usableIndices(at: depth)
            .max(by: { cylinders[$0].gas.oxygenFraction < cylinders[$1].gas.oxygenFraction })
    }

    /// Derinlikte gaz değişimi gerekiyor mu?
    ///
    /// - Note: Değişim **aşağı doğru** yapılır: bir gazın MOD'u geçildiğinde daha
    ///   derin kullanılabilir (düşük O₂'li) gaza geçilir. Eğer **hiçbir gaz**
    ///   bu derinlikte kullanılamıyorsa dalış sınırı aşılmıştır: `suggestion`
    ///   `nil` döner ve dalgıç yüzeye çıkmalıdır.
    public func requiresSwitch(at depth: Double, currentIndex: Int) -> Bool {
        guard cylinders.indices.contains(currentIndex) else { return false }
        let cylinder = cylinders[currentIndex]
        return !cylinder.isUsable(at: depth,
                                  maxPO2: cylinder.effectiveMaxPO2(planMaxPO2: maxPO2),
                                  water: water)
    }

    /// Bu derinlikte **herhangi bir** gaz kullanılabilir mi?
    public func canReach(depth: Double) -> Bool {
        cylinders.contains {
            $0.isUsable(at: depth, maxPO2: $0.effectiveMaxPO2(planMaxPO2: maxPO2), water: water)
        }
    }

    /// Mevcut gazdan daha derine uygun gaz önerisi.
    public func suggestion(at depth: Double, currentIndex: Int) -> Cylinder? {
        guard let best = bestIndex(at: depth), best != currentIndex,
              cylinders.indices.contains(best) else { return nil }
        return cylinders[best]
    }

    /// Gaz değişim planı (derinlik → gaz) — ekranda liste olarak gösterilir.
    public func switchTable() -> [(depth: Double, from: GasMix, to: GasMix)] {
        var result: [(Double, GasMix, GasMix)] = []
        for index in 0..<(cylinders.count - 1) {
            let depth = cylinders[index].switchDepth(to: cylinders[index + 1],
                                                     maxPO2: cylinders[index + 1].effectiveMaxPO2(planMaxPO2: maxPO2),
                                                     water: water)
            result.append((depth, cylinders[index].gas, cylinders[index + 1].gas))
        }
        return result
    }

    /// Plan bütünlük denetimi.
    public func validate() -> [GasPlanIssue] {
        var issues: [GasPlanIssue] = []

        for (index, cylinder) in cylinders.enumerated() {
            let mod = cylinder.maximumOperatingDepth(maxPO2: cylinder.effectiveMaxPO2(planMaxPO2: maxPO2),
                                                      water: water)
            // Saf O₂ 6 m'den derinde kullanılamaz. Deko O₂'si 1.6 bar limitle
            // planlanır (MOD ≈ 6.6 m) ve bu **normaldir**; uyarı yalnızca
            // sınırın epey üstünde (≥ 7 m) bir deko gazı için üretilir.
            if cylinder.gas.oxygenFraction >= 0.99, mod > 7.0 {
                issues.append(.decoGasTooDeep(index: index, limit: 6))
            }
            // Sıralama: MOD'lar azalan olmalı (yüksek O₂ önce)
            if index > 0 {
                let previous = cylinders[index - 1]
                let previousMOD = previous.maximumOperatingDepth(
                    maxPO2: previous.effectiveMaxPO2(planMaxPO2: maxPO2), water: water)
                if mod > previousMOD { issues.append(.wrongOrder(index: index)) }
            }
        }
        // Başlangıç gazı daha sığ silindirle başlanıyorsa uyarı
        if let start = cylinders.first,
           start.maximumOperatingDepth(maxPO2: start.effectiveMaxPO2(planMaxPO2: maxPO2),
                                       water: water) <= 0 {
            issues.append(.startGasUnusable)
        }
        return issues
    }

    /// Gaz planı sorunları.
    public enum GasPlanIssue: Equatable, Sendable {
        /// Saf O₂ 6 m'den derinde kullanılamaz
        case decoGasTooDeep(index: Int, limit: Double)
        /// Silindirler yanlış sırada (MOD artıyor)
        case wrongOrder(index: Int)
        /// Başlangıç gazı hiç kullanılamıyor
        case startGasUnusable

        public var message: String {
            switch self {
            case .decoGasTooDeep(_, let limit):
                return "Saf O₂ \(Int(limit)) m'den derinde kullanılamaz (deko gazı)"
            case .wrongOrder(let index):
                return "\(index). silindir yanlış sırada: daha derin kullanılabilir gaz önce olmalı"
            case .startGasUnusable:
                return "Başlangıç gazı kullanılamıyor — MOD çok sığ"
            }
        }

        public var isWarningOnly: Bool {
            if case .decoGasTooDeep = self { return true }
            return false
        }
    }
}

/// Nitrox seçimi yardımcıları.
public enum NitroxPicker {

    /// Standart EAN aralığı (UI kaydırıcısı).
    public static let standardRange: ClosedRange<Int> = 21...40

    /// Verilen yüzde geçerli bir solunabilir karışım mı? (%21–%100)
    public static func isValid(percent: Int) -> Bool {
        (21...100).contains(percent)
    }

    /// En yüksek O₂ oranını güvenle kullanılabilecek şekilde seçer.
    ///
    /// - Parameters:
    ///   - targetDepth: Hedef dalış derinliği (m)
    ///   - maxPO2: Azami oksijen basıncı (bar)
    /// - Returns: EAN yüzdesi (21–40 aralığında, en yüksek güvenli değer)
    public static func recommendedPercent(targetDepth: Double,
                                          maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                          water: DivePhysics.WaterType = .salt,
                                          maximum: Int = 40) -> Int {
        for percent in stride(from: min(maximum, 100), through: 21, by: -1) {
            let gas = GasMix(oxygenPercent: Double(percent))
            if gas.maximumOperatingDepth(maxPO2: maxPO2, water: water) >= targetDepth {
                return percent
            }
        }
        return 21   // hava
    }

    /// EAN üretir (yüzde tam sayı).
    public static func ean(_ percent: Int) -> GasMix? {
        guard isValid(percent: percent) else { return nil }
        return GasMix(oxygenPercent: Double(percent))
    }

    /// MOD'u verilen yüzdeye göre döndürür (UI'de tek satır bilgi).
    public static func maximumDepth(for percent: Int,
                                    maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                    water: DivePhysics.WaterType = .salt) -> Double? {
        guard let gas = ean(percent) else { return nil }
        return gas.maximumOperatingDepth(maxPO2: maxPO2, water: water)
    }

    /// Karışımın nitrojen oranı (yüzde) — "daha az N₂ = daha az deko" bilgisi.
    public static func nitrogenPercent(_ percent: Int) -> Int? {
        guard isValid(percent: percent) else { return nil }
        return 100 - percent
    }
}

extension GasMix {
    /// Tam sayı yüzdeyle EAN üretir (21–40 aralığında).
    public static func nitrox(_ percent: Int) -> GasMix? {
        NitroxPicker.ean(percent)
    }

    /// Nitrox mu (EAN21'den zengin)?
    public var isNitrox: Bool { oxygenFraction > 0.21 + 0.0001 }

    /// Nitrojen yüzdesi.
    public var nitrogenPercent: Int { Int((nitrogenFraction * 100).rounded()) }

    /// MOD metni ("33.0 m").
    public func maximumOperatingDepthText(maxPO2: Double = DiveSafetyLimits.maximumPO2,
                                          water: DivePhysics.WaterType = .salt) -> String {
        String(format: "%.1f m", maximumOperatingDepth(maxPO2: maxPO2, water: water))
    }
}