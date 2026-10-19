#if os(watchOS)
import SwiftUI
import DiveCore

// MARK: - Komplikasyon görünümleri

/// `accessoryCircular` — saat yüzü dairesel komplikasyonu.
///
/// Yalnızca `DiveComplicationData` okur; metin/karar mantığı çekirdektedir.
struct DiveCircularComplication: View {
    let data: DiveComplicationData

    var body: some View {
        Gauge(value: min(1, max(0, data.gauge))) {
            Image(systemName: "water.waves")
        } currentValueLabel: {
            Text(data.primaryText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(DivePalette.color(for: data.accentRole))
        .widgetAccentable()
    }
}

/// `accessoryRectangular` — dikdörtgen komplikasyon.
struct DiveRectangularComplication: View {
    let data: DiveComplicationData

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(data.primaryText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: data.accentRole == .danger
                      ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.33percent")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DivePalette.color(for: data.accentRole))
            }
            Text(data.secondaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            Text(data.tertiaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .widgetAccentable()
    }
}

/// `accessoryInline` — tek satır.
struct DiveInlineComplication: View {
    let data: DiveComplicationData

    var body: some View {
        Label {
            Text(data.primaryText).monospacedDigit()
        } icon: {
            Image(systemName: data.accentRole == .danger
                  ? "exclamationmark.triangle.fill" : "water.waves")
        }
        .widgetAccentable()
    }
}

/// `accessoryCorner` — köşe komplikasyonu (gauge).
struct DiveCornerComplication: View {
    let data: DiveComplicationData

    var body: some View {
        Gauge(value: min(1, max(0, data.gauge))) {
            Image(systemName: "arrow.down")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(DivePalette.color(for: data.accentRole))
        .widgetAccentable()
    }
}

/// Komplikasyon verisini doğru görünümle eşleştiren kurucu.
@ViewBuilder
struct DiveComplicationView: View {
    let data: DiveComplicationData

    var body: some View {
        switch data.style {
        case .inline:      DiveInlineComplication(data: data)
        case .circular:    DiveCircularComplication(data: data)
        case .rectangular: DiveRectangularComplication(data: data)
        case .corner:      DiveCornerComplication(data: data)
        }
    }
}
#endif