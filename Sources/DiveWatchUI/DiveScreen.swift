#if os(watchOS)
import SwiftUI
import WatchKit
import DiveCore

// MARK: - Dalış ekranı

/// Ana dalış ekranı (aktif + Always-On Display).
///
/// Hiçbir karar burada verilmez: tüm değerler `DiveViewModel.display`
/// (`DiveDisplayState`) içinden okunur.
struct DiveScreen: View {

    @ObservedObject var model: DiveViewModel
    @Environment(\.isAlwaysOn) private var isAlwaysOn
    /// Deko/oksijen kartları yalnızca aktif ekranda gösterilir (AOD sade kalır).
    var showsSafetyCards: Bool = true

    private var display: DiveDisplayState { model.display }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                if let banner = display.banner {
                    AlarmBanner(banner: banner)
                }

                depthBlock(height: geometry.size.height * (isAlwaysOn ? 0.42 : 0.36))

                if !isAlwaysOn {
                    metricsRow
                    if showsSafetyCards {
                        GuidanceCard(display: model.guidance)
                    }
                    stopOrDecoStrip
                    HStack {
                        AscentRateGauge(indicator: display.ascentRate, compact: false)
                    }
                    CompassTape(compass: display.compass, visibleDegrees: 120)
                    if showsSafetyCards, model.oxygen.isAlarm {
                        OxygenCard(display: model.oxygen)
                    }
                } else {
                    // AOD: yalnızca derinlik + süre + NDL/tavan
                    HStack {
                        Text(display.diveTimeText)
                        Spacer()
                        Text(display.hasNdl ? "NDL \(display.ndlText)" : "TTS \(display.deco.ttsText)")
                    }
                    .font(DiveTypography.font(for: .alwaysOn))
                    .foregroundStyle(DivePalette.color(for: .hero, theme: display.theme))
                    .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(background)
        .onChange(of: isAlwaysOn) { _, newValue in
            model.updateAlwaysOn(newValue)
        }
    }

    private var background: some View {
        ZStack {
            if display.backgroundColorRole == .criticalBackground {
                DivePalette.criticalBackground(theme: display.theme)
            } else {
                // ADIM 11: gece/AOD temalarında arka plan tamamen kapanır
                // (OLED'da siyah piksel = güç tasarrufu)
                DivePalette.background(theme: display.theme)
            }
            // Deko modunda hafif mor tonlama
            if display.mode == .decoObligation {
                DivePalette.color(for: .deco).opacity(0.08)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Derinlik

    private func depthBlock(height: CGFloat) -> some View {
        HStack(spacing: 8) {
            ZStack {
                DepthRingGauge(indicator: display.depthIndicator,
                               colorRole: display.depthColorRole,
                               lineWidth: 6)
                VStack(spacing: -2) {
                    Text(display.depthText)
                        .font(DiveTypography.font(for: display.depthTextRole))
                        .foregroundStyle(DivePalette.color(for: display.depthColorRole, theme: display.theme))
                        .monospacedDigit()
                    Text(display.depthUnit)
                        .font(DiveTypography.font(for: .micro))
                        .foregroundStyle(DivePalette.color(for: .secondary))
                }
            }
            .frame(width: min(height, 110), height: min(height, 110))

            VStack(alignment: .leading, spacing: 2) {
                metric(label: "Azami", value: "\(display.maxDepthText) m")
                metric(label: "Süre", value: display.diveTimeText)
                metric(label: "Su", value: display.temperatureText)
                metric(label: "Gaz", value: display.gasLabel)
                metric(label: display.hasNdl ? "NDL" : "Tavan",
                       value: display.hasNdl ? display.ndlText : display.deco.ceilingText,
                       colorRole: display.ndlColorRole)
            }
            .font(DiveTypography.font(for: .small))
        }
    }

    private func metric(label: String, value: String, colorRole: DiveColorRole? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(DivePalette.color(for: .secondary))
            Spacer(minLength: 2)
            Text(value)
                .foregroundStyle(DivePalette.color(for: colorRole ?? .hero))
                .monospacedDigit()
        }
    }

    // MARK: - Satırlar

    private var metricsRow: some View {
        HStack(spacing: 6) {
            smallChip(title: display.phaseText,
                      value: display.ascentRate.level.aodSymbol,
                      colorRole: display.ascentRate.level.colorRole)
            smallChip(title: "GF99", value: display.deco.gf99Text,
                      colorRole: display.deco.hasObligation ? .deco : .secondary)
            smallChip(title: "PO₂",
                      value: String(format: "%.2f", model.state.oxygenPartialPressure),
                      colorRole: model.state.oxygenPartialPressure > DiveSafetyLimits.maximumPO2
                        ? .danger : .secondary)
        }
    }

    private func smallChip(title: String, value: String, colorRole: DiveColorRole) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: colorRole))
            Text(title)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var stopOrDecoStrip: some View {
        let stop = display.safetyStop
        if stop.isActive || stop.isComplete || stop.wasAbandoned {
            StopStrip(title: stop.title,
                      primary: stop.remainingText,
                      secondary: stop.subtitle,
                      colorRole: stop.isComplete ? .safe : (stop.wasAbandoned ? .caution : .safe),
                      progress: stop.progress)
        } else if display.deco.hasObligation {
            StopStrip(title: "Deko",
                      primary: "\(display.deco.nextStopText) · \(display.deco.ttsText)",
                      secondary: "GF99 \(display.deco.gf99Text)",
                      colorRole: .deco)
        }
    }
}

// MARK: - Dalış öncesi / özet

/// Dalış başlamadan önceki hazırlık ekranı.
struct PreDiveScreen: View {
    let actionLabel: String
    let actionSymbol: String
    /// ADIM 11 — dalış öncesi ekran da temayı kullanır
    var theme: DiveDisplayTheme = .standard
    var onStart: (() -> Void)?
    /// ADIM 6/11 — ayarlar ve enerji ekranlarına geçiş
    var onOpenSettings: (() -> Void)?
    var onOpenEnergy: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "water.waves")
                .font(.system(size: 34))
                .foregroundStyle(DivePalette.color(for: .accent, theme: theme))
            Text("Dalışa Hazır")
                .font(DiveTypography.font(for: .large))
                .foregroundStyle(DivePalette.color(for: .hero, theme: theme))
            Text("Hazır olduğunda başlat")
                .font(DiveTypography.font(for: .small))
                .foregroundStyle(DivePalette.color(for: .secondary, theme: theme))
            HStack(spacing: 10) {
                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .tint(DivePalette.color(for: .secondary, theme: theme))
                }
                if let onOpenEnergy {
                    Button(action: onOpenEnergy) {
                        Image(systemName: "battery.100")
                    }
                    .tint(DivePalette.color(for: .secondary, theme: theme))
                }
            }
            Spacer()
            Button {
                onStart?()
            } label: {
                Label(actionLabel, systemImage: actionSymbol)
                    .font(DiveTypography.font(for: .medium))
            }
            .tint(DivePalette.color(for: .safe))
        }
        .padding()
        .background(DivePalette.background(theme: theme).ignoresSafeArea())
    }
}

/// Dalış sonu özeti (ADIM 4'te zenginleştirilecek).
struct DiveSummaryScreen: View {
    let summary: DiveSummaryDisplay
    var onDone: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.title)
                    .font(DiveTypography.font(for: .large))
                    .foregroundStyle(DivePalette.color(for: .hero, theme: display.theme))
                Text(summary.gradeText)
                    .font(DiveTypography.font(for: .medium))
                    .foregroundStyle(DivePalette.color(for: .caution))

                row("Azami derinlik", summary.maxDepthText)
                row("Ortalama", summary.averageDepthText)
                row("Süre", summary.diveTimeText)
                row("Sıcaklık", summary.temperatureText)
                row("Deko", summary.decoText)
                row("GF99", summary.gf99Text)
                row("CNS", summary.cnsText)
                row("OTU", summary.otuText)
                row("Emniyet durağı", summary.safetyStopText)
                row("Uçuş yasağı", summary.noFlyText)
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.surfaceBackground.ignoresSafeArea())
        .onTapGesture { onDone?() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DiveTypography.font(for: .small))
                .foregroundStyle(DivePalette.color(for: .secondary))
            Spacer()
            Text(value)
                .font(DiveTypography.font(for: .medium))
                .foregroundStyle(DivePalette.color(for: .hero, theme: display.theme))
                .monospacedDigit()
        }
    }
}
#endif