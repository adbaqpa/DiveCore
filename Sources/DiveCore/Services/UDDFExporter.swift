import Foundation

/// ADIM 10 — **UDDF 3.3.0** dışa aktarımı (Universal Dive Data Format).
///
/// ## Neden UDDF?
/// UDDF, dalış bilgisayarı verilerinin **açık standart** değişimidir.
/// Subsurface, Divelog ve birçok eğitim/sertifika yazılımı okuyabilir; bu
/// sayede kullanıcı verisi platformdan bağımsız saklanır.
///
/// ## Yapı
/// ```xml
/// <uddf version="3.3.0">
///   <generator>
///   <profiledata>            ← gaz tanımları
///     <repetitiongroup>      ← örnek serisi (defansif programlarda)
///   <profiledata>
///   <waypoints>              ← GPS rotadaki ara noktalar
///   <samples>
///     <waypoint>             ← her örnek
///   </samples>
/// </uddf>
/// ```
///
/// ## XML kaçışı
/// Metin alanları (not, etiket, konum adı) `&`, `<`, `>` gibi karakterleri
/// içerebilir; tümü `escape(_:)` ile kaçırılır. Testler bu kaçışı doğrular.
public struct UDDFExporter: Sendable {

    /// Dışa aktarım seçenekleri.
    public struct Options: Sendable {
        /// Üretici adı (Creator)
        public var creatorName: String
        /// Üretici sürümü
        public var creatorVersion: String
        /// Örnek başına en fazla nokta (0 = sınırsız)
        public var sampleBudget: Int
        /// Noktalar arası en küçük mesafe (m) — GPS gürültüsünü azaltır
        public var gpsSpacing: Double
        /// Örnek aralığı (saniye) — 0 = ham veri
        public var sampleInterval: TimeInterval
        /// Tarih biçimi
        public var dateFormat: String

        public init(creatorName: String = "DiveLog Apple Watch",
                    creatorVersion: String = "1.0",
                    sampleBudget: Int = 0,
                    gpsSpacing: Double = 5,
                    sampleInterval: TimeInterval = 0,
                    dateFormat: String = "yyyy-MM-dd'T'HH:mm:ss.SSSZ") {
            self.creatorName = creatorName
            self.creatorVersion = creatorVersion
            self.sampleBudget = sampleBudget
            self.gpsSpacing = gpsSpacing
            self.sampleInterval = sampleInterval
            self.dateFormat = dateFormat
        }

        public static let `default` = Options()
    }

    public let options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    // MARK: - Dışa aktarma

    /// `LogEntry` → UDDF XML metni.
    public func export(_ log: LogEntry) -> String {
        var xml = ""
        xml += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<uddf version=\"3.3.0\">\n"

        // Üretici
        xml += "\t<generator>\n"
        xml += "\t\t<name>\(escape(options.creatorName))</name>\n"
        xml += "\t\t<version>\(escape(options.creatorVersion))</version>\n"
        xml += "\t\t<type>3</type>\n"   // 3 = dive computer
        xml += "\t</generator>\n"

        // Gaz profilleri
        xml += "\t<profiledata>\n"
        for (index, gas) in log.gases.enumerated() {
            xml += gasProfileXML(gas: gas, index: index, isStart: index == log.startGasIndex)
        }
        xml += "\t</profiledata>\n"

        // Örnekler
        xml += "\t<samples>\n"
        for sample in decimated(log.samples) {
            xml += waypointXML(sample: sample,
                               startDate: log.startDate,
                               gases: log.gases)
        }
        xml += "\t</samples>\n"

        // Dalış özeti (waypoint'ler yerine profil verisi olarak)
        xml += "\t<profiledata>\n"
        xml += diveProfileXML(log: log)
        xml += "\t</profiledata>\n"

        // GPS ara noktaları
        let route = DiveRoute(samples: log.samples, startDate: log.startDate,
                              minimumSpacing: options.gpsSpacing)
        if !route.isEmpty {
            xml += "\t<waypoints>\n"
            for point in route.points where abs(point.coordinate.latitude) > 0
                || abs(point.coordinate.longitude) > 0 {
                xml += "\t\t<waypoint>\n"
                xml += "\t\t\t<name>GPS \(Int(point.elapsed / 60))dk</name>\n"
                xml += "\t\t\t<depth>\(number(point.depth))</depth>\n"
                xml += "\t\t\t<divetime>\(number(point.elapsed))</divetime>\n"
                xml += "\t\t\t<place>\(escape(log.location ?? ""))</place>\n"
                xml += "\t\t\t<gps>\n"
                xml += "\t\t\t\t<latitude>\(number(point.coordinate.latitude, digits: 6))</latitude>\n"
                xml += "\t\t\t\t<longitude>\(number(point.coordinate.longitude, digits: 6))</longitude>\n"
                xml += "\t\t\t</gps>\n"
                xml += "\t\t</waypoint>\n"
            }
            xml += "\t</waypoints>\n"
        }

        xml += "</uddf>\n"
        return xml
    }

    /// `LogEntry` → UDDF veri (UTF-8).
    public func data(_ log: LogEntry) -> Data {
        Data(export(log).utf8)
    }

    /// Dosya adı önerisi.
    public func suggestedFileName(_ log: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let stamp = formatter.string(from: log.startDate)
        let site = (log.location ?? "dalış")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(stamp)_\(site).uddf"
    }

    // MARK: - Bölümler

    private func gasProfileXML(gas: GasMix, index: Int, isStart: Bool) -> String {
        var xml = "\t\t<gasp>\n"
        xml += "\t\t\t<name>\(escape(gas.label))</name>\n"
        xml += "\t\t\t<o2>\(number(gas.oxygenFraction, digits: 3))</o2>\n"
        xml += "\t\t\t<n2>\(number(gas.nitrogenFraction, digits: 3))</n2>\n"
        xml += "\t\t\t<he>\(number(gas.heliumFraction, digits: 3))</he>\n"
        if isStart { xml += "\t\t\t<switchdepth>0</switchdepth>\n" }
        xml += "\t\t</gasp>\n"
        _ = index
        return xml
    }

    private func waypointXML(sample: DiveSample, startDate: Date, gases: [GasMix]) -> String {
        var xml = "\t\t<waypoint>\n"
        xml += "\t\t\t<depth>\(number(sample.depth, digits: 2))</depth>\n"
        xml += "\t\t\t<divetime>\(number(sample.elapsed, digits: 1))</divetime>\n"

        if sample.temperature > -5 {
            xml += "\t\t\t<waterTemp>\(number(sample.temperature, digits: 1))</waterTemp>\n"
        }
        if let lat = sample.latitude, let lon = sample.longitude,
           abs(lat) > 0 || abs(lon) > 0 {
            xml += "\t\t\t<gps>\n"
            xml += "\t\t\t\t<latitude>\(number(lat, digits: 6))</latitude>\n"
            xml += "\t\t\t\t<longitude>\(number(lon, digits: 6))</longitude>\n"
            xml += "\t\t\t</gps>\n"
        }
        if sample.ceiling > 0 {
            xml += "\t\t\t<switchdepth>\(number(sample.ceiling, digits: 1))</switchdepth>\n"
        }
        if sample.gasIndex >= 0 && sample.gasIndex < gases.count {
            xml += "\t\t\t<gasiset ref=\"\(sample.gasIndex)\" switchreference=\"switchdepth\"/>\n"
        }
        xml += "\t\t</waypoint>\n"
        _ = startDate
        return xml
    }

    private func diveProfileXML(log: LogEntry) -> String {
        var xml = ""
        xml += "\t\t<informationbeforedive>\n"
        xml += "\t\t\t<divenumber>\(1)</divenumber>\n"
        xml += "\t\t</informationbeforedive>\n"

        xml += "\t\t<applicationdata>\n"
        xml += "\t\t\t<start>\(escape(dateString(log.startDate)))</start>\n"
        xml += "\t\t\t<end>\(escape(dateString(log.endDate ?? log.startDate.addingTimeInterval(log.totalDiveTime))))</end>\n"
        xml += "\t\t\t<maxdepth>\(number(log.maxDepth, digits: 2))</maxdepth>\n"
        xml += "\t\t\t<avgdepth>\(number(log.averageDepth, digits: 2))</avgdepth>\n"
        xml += "\t\t\t<runtime>\(number(log.totalDiveTime, digits: 0))</runtime>\n"
        xml += "\t\t\t<temp_begin>\(number(log.waterTemperatureStart, digits: 1))</temp_begin>\n"
        xml += "\t\t\t<temp_end>\(number(log.waterTemperatureEnd, digits: 1))</temp_end>\n"
        xml += "\t\t\t<temp_min>\(number(log.waterTemperatureMin, digits: 1))</temp_min>\n"
        xml += "\t\t\t<temp_max>\(number(log.waterTemperatureMax, digits: 1))</temp_max>\n"
        xml += "\t\t\t<surfaceinterval>\(number(log.recommendedSurfaceInterval, digits: 0))</surfaceinterval>\n"
        xml += "\t\t\t<B>\(number(log.totalDiveTime, digits: 0))</B>\n"
        xml += "\t\t\t<location>\(escape(log.location ?? ""))</location>\n"
        if !log.notes.isEmpty {
            xml += "\t\t\t<notes>\(escape(log.notes))</notes>\n"
        }
        if log.safetyStopCompleted {
            xml += "\t\t\t<safetystop>1</safetystop>\n"
        }
        if log.hadDecoObligation {
            xml += "\t\t\t<deco>\(number(log.safetyStopAccumulated, digits: 0))</deco>\n"
        }
        xml += "\t\t\t<cnspercent>\(number(log.cnsPercent, digits: 1))</cnspercent>\n"
        xml += "\t\t\t<otu>\(number(log.otuUnits, digits: 2))</otu>\n"
        xml += "\t\t\t<gflow>\(number(Double(log.gradientFactors.low), digits: 0))</gflow>\n"
        xml += "\t\t\t<gfhigh>\(number(Double(log.gradientFactors.high), digits: 0))</gfhigh>\n"
        xml += "\t\t\t<maxpo2>\(number(log.maxPO2, digits: 2))</maxpo2>\n"
        xml += "\t\t\t<rating>\(log.rating)</rating>\n"
        xml += "\t\t\t<serial>\(escape(log.computerSerial ?? ""))</serial>\n"
        xml += "\t\t</applicationdata>\n"
        return xml
    }

    // MARK: - Örnekleme

    /// Örnekleri indirger: bütçe + aralık.
    ///
    /// - Note: Bütçe verilmişse **min/max** (kova) yöntemi uygulanır; her
    ///   kovada en derin ve en sığ örnek korunur, böylece dalış profili
    ///   (tavan/dip) korunur.
    public func decimated(_ samples: [DiveSample]) -> [DiveSample] {
        guard !samples.isEmpty else { return [] }

        var result: [DiveSample]
        if options.sampleInterval > 0 {
            var lastTime = -Double.infinity
            result = samples.filter { sample in
                guard sample.elapsed - lastTime >= options.sampleInterval else { return false }
                lastTime = sample.elapsed
                return true
            }
        } else {
            result = samples
        }

        guard options.sampleBudget > 0, result.count > options.sampleBudget else { return result }

        // Kova (min/max) indirgemesi
        let bucketCount = max(1, (options.sampleBudget - 2) / 2)
        let bucketSize = Double(result.count) / Double(bucketCount)
        var reduced: [DiveSample] = [result[0]]

        for bucket in 0..<bucketCount {
            let start = Int(Double(bucket) * bucketSize)
            let end = min(result.count, Int(Double(bucket + 1) * bucketSize))
            guard start < end else { continue }
            let slice = result[start..<end]
            guard let deepest = slice.min(by: { $0.depth < $1.depth }),
                  let shallowest = slice.max(by: { $0.depth < $1.depth }) else { continue }
            if shallowest.id != deepest.id { reduced.append(deepest) }
            reduced.append(shallowest)
        }
        reduced.append(result[result.count - 1])
        return reduced.sorted { $0.elapsed < $1.elapsed }
    }

    // MARK: - Biçimlendirme

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = options.dateFormat
        return formatter.string(from: date)
    }

    /// Nokta ondalık biçimi (yerel ayraç kullanmaz — XML her zaman `.` ister).
    func number(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value.replacingLocaleDecimalSeparator)
    }

    /// XML kaçışı.
    func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }
}

extension Double {
    /// Nokta ondalık ayıracına zorlar (Türkçe locale "1,23" üretir).
    var replacingLocaleDecimalSeparator: Double {
        // `String(format:)` zaten C locale kullanır; bu uzantı yalnızca
        // açıklık amaçlıdır ve değeri değiştirmez.
        self
    }
}
