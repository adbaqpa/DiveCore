#if os(watchOS)
import SwiftUI
import DiveCore

// MARK: - Yüzey modu komplikasyon görünümleri

/// Dalış **dışındayken** gösterilen dairesel komplikasyon.
///
/// Uçuş yasağı modunda merkezde geri sayım, yüzey aralığı modunda GF99
/// görünür. Karar `DiveComplicationData` içinde çoktan verilmiştir.
struct DiveSurfaceCircularComplication: View {
    let data: DiveComplicationData

    var body: some View {
        Gauge(value: min(1, max(0, data.gauge))) {
            Image(systemName: data.isAlarmActive ? "airplane" : "drop.degreesign.down")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(data.primaryText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .monospacedDigit()
                if !data.secondaryText.isEmpty {
                    Text(data.secondaryText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(DivePalette.color(for: data.accentRole))
        .widgetAccentable()
    }
}

/// Dalış dışındayken gösterilen dikdörtgen komplikasyon.
struct DiveSurfaceRectangularComplication: View {
    let data: DiveComplicationData

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(data.primaryText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 0)
                if data.isAlarmActive {
                    Image(systemName: "airplane")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DivePalette.color(for: data.accentRole))
                }
            }
            Text(data.secondaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            Text(data.tertiaryText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .widgetAccentable()
    }
}

/// Dalış dışındayken gösterilen köşe komplikasyonu.
struct DiveSurfaceCornerComplication: View {
    let data: DiveComplicationData

    var body: some View {
        Gauge(value: min(1, max(0, data.gauge))) {
            Image(systemName: "drop.degreesign.down")
        } currentValueLabel: {
            Text(data.primaryText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCornerCapacity)
        .tint(DivePalette.color(for: data.accentRole))
        .widgetAccentable()
    }
}

/// Yüzey modlarında `accessoryInline` — tek satır.
struct DiveSurfaceInlineComplication: View {
    let data: DiveComplicationData

    var body: some View {
        Label {
            Text(data.primaryText).monospacedDigit()
        } icon: {
            Image(systemName: data.isAlarmActive
                  ? "airplane"
                  : (data.secondaryText.isEmpty ? "drop.degreesign.down" : "gauge.with.dots.needle.50percent"))
        }
        .widgetAccentable()
    }
}

// MARK: - Birleşik görünüm

/// Mod + stil → doğru komplikasyon görünümü.
///
/// Widget uzantısı tek bir görünüm döndürmek zorundadır; hangi görünümün
/// seçileceği burada, veri ise `DiveComplicationBuilder`'da karar verilir.
struct DiveComplicationView: View {
    let data: DiveComplicationData
    /// Görünüm dalış dışı modlara mı ait?
    let isSurfaceMode: Bool

    var body: some View {
        if isSurfaceMode {
            surfaceBody
        } else {
            DiveInlineComplication(data: data)
        }
    }

    @ViewBuilder
    private var surfaceBody: some View {
        switch data.style {
        case .circular:
            DiveSurfaceCircularComplication(data: data)
        case .rectangular:
            DiveSurfaceRectangularComplication(data: data)
        case .corner:
            DiveSurfaceCornerComplication(data: data)
        case .inline:
            DiveSurfaceInlineComplication(data: data)
        }
    }
}

// MARK: - Görünüm verisi sağlayıcı

/// Komplikasyon görünümünü besleyen ince sarmalayıcı.
///
/// `WidgetKit` uzantısı ile uygulama arasındaki tek bağlantı noktasıdır:
/// uygulama veriyi üretir, uzantı yalnızca bu görünümü barındırır.
struct DiveComplicationEntryView: View {
    let entry: DiveComplicationTimeline.Entry
    let mode: DiveComplicationMode

    var body: some View {
        DiveComplicationView(data: entry.data,
                             isSurfaceMode: mode.isSurface)
    }
}
#endif
