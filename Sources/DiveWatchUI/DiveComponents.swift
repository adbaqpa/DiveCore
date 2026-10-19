#if os(watchOS)
import SwiftUI
import DiveCore

// MARK: - Derinlik göstergesi

/// Dairesel derinlik halkası: dolgu = anlık derinlik, ince çizgi = azami derinlik.
struct DepthRingGauge: View {
    let indicator: DepthIndicator
    let colorRole: DiveColorRole
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(DivePalette.color(for: colorRole).opacity(0.20), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, indicator.fraction))
                .stroke(DivePalette.color(for: colorRole),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Azami derinlik işareti
            Circle()
                .trim(from: min(0.999, indicator.maxFraction),
                      to: min(1.0, indicator.maxFraction + 0.012))
                .stroke(DivePalette.color(for: .caution), lineWidth: lineWidth)
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.25), value: indicator.fraction)
    }
}

// MARK: - Çıkış hızı göstergesi

/// Çıkış hızı çubuğu: yön oku + renk + değer.
struct AscentRateGauge: View {
    let indicator: AscentRateIndicator
    let compact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: indicator.level.symbol)
                .font(.system(size: compact ? 11 : 14, weight: .bold))
                .foregroundStyle(DivePalette.color(for: indicator.level.colorRole))

            // Gösterge çubuğu (merkezden doldurma)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DivePalette.color(for: .secondary).opacity(0.25))
                GeometryReader { geometry in
                    Capsule()
                        .fill(DivePalette.color(for: indicator.level.colorRole))
                        .frame(width: geometry.size.width * indicator.fill)
                }
            }
            .frame(height: compact ? 4 : 6)

            Text(compact ? indicator.aodLabel : indicator.text)
                .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: indicator.level.colorRole))
                .monospacedDigit()
                .frame(width: compact ? 24 : 34, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.2), value: indicator.fill)
    }
}

// MARK: - Pusola

/// Üstte gösterilen ince pusola şeridi (başlık + derece).
struct CompassTape: View {
    let compass: CompassIndicator
    /// Görünür alan (derece)
    let visibleDegrees: Double

    private var ticks: [(label: String, offset: Double)] {
        guard let heading = compass.heading else { return [] }
        let points: [(String, Double)] = [("K", 0), ("KD", 45), ("D", 90), ("GD", 135),
                                         ("G", 180), ("GB", 225), ("B", 270), ("KB", 315)]
        var result: [(String, Double)] = []
        for (label, absolute) in points {
            for shift in [-360.0, 0.0, 360.0] {
                let delta = absolute + shift - heading
                let normalized = delta.truncatingRemainder(dividingBy: 360)
                if abs(normalized) <= visibleDegrees / 2 {
                    result.append((label, normalized / (visibleDegrees / 2)))
                }
            }
        }
        return result.sorted { abs($0.offset) < abs($1.offset) }
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(ticks, id: \.label) { tick in
                    Text(tick.label)
                        .font(.system(size: 9, weight: tick.label.count == 1 ? .bold : .medium,
                                      design: .rounded))
                        .foregroundStyle(DivePalette.color(for: tick.label.count == 1 ? .hero : .secondary))
                        .frame(maxWidth: .infinity)
                        .opacity(1 - abs(tick.offset) * 0.6)
                }
            }
            .frame(height: 12)
            .clipShape(Rectangle())

            // Merkez çizgi
            Capsule()
                .fill(DivePalette.color(for: .accent))
                .frame(width: 2, height: 4)

            Text("\(Int(compass.normalized))°")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
        .animation(.easeOut(duration: 0.2), value: compass.normalized)
    }
}

// MARK: - Deko / emniyet durağı şeridi

/// Emniyet durağı veya deko bilgisi şeridi.
struct StopStrip: View {
    let title: String
    let primary: String
    let secondary: String
    let colorRole: DiveColorRole
    var progress: Double?

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(DiveTypography.font(for: .small))
                    .foregroundStyle(DivePalette.color(for: colorRole))
                Spacer(minLength: 0)
                Text(primary)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DivePalette.color(for: colorRole))
                    .monospacedDigit()
            }
            if let progress {
                ProgressView(value: progress)
                    .tint(DivePalette.color(for: colorRole))
            }
            Text(secondary)
                .font(DiveTypography.font(for: .micro))
                .foregroundStyle(DivePalette.color(for: .secondary))
        }
    }
}

// MARK: - Alarm banner

/// Ekranda üstte görünen kritik uyarı şeridi.
struct AlarmBanner: View {
    let banner: DiveBanner

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: banner.severity == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text(banner.title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Text(banner.message)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DivePalette.color(for: banner.colorRole), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif