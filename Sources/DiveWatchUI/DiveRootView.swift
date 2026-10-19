#if os(watchOS)
import SwiftUI
import DiveCore

/// Uygulamanın kök görünümü: mod seçimi tamamen `DiveScreenMode`'a bağlıdır.
struct DiveRootView: View {

    @StateObject private var model = DiveViewModel()
    @State private var showsSettings = false
    /// ADIM 11 — enerji/görüntü ayarları
    @State private var showsEnergy = false

    var body: some View {
        Group {
            switch model.display.mode {
            case .preDive where showsEnergy:
                EnergySettingsScreen(settings: $model.settings, energy: model.energy)
                    .onDisappear { model.setPowerProfile(model.settings.powerProfile) }
                    .diveLockOverlay(model.lock)
            case .preDive where showsSettings:
                DiveSettingsScreen(settings: $model.settings,
                                  display: $model.settingsDisplay,
                                  ndl: model.settingsDisplay.estimatedNDL.seconds)
                    .onDisappear { model.refreshSettings() }
                    .diveLockOverlay(model.lock)
                    .onAppear { model.refreshSettings() }
            case .preDive:
                PreDiveScreen(actionLabel: DiveActionIntent.startDive.label,
                              actionSymbol: DiveActionIntent.startDive.symbolName,
                              theme: model.theme,
                              onOpenSettings: { showsSettings = true },
                              onOpenEnergy: { showsEnergy = true }) {
                    try? model.startDive(scenario: DiveScenario.recreational30m)
                }
            case .summary:
                if let report = model.report {
                    DiveReportScreen(display: report) { }
                } else if let summary = model.summary {
                    DiveSummaryScreen(summary: summary) { }
                } else {
                    DiveScreen(model: model)
                }
            case .surfaced, .diving, .safetyStop, .decoObligation:
                DiveScreen(model: model)
                    .diveLockOverlay(model.lock,
                                     ejectionStepName: model.ejectionStep,
                                     ejectionProgress: model.ejectionProgress)
                    .overlay(alignment: .bottom) {
                        if model.isEmergencyMenuPresented {
                            DiveLockOverlay.EmergencyMenu(
                                actions: model.lock.emergencyMenu(for: model.lock.guidance),
                                guidance: model.lock.guidance.instruction) { action in
                                model.perform(action)
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                    .gesture(
                        // Uzun basış: dalışı bitir (Action Button alternatifi)
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in }
                    )
            }
        }
    }
}

#Preview("Dalış") {
    DiveScreen(model: DiveViewModel())
}

#Preview("Enerji ve Görüntü") {
    EnergySettingsScreen(
        settings: .constant(.recreational),
        energy: EnergyManager(state: EnergyState(batteryLevel: 0.24, isDiving: true)))
}

#Preview("Çıkış rehberi") {
    GuidanceCard(display: GuidanceDisplay(guidance: AscentAdvisor().evaluate(
        DiveState(phase: .ascending, currentDepth: 9, maxDepth: 30, diveTime: 2000,
                  ascentRate: 3, ceilingDepth: 6, nextStopDepth: 6, timeToSurface: 900))))
}

#Preview("Komplikasyon — Dairesel") {
    DiveCircularComplication(
        data: DiveComplicationBuilder.build(
            from: DiveState(phase: .bottom, currentDepth: 24.6, maxDepth: 30,
                            diveTime: 760, ascentRate: 8.4,
                            noDecompressionLimit: 320, gf99: 62),
            style: .circular))
}

#Preview("Komplikasyon — Dikdörtgen") {
    DiveRectangularComplication(
        data: DiveComplicationBuilder.build(
            from: DiveState(phase: .ascending, currentDepth: 6.2, maxDepth: 30,
                            diveTime: 1500, ascentRate: 4.1,
                            noDecompressionLimit: 240, gf99: 88),
            style: .rectangular))
}
#endif