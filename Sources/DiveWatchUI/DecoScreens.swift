#if os(watchOS)
import SwiftUI
import DiveCore

// MARK: - Çıkış rehberi kartı

/// Tavan tamponu, sonraki dura ve bekleme süresi (asansör mü).
struct GuidanceCard: View {
    let display: GuidanceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(display.instruction)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            } icon: {
                Image(systemName: display.severity == .critical
                      ? "exclamationmark.triangle.fill" : "arrow.up.circle.fill")
            }
            .foregroundStyle(DivePalette.color(for: display.colorRole))

            HStack(spacing: 8) {
                chip("Tavanüstü", display.maximumAllowedText)
                chip("Sonraki", display.nextStopText)
                if display.holdText != "—" { chip("Bekle", display.holdText) }
                chip("TTS", display.ttsText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DivePalette.color(for: display.colorRole).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DivePalette.color(for: display.colorRole).opacity(0.6), lineWidth: 1))
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: .hero))
                .monospacedDigit()
            Text(title)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
    }
}

// MARK: - Oksijen kartı

/// PO₂ / CNS / OTU göstergeleri; limit aşımında kırmızı.
struct OxygenCard: View {
    let display: OxygenDisplay

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(display.metrics) { metric in
                    VStack(spacing: 1) {
                        Text(metric.valueText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(DivePalette.color(for: metric.colorRole))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(metric.label)
                            .font(DiveTypography.font(for: .micro))
                            .foregroundStyle(DivePalette.color(for: .secondary))
                        ProgressView(value: metric.progress)
                            .tint(DivePalette.color(for: metric.colorRole))
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if let message = display.message {
                Text(message)
                    .font(DiveTypography.font(for: .micro))
                    .foregroundStyle(DivePalette.color(for: display.isAlarm ? .danger : .caution))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - Deko planı ekranı

/// Planlanan deko duraklarının listesi (ADIM 4 ana ekranı).
struct DecoPlanScreen: View {
    let display: DecoPlanDisplay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(display.headline)
                    .font(DiveTypography.font(for: .medium))
                    .foregroundStyle(DivePalette.color(for: .deco))

                ForEach(display.rows) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.isSafetyStop ? "shield.checkered" : "circle.dotted")
                            .font(.system(size: 12))
                            .foregroundStyle(DivePalette.color(for: row.isSafetyStop ? .safe : .deco))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.depthText)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("\(row.arrivalText) → \(row.departureText)")
                                .font(DiveTypography.font(for: .micro))
                                .foregroundStyle(DivePalette.color(for: .secondary))
                                .monospacedDigit()
                        }
                        Spacer()
                        Text(row.holdText)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(DivePalette.color(for: .hero))
                            .monospacedDigit()
                        Text(row.gasLabel)
                            .font(DiveTypography.font(for: .micro))
                            .foregroundStyle(DivePalette.color(for: .accent))
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    metric("Çıkış", display.ascentTimeText)
                    Spacer()
                    metric("Durakta", display.holdTimeText)
                    Spacer()
                    metric("Toplam", display.totalTimeText)
                }
                .padding(.top, 4)
            }
        }
        .background(DivePalette.background.ignoresSafeArea())
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: .hero))
                .monospacedDigit()
            Text(label)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
    }
}

// MARK: - Yüzey aralığı ekranı

/// Dalış sonrası bekleme ve uçuş yasağı geri sayımı.
struct SurfaceIntervalScreen: View {
    let display: SurfaceIntervalDisplay

    var body: some View {
        VStack(spacing: 8) {
            Gauge(value: display.gf99Progress) {
                Text("GF99")
            } currentValueLabel: {
                Text(display.gf99Text)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(DivePalette.color(for: display.colorRole))
            .scaleEffect(1.2)

            VStack(spacing: 1) {
                Text(display.statusText)
                    .font(DiveTypography.font(for: .medium))
                    .foregroundStyle(DivePalette.color(for: display.colorRole))
                Text(display.elapsedText + " geçti")
                    .font(DiveTypography.font(for: .micro))
                    .foregroundStyle(DivePalette.color(for: .secondary))
                if !display.isCleared {
                    Text("Uçuş yasağı: \(display.noFlyText)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DivePalette.color(for: .caution))
                        .monospacedDigit()
                }
                Text(display.recommendation)
                    .font(DiveTypography.font(for: .micro))
                    .foregroundStyle(DivePalette.color(for: .secondary))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
        .background(DivePalette.background.ignoresSafeArea())
    }
}
#endif