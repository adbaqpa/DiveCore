#if os(iOS)
import SwiftUI
import Charts
import DiveCore

/// ADIM 10 — **interaktif derinlik-zaman grafiği**.
///
/// ## Etkileşim
/// - **Yatay sürükleme** → görünür zaman aralığını kaydırır,
/// - **Pinch / düğme** → yakınlaştırır (en az 60 saniyelik pencere),
/// - **Dokunma** → en yakın örneği seçer, araç ipucu gösterir,
/// - Grafik seçimi, `DiveChartModel` sayesinde harita ve özet kartıyla
///   aynı anda senkronlanır.
///
/// Tüm kararlar (hangi aralık görünür, hangi nokta seçili) test edilebilir
/// `DiveChartModel` içindedir; bu görünüm yalnızca uygular.
struct DiveChartView: View {

    @State private var model: DiveChartModel
    @State private var samples: [DiveSample]
    @Binding var selectedElapsed: TimeInterval?
    var showsCeiling: Bool = true
    var onSelectElapsed: ((TimeInterval) -> Void)?

    init(log: LogEntry,
         selectedElapsed: Binding<TimeInterval?>,
         showsCeiling: Bool = true,
         onSelectElapsed: ((TimeInterval) -> Void)? = nil) {
        _model = State(initialValue: DiveChartModel(metric: .depth,
                                                     samples: log.samples,
                                                     totalDuration: log.totalDiveTime))
        _samples = State(initialValue: log.samples)
        _selectedElapsed = selectedElapsed
        self.showsCeiling = showsCeiling
        self.onSelectElapsed = onSelectElapsed
    }

    var body: some View {
        VStack(spacing: 8) {
            metricPicker
            chart
            controls
        }
        .onChange(of: selectedElapsed) { _, newValue in
            guard let newValue else { return }
            model.moveCursor(to: newValue)
        }
    }

    // MARK: - Metrik seçimi

    private var metricPicker: some View {
        Picker("Metrik", selection: Binding(
            get: { model.metric },
            set: { newValue in
                model = DiveChartModel(metric: newValue, samples: samples,
                                       totalDuration: model.totalDuration)
            })) {
            ForEach(DiveChartModel.Metric.allCases) { metric in
                Text(metric.title).tag(metric)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Grafik

    private var chart: some View {
        Chart {
            ForEach(model.visiblePoints) { point in
                AreaMark(
                    x: .value("Süre", point.x),
                    yStart: .value("Taban", 0),
                    yEnd: .value(model.metric.title, point.y)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.cyan.opacity(0.55), .cyan.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value("Süre", point.x),
                    y: .value(model.metric.title, point.y)
                )
                .foregroundStyle(.cyan)
                .interpolationMethod(.monotone)
            }

            if showsCeiling, model.metric == .depth {
                ForEach(model.visibleCeilingPoints) { point in
                    LineMark(x: .value("Süre", point.x), y: .value("Tavan", point.y))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }

            if let selection = model.selection {
                RuleMark(x: .value("Seçili", selection.x))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                PointMark(
                    x: .value("Süre", selection.x),
                    y: .value(model.metric.title, selection.y)
                )
                .foregroundStyle(.white)
                .symbolSize(60)
            }
        }
        .chartYScale(domain: yDomain, reversed: model.metric.isInverted)
        .chartXScale(domain: model.visibleRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let time = value.as(Double.self) {
                        Text(DurationFormatter.clock(time))
                    }
                }
            }
        }
        .chartYAxisLabel(model.metric.unit)
        .frame(height: 220)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { drag in
                                let x = drag.location.x - geometry[proxy.plotFrame!].origin.x
                                if let time: Double = proxy.value(atX: x) {
                                    model.moveCursor(to: time)
                                    selectedElapsed = time
                                }
                            }
                            .onEnded { _ in model.clearCursor() }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                model.zoom(by: Double(scale))
                            }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in
                            if let selection = model.selection {
                                selectedElapsed = selection.x
                                onSelectElapsed?(selection.x)
                            }
                        }
                    )
            }
        }
    }

    /// Y ekseni aralığı (görünür pencereye göre).
    private var yDomain: ClosedRange<Double> {
        guard let extent = model.visibleExtent, extent.upperBound > extent.lowerBound else {
            return 0...1
        }
        let margin = max(0.5, (extent.upperBound - extent.lowerBound) * 0.1)
        return (extent.lowerBound - margin)...(extent.upperBound + margin)
    }

    // MARK: - Kontroller

    private var controls: some View {
        HStack {
            Button { model.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Button { model.resetZoom() } label: {
                Text(DurationFormatter.clock(model.visibleRange.upperBound - model.visibleRange.lowerBound))
                    .font(.caption.monospacedDigit())
            }
            Button { model.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            Spacer()
            if let text = model.selectionText {
                Text(text)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
    }
}
#endif
