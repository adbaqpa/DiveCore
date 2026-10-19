#if os(watchOS)
import SwiftUI
import DiveCore

/// Dalış öncesi ayarlar ekranı (ADIM 6): GF, çoklu gaz, derin duraklar.
///
/// Tüm veriler `DiveSettingsDisplay` üzerinden gelir; ekran yalnızca listeler
/// ve `DiveSettings` değerini günceller.
struct DiveSettingsScreen: View {

    @Binding var settings: DiveSettings
    @Binding var display: DiveSettingsDisplay
    /// Tahmini NDL (hesaplanmışsa)
    var ndl: TimeInterval = 0

    @State private var selectedGasIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                targetHeader
                gradientFactorSection
                gasSection
                deepStopSection
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.surfaceBackground.ignoresSafeArea())
    }

    // MARK: - Başlık

    private var targetHeader: some View {
        HStack {
            metric("Hedef", display.targetDepthText)
            Spacer()
            metric("Süre", display.targetDurationText)
            Spacer()
            metric("NDL", display.estimatedNDLText)
        }
        .padding(.vertical, 2)
    }

    // MARK: - GF

    private var gradientFactorSection: some View {
        section("GF Ayarları") {
            ForEach(display.factorsRows) { row in
                Button {
                    if let preset = GradientFactorCatalog.preset(id: row.id) {
                        settings.gradientFactors = preset.factors
                        refresh()
                    }
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(row.name)
                                    .font(DiveTypography.font(for: .medium))
                                    .foregroundStyle(DivePalette.color(for: row.isSelected ? .hero : .secondary))
                                if row.isRecommended {
                                    Text("ÖNERİ")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(DivePalette.color(for: .safe))
                                        .padding(.horizontal, 3)
                                        .background(DivePalette.color(for: .safe).opacity(0.2),
                                                    in: Capsule())
                                }
                            }
                            Text(row.factorsText)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(DivePalette.color(for: row.isSelected ? .accent : .secondary))
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        if row.isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DivePalette.color(for: .safe))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Özel GF girişi
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Özel")
                        .font(DiveTypography.font(for: .small))
                        .foregroundStyle(DivePalette.color(for: .secondary))
                    Spacer()
                    Text(display.customRow.low == display.selectedFactors.low ? "•" : "")
                    Text("\(display.customRow.low)/\(display.customRow.high)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DivePalette.color(for: display.customRow.isCaution ? .caution : .hero))
                }
                Slider(value: Binding(
                    get: { Double(settings.gradientFactors.low) },
                    set: { value in
                        let low = Int(value.rounded())
                        settings.gradientFactors = GradientFactors(low: low, high: max(low, settings.gradientFactors.high))
                        refresh()
                    }),
                    in: Double(GradientFactorCatalog.allowedRange.lowerBound)...Double(GradientFactorCatalog.allowedRange.upperBound),
                    step: 5)
                .tint(DivePalette.color(for: .accent))
                if display.customRow.isCaution {
                    Text(display.customRow.note)
                        .font(DiveTypography.font(for: .micro))
                        .foregroundStyle(DivePalette.color(for: .caution))
                }
            }
        }
    }

    // MARK: - Gaz

    private var gasSection: some View {
        section("Gazlar") {
            ForEach(Array(display.gasRows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(row.label)
                                .font(DiveTypography.font(for: .medium))
                                .foregroundStyle(DivePalette.color(for: .hero))
                            if row.isStartGas {
                                Text("BAŞLANGIÇ")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(DivePalette.color(for: .accent))
                            }
                            if row.isDecoGas {
                                Text("DEKO")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(DivePalette.color(for: .deco))
                            }
                        }
                        Text(row.nitrogenPercentText)
                            .font(DiveTypography.font(for: .micro))
                            .foregroundStyle(DivePalette.color(for: .secondary))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("MOD \(row.modText)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DivePalette.color(for: row.colorRole))
                            .monospacedDigit()
                        Text(row.isUsableAtTargetDepth ? "hedefte uygun" : "hedef için uygun değil")
                            .font(DiveTypography.font(for: .micro))
                            .foregroundStyle(DivePalette.color(for: row.colorRole))
                    }
                }
                .padding(.vertical, 1)
            }

            if !display.switchNote.isEmpty {
                Text(display.switchNote)
                    .font(DiveTypography.font(for: .micro))
                    .foregroundStyle(DivePalette.color(for: .accent))
            }
            ForEach(display.gasIssues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(DiveTypography.font(for: .micro))
                    .foregroundStyle(DivePalette.color(for: .caution))
            }

            // Nitrox hızlı seçim
            nitroxPicker
        }
    }

    private var nitroxPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("EAN %")
                    .font(DiveTypography.font(for: .small))
                    .foregroundStyle(DivePalette.color(for: .secondary))
                Spacer()
                Text("\(settings.gasPlan.startGas.oxygenFraction * 100)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DivePalette.color(for: .accent))
            }
            Slider(value: Binding(
                get: { settings.gasPlan.startGas.oxygenFraction * 100 },
                set: { value in
                    let percent = Int(value.rounded())
                    guard let gas = GasMix.nitrox(percent) else { return }
                    var cylinders = settings.gasPlan.cylinders
                    cylinders[0] = GasPlan.Cylinder(id: cylinders[0].id, gas: gas,
                                                    sizeLiters: cylinders[0].sizeLiters,
                                                    fillPressure: cylinders[0].fillPressure)
                    settings.gasPlan = GasPlan(cylinders: cylinders,
                                               water: settings.gasPlan.water,
                                               maxPO2: settings.gasPlan.maxPO2)
                    refresh()
                }),
                in: Double(NitroxPicker.standardRange.lowerBound)...Double(NitroxPicker.standardRange.upperBound),
                step: 1)
            .tint(DivePalette.color(for: .accent))
            Text("Önerilen: EAN%\(settings.targetNitroxPercent)")
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
    }

    // MARK: - Derin duraklar

    private var deepStopSection: some View {
        section("Derin Duraklar") {
            Toggle(isOn: Binding(
                get: { settings.deepStops.isEnabled },
                set: { value in
                    settings.deepStops.isEnabled = value
                    refresh()
                })) {
                Text("Derin durakları hesapla (GUE tarzı)")
                    .font(DiveTypography.font(for: .small))
                    .foregroundStyle(DivePalette.color(for: .hero))
            }
            .tint(DivePalette.color(for: .accent))

            Text(display.deepStopNote)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))

            ForEach(display.deepStopRows) { row in
                HStack {
                    Text(row.depthText)
                        .font(DiveTypography.font(for: .medium))
                        .foregroundStyle(DivePalette.color(for: row.colorRole))
                    Spacer()
                    Text(row.holdText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DivePalette.color(for: row.colorRole))
                }
            }

            if settings.deepStops.isEnabled {
                VStack(alignment: .leading, spacing: 1) {
                    stepperRow("Aralık", value: settings.deepStops.interval, step: 1.5) {
                        settings.deepStops.interval = $0
                        refresh()
                    }
                    stepperRow("En derin", value: settings.deepStops.lastStopDepth, step: 3) {
                        settings.deepStops.lastStopDepth = $0
                        refresh()
                    }
                }
            }
        }
    }

    private func stepperRow(_ title: String, value: Double, step: Double,
                            apply: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
            Spacer()
            Button {
                apply(max(0.5, value - step))
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            Text(String(format: "%.0f m", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 44)
            Button {
                apply(value + step)
            } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
        .foregroundStyle(DivePalette.color(for: .accent))
    }

    // MARK: - Yardımcılar

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DiveTypography.font(for: .small))
                .foregroundStyle(DivePalette.color(for: .secondary))
            content()
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: .hero))
                .monospacedDigit()
            Text(label)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
    }

    private func refresh() {
        display = DiveSettingsDisplay(settings: settings,
                                      targetDepth: settings.targetDepth,
                                      targetDuration: settings.targetDuration,
                                      estimatedNDL: ndl)
    }
}
#endif