#if os(watchOS)
import SwiftUI
import DiveCore

/// ADIM 11 — **Enerji ve Görüntü ayar ekranı**.
///
/// Bölümler:
/// 1. **Enerji profili** — performans / dengeli / pil tasarrufu,
/// 2. **Gece modu** — otomatik / her zaman açık / kapalı,
/// 3. **AOD** — açık/kapalı (pil için en büyük kazanç),
/// 4. **Canlı ölçüm** — pil, termal durum, tahmini dayanma süresi,
/// 5. **Öneriler** — `EnergyManager.guidance` listesi.
struct EnergySettingsScreen: View {

    @Binding var settings: DiveSettings
    /// Canlı enerji durumu (adaptörden gelir)
    let energy: EnergyManager

    @State private var previewTheme: DiveDisplayTheme?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                statusCard
                profileSection
                nightModeSection
                alwaysOnSection
                if !energy.guidance.isEmpty { guidanceSection }
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.background(theme: previewTheme ?? settings.themeSelection)
            .ignoresSafeArea())
    }

    // MARK: - Durum kartı

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("ENERJİ")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DivePalette.color(for: .secondary, theme: .standard))
                Spacer()
                Text(energy.state.thermalState.title)
                    .font(.system(size: 11))
                    .foregroundStyle(thermalColor)
            }
            Text(batteryText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(energy.summaryText)
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.color(for: .secondary, theme: .standard))
        }
        .padding(.vertical, 2)
    }

    private var batteryText: String {
        energy.state.isBatteryUnknown
            ? "Pil —"
            : "Pil %\(energy.state.batteryPercent)"
    }

    private var thermalColor: DiveColorRole {
        switch energy.state.thermalState {
        case .nominal: return .safe
        case .fair: return .caution
        case .serious, .critical: return .danger
        }
    }

    // MARK: - Profil

    private var profileSection: some View {
        section("Enerji Profili") {
            ForEach(PowerProfile.allCases) { profile in
                row(title: profile.title,
                    detail: profile.detail,
                    isSelected: settings.powerProfile == profile) {
                    settings.powerProfile = profile
                }
            }
        }
    }

    // MARK: - Gece modu

    private var nightModeSection: some View {
        section("Gece Modu (Kırmızı)") {
            ForEach(EnergyManager.NightModePreference.allCases, id: \.self) { preference in
                row(title: preference.title,
                    detail: nightDetail(preference),
                    isSelected: settings.nightModePreference == preference) {
                    settings.nightModePreference = preference
                }
            }
            themePreview
        }
    }

    private func nightDetail(_ preference: EnergyManager.NightModePreference) -> String {
        switch preference {
        case .auto:
            return "Pil %30 altında veya gece saatlerinde kırmızı mod"
        case .forced:
            return "Her zaman kırmızı; gece dalışında göz koruması"
        case .off:
            return "Tam renk; en yüksek pil tüketimi"
        }
    }

    private var themePreview: some View {
        HStack(spacing: 6) {
            ForEach(DiveDisplayTheme.allCases) { theme in
                Button {
                    previewTheme = theme
                } label: {
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DivePalette.background(theme: theme))
                            .frame(height: 22)
                            .overlay(
                                Text("24.6")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(DivePalette.color(for: .hero, theme: theme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(
                                        previewTheme == theme
                                            ? DivePalette.color(for: .accent, theme: .standard)
                                            : .clear,
                                        lineWidth: 2)
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - AOD

    private var alwaysOnSection: some View {
        section("Always-On Ekran") {
            row(title: "AOD'yi Aç",
                detail: "AOD açıkken pil ömrü belirgin şekilde kısalır",
                isSelected: settings.allowsAlwaysOnDisplay) {
                settings.allowsAlwaysOnDisplay.toggle()
            }
        }
    }

    // MARK: - Öneriler

    private var guidanceSection: some View {
        section("Öneriler") {
            ForEach(energy.guidance) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.message)
                        .font(.system(size: 12))
                        .foregroundStyle(DivePalette.color(for: role(for: item.kind),
                                                           theme: .standard))
                    if let action = item.action {
                        Text(action)
                            .font(.system(size: 10))
                            .foregroundStyle(DivePalette.color(for: .secondary, theme: .standard))
                    }
                }
            }
        }
    }

    private func role(for kind: EnergyManager.Guidance.Kind) -> DiveColorRole {
        switch kind {
        case .info: return .accent
        case .caution: return .caution
        case .critical: return .danger
        }
    }

    // MARK: - Yardımcılar

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: .secondary, theme: .standard))
            content()
        }
        .padding(.vertical, 4)
    }

    private func row(title: String, detail: String, isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DivePalette.color(for: isSelected ? .accent : .hero,
                                                           theme: .standard))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(DivePalette.color(for: .secondary, theme: .standard))
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DivePalette.color(for: .accent, theme: .standard))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private extension DiveSettings {
    /// Kullanıcı ayarından türetilen tema (AOD hariç).
    var themeSelection: DiveDisplayTheme {
        switch nightModePreference {
        case .forced: return .nightShift
        case .off: return .standard
        case .auto: return .standard
        }
    }
}
#endif
