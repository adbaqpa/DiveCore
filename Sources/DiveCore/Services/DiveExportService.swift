import Foundation

/// ADIM 10 — dışa aktarma servisi.
///
/// UDDF ve FIT'i tek bir noktadan üretir, dosya adını önerir ve verinin
/// **gerçekten dışa aktarılmaya uygun** olup olmadığını denetler.
public struct DiveExportService: Sendable {

    /// Dışa aktarılan dosya.
    public struct Export: Equatable, Sendable, Identifiable {
        public enum Format: String, Equatable, Codable, Sendable, CaseIterable {
            case uddf = "UDDF"
            case fit = "FIT"
            case json = "JSON"

            public var title: String { rawValue }
            public var fileExtension: String {
                switch self {
                case .uddf: return "uddf"
                case .fit: return "fit"
                case .json: return "json"
                }
            }
        }

        public let id: String
        public let format: Format
        public let fileName: String
        public let data: Data
        public let byteCount: Int
        /// Örnek (waypoint/record) sayısı
        public let sampleCount: Int

        public init(format: Format, fileName: String, data: Data, sampleCount: Int) {
            self.id = format.rawValue
            self.format = format
            self.fileName = fileName
            self.data = data
            self.byteCount = data.count
            self.sampleCount = sampleCount
        }

        /// Kısa özet (paylaşım ekranı için).
        public var summary: String {
            "\(format.title) · \(sampleCount) örnek · \(byteCount / 1024) KB"
        }
    }

    /// Dışa aktarma uyarısı.
    public struct Issue: Equatable, Sendable, Identifiable {
        public enum Severity: String, Sendable { case info, warning, error }
        public let id: String
        public let severity: Severity
        public let message: String
    }

    public let uddf: UDDFExporter
    public let fit: FITExporter

    public init(uddf: UDDFExporter = UDDFExporter(),
                fit: FITExporter = FITExporter()) {
        self.uddf = uddf
        self.fit = fit
    }

    // MARK: - Üretim

    public func export(_ log: LogEntry, format: Export.Format) -> Export {
        switch format {
        case .uddf:
            let exporter = uddf
            return Export(format: .uddf,
                          fileName: exporter.suggestedFileName(log),
                          data: exporter.data(log),
                          sampleCount: exporter.decimated(log.samples).count)
        case .fit:
            return Export(format: .fit,
                          fileName: fit.suggestedFileName(log),
                          data: fit.data(log),
                          sampleCount: fit.decimated(log.samples).count)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = (try? encoder.encode(log)) ?? Data()
            return Export(format: .json,
                          fileName: suggestedJSONName(log),
                          data: data,
                          sampleCount: log.samples.count)
        }
    }

    /// Tüm biçimleri üretir.
    public func exportAll(_ log: LogEntry) -> [Export] {
        Export.Format.allCases.map { export(log, format: $0) }
    }

    private func suggestedJSONName(_ log: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let site = (log.location ?? "dalış")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(formatter.string(from: log.startDate))_\(site).json"
    }

    // MARK: - Denetim

    /// Dışa aktarım öncesi veri denetimi.
    ///
    /// - Note: Hatalar (ör. örnek yok) dışa aktarmayı engeller; uyarılar
    ///   yalnızca bilgilendirir.
    public func validate(_ log: LogEntry) -> [Issue] {
        var issues: [Issue] = []

        if log.samples.isEmpty {
            issues.append(Issue(id: "noSamples", severity: .error,
                                message: "Dalışta hiç örnek yok"))
        }
        if log.totalDiveTime <= 0 {
            issues.append(Issue(id: "noDuration", severity: .error,
                                message: "Dalış süresi sıfır"))
        }
        if log.gases.isEmpty {
            issues.append(Issue(id: "noGas", severity: .error,
                                message: "Gaz tanımı yok"))
        }
        if log.maxDepth <= 0 {
            issues.append(Issue(id: "noDepth", severity: .error,
                                message: "Maksimum derinlik sıfır"))
        }
        if log.samples.count > 5000 {
            issues.append(Issue(id: "manySamples", severity: .warning,
                                message: "5000'den fazla örnek; indirgeme önerilir"))
        }
        if log.samples.contains(where: { $0.latitude != nil || $0.longitude != nil }) == false {
            issues.append(Issue(id: "noGPS", severity: .info,
                                message: "GPS rotası yok (konum yalnızca yüzeyde kaydedilir)"))
        }
        if log.notes.isEmpty {
            issues.append(Issue(id: "noNotes", severity: .info,
                                message: "Dalış notu yok"))
        }
        if log.cnsPercent > 80 {
            issues.append(Issue(id: "highCNS", severity: .warning,
                                message: "CNS yükü yüksek (%\(Int(log.cnsPercent)))"))
        }
        return issues
    }

    /// Dışa aktarılabilir mi?
    public func canExport(_ log: LogEntry) -> Bool {
        !validate(log).contains { $0.severity == .error }
    }

    // MARK: - İçe aktarma (UDDF)

    /// UDDF metninden temel özet çıkarır.
    ///
    /// - Note: Tam bir UDDF ayrıştırıcısı değildir; içe aktarma iş akışının
    ///   ilk adımı olarak dosyanın okunabilirliğini doğrular ve başlık
    ///   bilgilerini döndürür.
    public func peekUDDF(_ xml: String) -> [String: String] {
        var result: [String: String] = [:]
        guard xml.contains("<uddf") else { return result }

        for key in ["version"] {
            if let value = value(of: key, in: xml, opening: "<uddf \(key)=") {
                result[key] = value
            }
        }
        for key in ["name", "version"] {
            if let value = firstTag(key, in: xml) { result["generator_\(key)"] = value }
        }
        for key in ["maxdepth", "avgdepth", "runtime", "location", "serial"] {
            if let value = firstTag(key, in: xml) { result[key] = value }
        }
        result["waypointCount"] = String(xml.components(separatedBy: "<waypoint>").count - 1)
        return result
    }

    private func value(of key: String, in xml: String, opening: String) -> String? {
        guard let range = xml.range(of: opening + "\"") else { return nil }
        let rest = xml[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end])
    }

    private func firstTag(_ tag: String, in xml: String) -> String? {
        let open = "<\(tag)>"
        guard let start = xml.range(of: open) else { return nil }
        let rest = xml[start.upperBound...]
        guard let end = rest.range(of: "</\(tag)>") else { return nil }
        let raw = String(rest[rest.startIndex..<end.lowerBound])
        // XML kaçışını geri al
        return raw
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
