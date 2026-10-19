#if os(watchOS)
import SwiftUI
import DiveCore

/// Dalış sonu özeti — kesintiler, deko durakları, oksijen değerlendirmesi.
struct DiveReportScreen: View {
    let display: DiveReportDisplay
    var onDone: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                header

                if !display.penaltyRows.isEmpty {
                    penalties
                }

                statistics
                decoStops
                footer
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.surfaceBackground.ignoresSafeArea())
        .onTapGesture { onDone?() }
    }

    // MARK: - Bölümler

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(display.title)
                .font(DiveTypography.font(for: .large))
                .foregroundStyle(DivePalette.color(for: .hero))
            HStack(spacing: 6) {
                Text(display.gradeText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DivePalette.color(for: gradeColor))
                Text(display.headline)
                    .font(DiveTypography.font(for: .small))
                    .foregroundStyle(DivePalette.color(for: .secondary))
            }
        }
    }

    private var gradeColor: DiveColorRole {
        switch display.gradeStars {
        case 5: return .safe
        case 4, 3: return .caution
        default: return .danger
        }
    }

    private var penalties: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(display.penaltyRows) { row in
                HStack(spacing: 5) {
                    Image(systemName: row.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DivePalette.color(for: row.colorRole))
                    Text(row.reason)
                        .font(DiveTypography.font(for: .small))
                        .foregroundStyle(DivePalette.color(for: row.colorRole))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DivePalette.color(for: .caution).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private var statistics: some View {
        VStack(spacing: 2) {
            row("Azami derinlik", display.maxDepthText)
            row("Ortalama", display.averageDepthText)
            row("Toplam süre", display.totalTimeText)
            row("Dipte", display.bottomTimeText)
            row("Sıcaklık", display.temperatureText)
            row("Azami hızlar", display.maxRatesText)
            row("Gaz", display.gasText)
            row("PO₂ / GF99", "\(display.po2Text) · \(display.gf99Text)")
            row("CNS / OTU", "\(display.cnsText) · \(display.otuText)")
            row("Emniyet durağı", display.safetyStopText)
        }
        .padding(6)
        .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var decoStops: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Deko")
                    .font(DiveTypography.font(for: .small))
                    .foregroundStyle(DivePalette.color(for: .secondary))
                Spacer()
                Text(display.totalDecoText)
                    .font(DiveTypography.font(for: .medium))
                    .foregroundStyle(DivePalette.color(for: .deco))
                    .monospacedDigit()
            }
            ForEach(display.decoStopRows) { row in
                HStack {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 10))
                        .foregroundStyle(DivePalette.color(for: .deco))
                    Text(row.label)
                        .font(DiveTypography.font(for: .small))
                        .foregroundStyle(DivePalette.color(for: .hero))
                        .monospacedDigit()
                    Spacer()
                    Text(row.gasLabel)
                        .font(DiveTypography.font(for: .micro))
                        .foregroundStyle(DivePalette.color(for: .accent))
                }
            }
        }
        .padding(6)
        .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Image(systemName: "airplane")
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.color(for: .secondary))
            Text("Uçuş yasağı \(display.noFlyText)")
                .font(DiveTypography.font(for: .small))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DiveTypography.font(for: .small))
                .foregroundStyle(DivePalette.color(for: .secondary))
            Spacer()
            Text(value)
                .font(DiveTypography.font(for: .medium))
                .foregroundStyle(DivePalette.color(for: .hero))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
#endif