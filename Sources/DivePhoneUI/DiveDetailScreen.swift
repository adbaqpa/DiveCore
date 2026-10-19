#if os(iOS)
import SwiftUI
import DiveCore

/// ADIM 10 — dalış ayrıntısı ekranı: harita + grafik + dışa aktarma.
///
/// Üç bölüm sekme/segment olarak sunulur; verilerin tamamı `DiveCore`
/// tarafından üretilir.
struct DiveDetailScreen: View {

    let log: LogEntry
    let route: DiveRoute

    @State private var selectedElapsed: TimeInterval?
    @State private var tab: Tab = .chart

    enum Tab: String, CaseIterable, Identifiable {
        case chart = "Grafik"
        case map = "Harita"
        case export = "Dışa Aktar"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch tab {
            case .chart:
                DiveChartView(log: log, selectedElapsed: $selectedElapsed)
                    .padding(.horizontal)
            case .map:
                DiveRouteMapView(route: route, selectedElapsed: $selectedElapsed)
            case .export:
                DiveExportScreen(log: log)
            }
        }
        .navigationTitle(log.location ?? "Dalış")
    }

    /// Üstteki özet: seçili andaki derinlik ve gaz yükü.
    private var summaryBar: some View {
        HStack {
            summaryItem("Süre", DurationFormatter.clock(log.totalDiveTime))
            Divider()
            summaryItem("Maks.", String(format: "%.1f m", log.maxDepth))
            Divider()
            summaryItem("Ort.", String(format: "%.1f m", log.averageDepth))
            Divider()
            summaryItem("GF99", "%\(Int(log.maxGF99))")
        }
        .frame(height: 44)
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
