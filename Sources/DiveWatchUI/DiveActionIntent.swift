#if os(watchOS)
import AppIntents
import Foundation
import DiveCore

/// Apple Watch Ultra **Action Button** (ve "Siri ile" / Shortcuts) için niyet.
///
/// ADIM 7: basış türüne göre yönlendirme yapılır —
/// **tek basış** → dalışı başlat / yer imi koy / alarmı sustur,
/// **basılı tutma** → acil durum menüsü (emniyet durağı / çıkış yardımı).
///
/// Karar `DiveLockController.action(for:isDiving:hasCriticalAlarm:)` tarafından
/// verilir; bu sınıf yalnızca niyeti WatchKit'e taşır.
@available(watchOS 10.0, *)
struct DiveActionIntentHandler: LiveActivityIntent {   // LiveActivityIntent: uygulama önde değilken de
    static var title: LocalizedStringResource = "Dalış Aksiyonu"
    static var description = IntentDescription("Dalışı başlatır, işaret koyar veya alarmı susturur.")

    /// Basış türü (Shortcuts üzerinden gelir).
    enum PressKind: String {
        case single
        case longPress
    }

    /// Tek basış işleyicisi (yer imi / dalış başlat / alarm sustur).
    @MainActor
    static var singlePressHandler: (() -> DiveActionButtonResolver.Outcome)?

    /// Basılı tutma işleyicisi (acil durum menüsü).
    @MainActor
    static var longPressHandler: (() -> DiveActionButtonResolver.Outcome)?

    /// Action Button için `perform()` (tek basış varsayılan).
    @MainActor
    func perform() async throws -> some IntentResult {
        let outcome = DiveActionIntentHandler.singlePressHandler?() ?? .ignored
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialogText))
    }
}

/// Basılı tutma (acil durum) niyeti — Shortcuts/App Intents üzerinden.
@available(watchOS 10.0, *)
struct DiveEmergencyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Acil Durum"
    static var description = IntentDescription("Emniyet durağını tetikler ve çıkış yardımı gösterir.")

    @MainActor
    static var handler: (() -> DiveActionButtonResolver.Outcome)?

    @MainActor
    func perform() async throws -> some IntentResult {
        let outcome = DiveEmergencyIntent.handler?() ?? .ignored
        return .result(dialog: IntentDialog(stringLiteral: outcome.dialogText))
    }
}

@available(watchOS 10.0, *)
extension DiveActionButtonResolver.Outcome {
    /// Kullanıcıya gösterilecek kısa geri bildirim metni.
    var dialogText: String {
        switch self {
        case .started: return "Dalış başladı"
        case .markerAdded: return "İşaret eklendi"
        case .alarmAcknowledged: return "Alarım susturuldu"
        case .ended: return "Dalış bitti"
        case .ignored: return "İşlem yok"
        }
    }
}

/// Action Button'ı `DiveViewModel`'e bağlayan kurulum (`App` katmanında çağrılır).
@available(watchOS 10.0, *)
@MainActor
public enum DiveActionButtonBinder {
    /// Tek basış → işaret/başlat, basılı tutma → acil durum.
    public static func bind(to model: DiveViewModel) {
        DiveActionIntentHandler.singlePressHandler = { [weak model] in
            model?.performActionIntent() ?? .ignored
        }
        DiveEmergencyIntent.handler = { [weak model] in
            model?.performEmergencyIntent() ?? .ignored
        }
    }
}
#endif