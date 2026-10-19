#if os(watchOS)
import SwiftUI
import DiveCore

/// Su kilidi katmanı (ADIM 7).
///
/// İki işi birden yapar:
/// 1. Kilitliyken dokunuşu **bloke eder** (`hit testing` kapalı) — su damlası
///    veya kol hareketi yanlışlıkla "dalışı bitir" gibi bir eylemi tetiklemez.
/// 2. Su atma döngüsünü kullanıcıya gösterir.
struct DiveLockOverlay: ViewModifier {

    let lock: DiveLockController
    /// Su atma döngüsünün kalan adımları
    var ejectionStepName: String?
    var ejectionProgress: Double = 0

    func body(content: Content) -> some View {
        content
            .disabled(lock.isLocked && lock.blocksTouch(on: .diveScreen))
            .overlay {
                if lock.phase == .ejecting, let step = ejectionStepName {
                    VStack(spacing: 6) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DivePalette.color(for: .accent))
                        Text("Suyu at")
                            .font(DiveTypography.font(for: .medium))
                            .foregroundStyle(DivePalette.color(for: .hero))
                        Text(DiveLockController.ejectionGuidance)
                            .font(DiveTypography.font(for: .micro))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(DivePalette.color(for: .secondary))
                        ProgressView(value: ejectionProgress)
                            .tint(DivePalette.color(for: .accent))
                        Text(step)
                            .font(DiveTypography.font(for: .micro))
                            .foregroundStyle(DivePalette.color(for: .accent))
                    }
                    .padding(10)
                    .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 12))
                }
            }
    }
}

extension View {
    /// Dalış sırasında dokunma kilidi uygular.
    func diveLockOverlay(_ lock: DiveLockController,
                         ejectionStepName: String? = nil,
                         ejectionProgress: Double = 0) -> some View {
        modifier(DiveLockOverlay(lock: lock,
                                 ejectionStepName: ejectionStepName,
                                 ejectionProgress: ejectionProgress))
    }

    /// Acil durum menüsü (Action Button basılı tutma).
    struct EmergencyMenu: View {
        let actions: [DiveLockController.ButtonAction]
        let guidance: String
        var perform: (DiveLockController.ButtonAction) -> Void

        var body: some View {
            VStack(spacing: 5) {
                Label("Acil Durum", systemImage: "exclamationmark.shield.fill")
                    .font(DiveTypography.font(for: .medium))
                    .foregroundStyle(DivePalette.color(for: .danger))

                Text(guidance)
                    .font(DiveTypography.font(for: .micro))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DivePalette.color(for: .secondary))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                ForEach(actions, id: \.self) { action in
                    Button {
                        perform(action)
                    } label: {
                        Label(action.label, systemImage: action.symbolName)
                            .font(DiveTypography.font(for: .small))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(color(for: action))
                }
            }
            .padding(8)
            .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 12))
        }

        private func color(for action: DiveLockController.ButtonAction) -> Color {
            switch action {
            case .startSafetyStop, .ascentAssist:
                return DivePalette.color(for: .caution)
            case .endDive:
                return DivePalette.color(for: .secondary)
            default:
                return DivePalette.color(for: .accent)
            }
        }
    }
}
#endif