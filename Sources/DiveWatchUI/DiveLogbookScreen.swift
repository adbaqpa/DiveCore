#if os(watchOS)
import SwiftUI
import DiveCore
import DiveCharts

/// Dalış günlüğü (defter) ekranı — ADIM 5.
///
/// Veriler `LogbookDisplay` üzerinden gelir; ekran yalnızca listeler.
struct DiveLogbookScreen: View {
    let display: LogbookDisplay
    @State private var selection: LogbookDisplay.Row?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                statistics
                if let today = display.today {
                    DailyTotalsChartView(totals: today)
                }
                Divider().opacity(0.3)
                rows
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.surfaceBackground.ignoresSafeArea())
    }

    // MARK: - Bölümler

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(display.statisticsLines, id: \.self) { line in
                Text(line)
                    .font(DiveTypography.font(for: .small))
                    .foregroundStyle(DivePalette.color(for: .secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack {
                Image(systemName: display.syncLabel == "Senkronize"
                      ? "checkmark.icloud.fill" : "iphone.and.arrow.forward")
                    .font(.system(size: 9))
                Text(display.syncLabel)
                    .font(DiveTypography.font(for: .micro))
                Spacer()
            }
            .foregroundStyle(DivePalette.color(for: .accent))
        }
    }

    @ViewBuilder
    private var rows: some View {
        if display.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(DivePalette.color(for: .secondary))
                Text("Henüz dalış yok")
                    .font(DiveTypography.font(for: .medium))
                    .foregroundStyle(DivePalette.color(for: .secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            ForEach(display.rows) { row in
                HStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DivePalette.color(for: row.hasDeco ? .deco : .accent)
                                .opacity(0.25))
                        GeometryReader { geometry in
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(DivePalette.color(for: row.hasDeco ? .deco : .accent))
                                    .frame(height: geometry.size.height * row.depthFraction)
                            }
                        }
                    }
                    .frame(width: 8, height: 26)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.title)
                            .font(DiveTypography.font(for: .medium))
                            .foregroundStyle(DivePalette.color(for: .hero))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(row.subtitle)
                            .font(DiveTypography.font(for: .micro))
                            .foregroundStyle(DivePalette.color(for: .secondary))
                    }
                    Spacer(minLength: 0)
                    Text(row.gradeText)
                        .font(.system(size: 11))
                        .foregroundStyle(DivePalette.color(for: gradeColor(row.gradeText)))
                }
            }
        }
    }

    private func gradeColor(_ grade: String) -> DiveColorRole {
        let filled = grade.filter { $0 == "★" }.count
        switch filled {
        case 5: return .safe
        case 3...4: return .caution
        default: return .danger
        }
    }
}
#endif