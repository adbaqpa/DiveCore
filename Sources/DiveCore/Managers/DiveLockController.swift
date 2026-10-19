import Foundation

/// Dalış sırasında dokunma kilidi, su çıkarma döngüsü ve Action Button
/// yönlendirmesi (ADIM 7).
///
/// ## Donanım gerçekliği (önemli)
/// Apple Watch'ın **Water Lock**'u bir uygulama API'si ile açılamaz; sistem
/// seviyesinde bir kilittir ve kullanıcı Control Center'dan veya su algılandığında
/// devreye girer. Bu nedenle burada iki ayrı mekanizma yönetilir:
///
/// 1. **Uygulama içi dokunma kilidi** — ekranın `hit testing`'i kapatılır,
///    kazara dokunma (su damlası, hareket) kullanıcı eylemi tetiklemez.
/// 2. **Sistem su kilidi yönlendirmesi** — kullanıcıya yönlendirme metni,
///    otomatik kontrol (`isSystemLockExpected`) ve çıkışta hatırlatma.
///
/// Su atma (audio ejection) döngüsü: hoparlörden kısa sesler çalınarak titreşim
/// sağlanır; ardından kullanıcı kolunu çevirip cihazı sallaması istenir.
/// Ses çalma `WatchWaterLockAdapter` tarafından yapılır, **sıralama ve zamanlama**
/// ise burada test edilebilir.
@MainActor
public final class DiveLockController {

    // MARK: - Yayın

    /// Durum değiştiğinde çağrılır (SwiftUI tarafı `objectWillChange` üretmek için
    /// kullanır; çekirdek modül Combine/SwiftUI bağımlılığı taşımaz).
    public var onChange: ((DiveLockController) -> Void)?

    public private(set) var isLocked: Bool = false
    public private(set) var phase: Phase = .idle
    public private(set) var pressCount: Int = 0

    // MARK: - Durum

    /// Dalış kilidi durumu.
    public enum Phase: String, Equatable, Sendable {
        /// Dalış yok — dokunma açık
        case idle
        /// Dalış başladı, ekran kilitli
        case diving
        /// Dalış bitti, su atma döngüsü sürüyor
        case ejecting
        /// Su atıldı, ekran kilidi açıldı
        case unlocked

        public var blocksTouch: Bool { self == .diving }
    }

    /// Action Button basış türü.
    public enum Press: String, Equatable, Sendable {
        /// Tek basış
        case single
        /// Basılı tutma
        case longPress
    }

    // MARK: - Ayarlar

    /// Dokunma kilidinin açılacağı ekranlar (alt küme).
    public var lockableSurfaces: Set<Surface> = [.diveScreen, .banner]
    /// Su atma döngüsü ses sayısı
    public var ejectionSequence: [EjectionStep] = EjectionStep.standard
    /// Dalış başlangıcında otomatik kilitle
    public var autoLockOnDiveStart = true
    /// Sistem su kilidi kullanıcı tarafından etkinleştirildi mi (kullanıcı ayarı)
    public var isSystemWaterLockEnabled = false

    /// Ekran/kontroller.
    public enum Surface: String, Equatable, Sendable, CaseIterable {
        case diveScreen
        case banner
        case compass
        case gasSelector
        case emergencyMenu
    }

    /// Su atma döngüsünün tek adımı.
    public struct EjectionStep: Equatable, Sendable {
        /// Adım etiketi ("Titreşim")
        public let name: String
        /// Bu adımdan sonra beklenecek süre (saniye)
        public let delay: TimeInterval
        /// Adım sonunda çalınacak ses (WatchKit/AV tarafında kullanılır)
        public let sound: Sound

        public enum Sound: String, Equatable, Sendable {
            case tone
            case click
            case chirp
            case success
        }

        public init(name: String, delay: TimeInterval, sound: Sound) {
            self.name = name
            self.delay = delay
            self.sound = sound
        }

        /// Standart su atma döngüsü: titreşim → ses → titreşim → ses,
        /// ardından kol çevirme.
        public static let standard: [EjectionStep] = [
            EjectionStep(name: "Titreşim", delay: 1.0, sound: .tone),
            EjectionStep(name: "Ses", delay: 1.2, sound: .chirp),
            EjectionStep(name: "Titreşim", delay: 1.0, sound: .click),
            EjectionStep(name: "Ses", delay: 1.2, sound: .chirp)
        ]
    }

    // MARK: - Yaşam döngüsü

    public init() {}

    /// Dalış başladı: dokunma kilidini etkinleştirir.
    public func onDiveStarted() {
        phase = .diving
        if autoLockOnDiveStart { isLocked = true }
        pressCount = 0
        notify()
    }

    /// Dalış bitti: su atma döngüsünü başlatır (kilit açılmadan önce).
    public func onDiveEnded() -> [EjectionStep] {
        phase = .ejecting
        // Kilit, su atma döngüsü boyunca **açık kalır** (kullanıcı kolunu
        // çevirebilmeli); biter bitmez serbest bırakılır.
        isLocked = false
        pressCount = 0
        notify()
        return ejectionSequence
    }

    /// Su atma döngüsü tamamlandı (kullanıcı kol çevirdi).
    public func onEjectionCompleted() {
        phase = .unlocked
        isLocked = false
        notify()
    }

    /// Kullanıcı kilidi manuel olarak açtı (Digital Crown çevirme).
    public func unlock() {
        isLocked = false
        if phase == .diving { phase = .unlocked }
        notify()
    }

    /// Yeniden kilitle.
    public func lock() {
        isLocked = true
        notify()
    }

    /// Kilidi sıfırla (dalış yok).
    public func reset() {
        isLocked = false
        phase = .idle
        pressCount = 0
        notify()
    }

    private func notify() {
        onChange?(self)
    }

    // MARK: - Dokunma politikası

    /// Belirli bir yüzey şu anda dokunmayı engelliyor mu?
    public func blocksTouch(on surface: Surface) -> Bool {
        isLocked && lockableSurfaces.contains(surface)
    }

    /// Acil durum menüsü kilitleme dışında mı? (her zaman erişilebilir olmalı)
    public var allowsEmergencyMenu: Bool {
        !blocksTouch(on: .emergencyMenu)
    }

    // MARK: - Action Button

    /// Action Button basışı → eylem.
    public enum ButtonAction: Equatable, Sendable {
        /// Dalış başlat
        case startDive
        /// Yer imi koy (tek basış)
        case placeMarker
        /// Acil durum menüsünü aç (basılı tutma)
        case openEmergencyMenu
        /// Emniyet durağını tetikle
        case startSafetyStop
        /// Yüzeye çıkış yardımı (plan + tavan bilgisi)
        case ascentAssist
        /// Alarmı sustur
        case acknowledgeAlarm
        /// Dalışı bitir
        case endDive
        /// İşlem yok
        case none

        public var label: String {
            switch self {
            case .startDive: return "Dalışı Başlat"
            case .placeMarker: return "İşaret Koy"
            case .openEmergencyMenu: return "Acil Durum"
            case .startSafetyStop: return "Emniyet Durağı"
            case .ascentAssist: return "Çıkış Yardımı"
            case .acknowledgeAlarm: return "Aları Sustur"
            case .endDive: return "Dalışı Bitir"
            case .none: return "—"
            }
        }

        public var symbolName: String {
            switch self {
            case .startDive: return "play.fill"
            case .placeMarker: return "mappin.and.ellipse"
            case .openEmergencyMenu: return "exclamationmark.shield.fill"
            case .startSafetyStop: return "shield.checkered"
            case .ascentAssist: return "arrow.up.circle.fill"
            case .acknowledgeAlarm: return "bell.slash.fill"
            case .endDive: return "stop.fill"
            case .none: return "circle"
            }
        }
    }

    /// Basış türüne göre eylemi çözer.
    ///
    /// - Not: Önce **kilit durumu** değil **basış türü** belirleyicidir: basılı
    ///   tutma her zaman acil durum menüsünü açar (dalgıç suda olduğunu
    ///   unutsa bile erişebilmelidir).
    public func action(for press: Press, isDiving: Bool, hasCriticalAlarm: Bool) -> ButtonAction {
        if press == .longPress {
            return isDiving ? .openEmergencyMenu : .startDive
        }
        // Tek basış
        if hasCriticalAlarm { return .acknowledgeAlarm }
        if isDiving { return .placeMarker }
        return .startDive
    }

    /// Basış sayacını artırır (UI geri bildirimi için).
    public func registerPress() {
        pressCount += 1
        notify()
    }

    /// Dalışın canlı çıkış rehberi (acil durum menüsünde gösterilir).
    ///
    /// - Note: SwiftUI dışında kullanılabilmesi için metin olarak saklanır;
    ///   canlı değer `DiveSessionController.guidance` ile eşitlenir.
    public var guidance: GuidanceSnapshot = GuidanceSnapshot()

    /// Çıkış rehberinin anlık görüntüsü.
    public struct GuidanceSnapshot: Equatable, Sendable {
        public var instruction = "Emniyet durağına in ve 3 dakika bekle"
        public var isAboveCeiling = false

        public init(instruction: String = "Emniyet durağına in ve 3 dakika bekle",
                    isAboveCeiling: Bool = false) {
            self.instruction = instruction
            self.isAboveCeiling = isAboveCeiling
        }
    }

    /// Acil durum menüsünün içeriği.
    public func emergencyMenu(for guidance: AscentAdvisor.Guidance) -> [ButtonAction] {
        var actions: [ButtonAction] = [.startSafetyStop, .ascentAssist]
        if guidance.isAboveCeiling {
            // Tavan ihlali acil durumda en üstte
            actions.insert(.openEmergencyMenu, at: 0)
        }
        actions.append(.endDive)
        return actions
    }

    // MARK: - Kullanıcı metinleri

    /// Su kilidi yönlendirme metni (dalış öncesi).
    public var waterLockGuidance: String {
        isSystemWaterLockEnabled
            ? "Su kilidi etkin — ekran dokunuşları kapalı olacak"
            : "Dalıştan önce Control Center → Su Kilit'i açmanız önerilir"
    }

    /// Su atma yönlendirmesi.
    public static let ejectionGuidance = "Kolunu çevir ve cihazı iki kez salla — suyu at"
}