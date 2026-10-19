#if os(iOS)
import SwiftUI
import DiveCore

/// ADIM 10 — **dışa aktarma ekranı**.
///
/// UDDF, FIT ve JSON biçimlerini üretir, veri denetimini gösterir ve
/// dosya paylaşımını başlatır.
///
/// ## Neden üç biçim?
/// - **UDDF** → açık standart, Subsurface/Divelog uyumlu,
/// - **FIT** → Garmin dünyasının standardı, çok küçük dosya,
/// - **JSON** → kendi arşivimiz ve yeniden içe aktarma için.
struct DiveExportScreen: View {

    let log: LogEntry

    @State private var issues: [DiveExportService.Issue] = []
    @State private var exports: [DiveExportService.Export] = []
    @State private var shareItem: DiveExportService.Export?

    private var service = DiveExportService()

    var body: some View {
        List {
            if !issues.isEmpty { validationSection }
            formatSection
            aboutSection
        }
        .navigationTitle("Dışa Aktar")
        .task { prepare() }
    }

    // MARK: - Denetim

    private var validationSection: some View {
        Section("Veri Denetimi") {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: issue.severity))
                        .foregroundStyle(color(for: issue.severity))
                    VStack(alignment: .leading) {
                        Text(issue.message)
                            .font(.subheadline)
                        Text(issue.severity.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Biçimler

    private var formatSection: some View {
        Section("Biçim") {
            ForEach(exports) { export in
                Button {
                    shareItem = export
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(export.format.title)
                                .font(.headline)
                            Text(export.fileName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(export.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.tint)
                    }
                }
                .disabled(export.data.isEmpty)
            }
        }
    }

    private var aboutSection: some View {
        Section("Bilgi") {
            ForEach(notes(for: exports.first?.format), id: \.self) { note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func notes(for format: DiveExportService.Export.Format?) -> [String] {
        switch format {
        case .uddf:
            return ["UDDF 3.3.0 açık standarttır; Subsurface ve Divelog tarafından okunabilir.",
                    "GPS noktaları yalnızca yüzeyde kaydedildiği için rotanın o bölümü eksik olabilir."]
        case .fit:
            return ["FIT ikili formattır ve UDDF'den çok daha küçüktür.",
                    "Garmin Connect, Strava ve Suunto uygulamalarıyla uyumludur."]
        case .json:
            return ["JSON, uygulamanın kendi arşiv biçimidir; tüm alanları korur.",
                    "Yeniden içe aktarma için kullanılır."]
        case nil:
            return ["Veri hazırlanıyor…"]
        }
    }

    // MARK: - Hazırlık

    private func prepare() {
        issues = service.validate(log)
        guard service.canExport(log) else {
            exports = []
            return
        }
        exports = service.exportAll(log)
    }

    private func icon(for severity: DiveExportService.Issue.Severity) -> String {
        switch severity {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(for severity: DiveExportService.Issue.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

// MARK: - Paylaşım

extension DiveExportService.Export: Identifiable {}

struct DiveShareSheet: UIViewControllerRepresentable {
    let export: DiveExportService.Export

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [export.data], applicationActivities: nil)
        controller.title = export.fileName
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
