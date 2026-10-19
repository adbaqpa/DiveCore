import Foundation

/// ADIM 10 — **FIT** (Flexible and Interoperable Data Transfer) dışa aktarımı.
///
/// ## Neden FIT?
/// Garmin dünyasının fiili standardıdır; Strava, TrainingPeaks ve onlarca
/// dalış uygulaması okur. UDDF'nin XML olmasına karşılık ikili (binary)
/// bir formattır ve çok daha küçüktür (tipik dalış: 30 KB).
///
/// ## Format özeti
/// ```
/// ┌────────────┬──────────────────────────────────────┬─────────┐
/// │ 12 bayt    │ veri kayıtları (mesajlar)            │ 2 bayt  │
/// │ başlık     │                                      │ CRC     │
/// └────────────┴──────────────────────────────────────┴─────────┘
/// ```
/// - Başlık: 12 veya 14 bayt (normal/definition mesajı)
/// - Kayıt başlık baytı: bit 7 = mesaj başı, bit 6 = tanım mesajı,
///   bit 5 = geliştirici bit, bit 0...3 = yerel mesaj tipi
/// - Veri: tanım mesajında alan tanımları, normal mesajda değerler
///   (little-endian, FIT ölçek/ofset tabanlı sıkıştırma)
/// - CRC: FIT CRC-16 (0xA001 tabanlı), başlık + veriler üzerinden hesaplanır
///
/// ## En küçük geçerli dosya
/// `file_id` + `session` + birkaç `record` + `event`(timer) — bu dosya
/// Subsurface ve Garmin cihazlarında dalış olarak görünür.
public struct FITExporter: Sendable {

    // MARK: - Global mesaj numaraları

    enum MessageNumber {
        static let fileId: UInt8 = 0
        static let session: UInt8 = 18
        static let lap: UInt8 = 19
        static let record: UInt8 = 20
        static let event: UInt8 = 21
    }

    // MARK: - FIT tarihi (FIT epoch: 1989-12-31 00:00:00 UTC)

    /// FIT epoch — Unix zamanından 631065600 saniye geride.
    public static let fitEpochOffset: TimeInterval = 631_065_600

    public static func fitTimestamp(_ date: Date) -> UInt32 {
        UInt32(max(0, date.timeIntervalSince1970 - fitEpochOffset))
    }

    public static func date(fromFitTimestamp timestamp: UInt32) -> Date {
        Date(timeIntervalSince1970: Double(timestamp) + fitEpochOffset)
    }

    // MARK: - Alan tanımı

    /// Bir alanın FIT profili (numara, boyut, taban türü, ölçek/ofset).
    struct FieldDefinition {
        let number: UInt8
        let size: UInt8
        let baseType: UInt8
        let scale: UInt8?
        let offset: Int8?

        /// `field_definitions` mesajındaki gösterim.
        var definitionBytes: [UInt8] {
            var bytes: [UInt8] = [number, size, baseType]
            if let scale { bytes.append(scale) }
            if let offset {
                bytes.append(0x80)                       // developer bit
                bytes.append(UInt8(bitPattern: offset))  // offset
            }
            return bytes
        }
    }

    // MARK: - Base tipler

    enum BaseType {
        static let enumType: UInt8 = 0x00
        static let sint8: UInt8 = 0x01
        static let uint8: UInt8 = 0x02
        static let sint16: UInt8 = 0x83
        static let uint16: UInt8 = 0x84
        static let sint32: UInt8 = 0x85
        static let uint32: UInt8 = 0x86
        static let string: UInt8 = 0x07
    }

    // MARK: - CRC

    /// FIT CRC-16 algoritması (CRC-16/ARC varyantı, 0xA001 polinomu).
    ///
    /// - Note: FIT'in belirli bir CRC'si vardır: `tmp = crc ^ byte`, ardından
    ///   8 kez sağa kaydırma ve en düşük bit set ise `0xA001` ile XOR.
    public static func crc(_ bytes: [UInt8], initial: UInt16 = 0) -> UInt16 {
        var crc = initial
        for byte in bytes {
            var tmp = crc ^ UInt16(byte)
            for _ in 0..<8 {
                tmp = (tmp & 1) == 1 ? (tmp >> 1) ^ 0xA001 : (tmp >> 1)
            }
            crc = tmp
        }
        return crc
    }

    // MARK: - Dışa aktarma seçenekleri

    public struct Options: Sendable {
        /// Üretici (Garmin Connect için "developer" alanı)
        public var manufacturer: UInt16
        /// Ürün kodu
        public var product: UInt16
        /// Seri numara
        public var serialNumber: UInt32
        /// Zaman damgası (FIT epoch)
        public var timeCreated: UInt32
        /// Örnek bütçesi (0 = tümü)
        public var sampleBudget: Int

        public init(manufacturer: UInt16 = 255,
                    product: UInt16 = 1,
                    serialNumber: UInt32 = 1,
                    timeCreated: UInt32? = nil,
                    sampleBudget: Int = 0) {
            self.manufacturer = manufacturer
            self.product = product
            self.serialNumber = serialNumber
            self.timeCreated = timeCreated ?? FITExporter.fitTimestamp(Date())
            self.sampleBudget = sampleBudget
        }

        public static let `default` = Options()
    }

    public let options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    // MARK: - Dışa aktarma

    /// `LogEntry` → FIT dosya verisi.
    public func data(_ log: LogEntry) -> Data {
        var records: [UInt8] = []
        records.reserveCapacity(1024)

        // file_id — "well-known" mesajdır: tanım mesajı **gönderilmez**,
        // alanlar profilde sabittir (type, manufacturer, product, serial, time).
        records += dataMessage(localType: 0, values: [
            .uint16(4),   // type: 4 = dive
            .uint16(options.manufacturer),
            .uint16(options.product),
            .uint32(options.serialNumber),
            .uint32(FITExporter.fitTimestamp(log.startDate))
        ])

        // event: timer start
        records += definitionMessage(localType: 1, globalType: MessageNumber.event, fields: [
            FieldDefinition(number: 253, size: 4, baseType: BaseType.uint32, scale: nil, offset: nil),
            FieldDefinition(number: 0, size: 1, baseType: BaseType.enumType, scale: nil, offset: nil)
        ])
        records += dataMessage(localType: 1, values: [
            .uint32(FITExporter.fitTimestamp(log.startDate)),
            .uint8(0)   // timer
        ])

        // record mesajları
        let samples = decimated(log.samples)
        if !samples.isEmpty {
            records += definitionMessage(localType: 2, globalType: MessageNumber.record, fields: [
                FieldDefinition(number: 253, size: 4, baseType: BaseType.uint32, scale: nil, offset: nil),
                FieldDefinition(number: 0, size: 4, baseType: BaseType.sint32, scale: 2, offset: nil),   // ölçek 1/100 m
                FieldDefinition(number: 1, size: 2, baseType: BaseType.uint16, scale: 1, offset: nil),    // ölçek 1/10 °C
                FieldDefinition(number: 3, size: 1, baseType: BaseType.uint8, scale: nil, offset: nil),
                FieldDefinition(number: 4, size: 1, baseType: BaseType.uint8, scale: nil, offset: nil)
            ])
            for sample in samples {
                let timestamp = FITExporter.fitTimestamp(
                    log.startDate.addingTimeInterval(sample.elapsed))
                let depth = Int32((sample.depth * 100).rounded())        // ölçek 1/100 m → cm
                let temperature = Int16((sample.temperature * 10).rounded())  // ölçek 1/10 °C
                let gf = UInt8(min(254, max(0, Int(sample.gf99.rounded()))))
                let ceiling = UInt8(min(254, max(0, Int((sample.ceiling * 10).rounded()))))
                records += dataMessage(localType: 2, values: [
                    .uint32(timestamp), .sint32(depth), .uint16(UInt16(bitPattern: temperature)),
                    .uint8(gf), .uint8(ceiling)
                ])
            }
        }

        // lap
        records += definitionMessage(localType: 3, globalType: MessageNumber.lap, fields: [
            FieldDefinition(number: 254, size: 2, baseType: BaseType.uint16, scale: nil, offset: nil),
            FieldDefinition(number: 253, size: 4, baseType: BaseType.uint32, scale: nil, offset: nil),
            FieldDefinition(number: 2, size: 4, baseType: BaseType.uint32, scale: 3, offset: nil),  // ms
            FieldDefinition(number: 7, size: 4, baseType: BaseType.uint32, scale: 3, offset: nil),  // ms
            FieldDefinition(number: 8, size: 2, baseType: BaseType.uint16, scale: 2, offset: nil)   // cm
        ])
        records += dataMessage(localType: 3, values: [
            .uint16(0),
            .uint32(FITExporter.fitTimestamp(log.startDate)),
            .uint32(UInt32(max(0, log.totalDiveTime * 1000))),
            .uint32(UInt32(max(0, log.totalDiveTime * 1000))),
            .uint16(UInt16(bitPattern: Int16((log.averageDepth * 100).rounded())))
        ])

        // session
        let endTimestamp = FITExporter.fitTimestamp(
            log.endDate ?? log.startDate.addingTimeInterval(log.totalDiveTime))
        records += definitionMessage(localType: 4, globalType: MessageNumber.session, fields: [
            FieldDefinition(number: 254, size: 2, baseType: BaseType.uint16, scale: nil, offset: nil),
            FieldDefinition(number: 253, size: 4, baseType: BaseType.uint32, scale: nil, offset: nil),
            FieldDefinition(number: 2, size: 4, baseType: BaseType.uint32, scale: 3, offset: nil),  // ms
            FieldDefinition(number: 7, size: 4, baseType: BaseType.uint32, scale: 3, offset: nil),  // ms
            FieldDefinition(number: 8, size: 2, baseType: BaseType.uint16, scale: 2, offset: nil),  // cm
            FieldDefinition(number: 26, size: 2, baseType: BaseType.uint16, scale: 2, offset: nil) // cm (max)
        ])
        records += dataMessage(localType: 4, values: [
            .uint16(0),
            .uint32(FITExporter.fitTimestamp(log.startDate)),
            .uint32(UInt32(max(0, log.totalDiveTime * 1000))),
            .uint32(UInt32(max(0, log.totalDiveTime * 1000))),
            .uint16(UInt16(bitPattern: Int16((log.averageDepth * 100).rounded()))),
            .uint16(UInt16(bitPattern: Int16((log.maxDepth * 100).rounded())))
        ])

        // event: timer stop
        records += dataMessage(localType: 1, values: [
            .uint32(endTimestamp), .uint8(1)   // stop_all
        ])

        return assemble(records: records)
    }

    // MARK: - Dosya çerçevesi

    /// Başlık + veri + CRC.
    private func assemble(records: [UInt8]) -> Data {
        var header: [UInt8] = [
            12,                          // başlık boyutu
            0x20,                        // protokol sürümü 2.0
            0x00, 0x00,                  // profil sürümü (little-endian)
            0x00, 0x00, 0x00, 0x00       // veri boyutu (little-endian, sonra yazılır)
        ]
        // ".FIT" imzası
        header += [0x2E, 0x46, 0x49, 0x54]
        // Başlık CRC'si (ilk 12 bayt)
        let headerCRC = FITExporter.crc(Array(header[0..<12]))
        header.append(UInt8(truncatingIfNeeded: headerCRC & 0xFF))
        header.append(UInt8(truncatingIfNeeded: (headerCRC >> 8) & 0xFF))

        // FIT veri boyutu, dosya CRC'sini **içerir** (başlık hariç)
        let size = UInt32(records.count + 2)
        header[4] = UInt8(size & 0xFF)
        header[5] = UInt8((size >> 8) & 0xFF)
        header[6] = UInt8((size >> 16) & 0xFF)
        header[7] = UInt8((size >> 24) & 0xFF)
        // Başlık CRC'si veri boyutu değiştiği için yeniden hesaplanır
        let finalHeaderCRC = FITExporter.crc(Array(header[0..<12]))
        header[12] = UInt8(truncatingIfNeeded: finalHeaderCRC & 0xFF)
        header[13] = UInt8(truncatingIfNeeded: (finalHeaderCRC >> 8) & 0xFF)

        var all = header + records
        let fileCRC = FITExporter.crc(all)
        all.append(UInt8(truncatingIfNeeded: fileCRC & 0xFF))
        all.append(UInt8(truncatingIfNeeded: (fileCRC >> 8) & 0xFF))
        return Data(all)
    }

    // MARK: - Mesaj kurucular

    /// `definition_message` — alanları tanımlar.
    func definitionMessage(localType: UInt8, globalType: UInt8,
                           fields: [FieldDefinition]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(0x40 | (localType & 0x0F))        // definition bit + local tip
        bytes.append(0x00)                              // reserved
        bytes.append(globalType)
        bytes.append(UInt8(fields.count))
        for field in fields { bytes += field.definitionBytes }
        return bytes
    }

    /// `data_message` — tanımlı alanların değerleri.
    func dataMessage(localType: UInt8, values: [Value]) -> [UInt8] {
        var bytes: [UInt8] = [localType & 0x0F]
        for value in values { bytes += value.bytes }
        return bytes
    }

    // MARK: - Örnek indirgeme

    /// Bütçeye göre örnek indirger (min/max kova yöntemi).
    public func decimated(_ samples: [DiveSample]) -> [DiveSample] {
        guard options.sampleBudget > 0, samples.count > options.sampleBudget,
              samples.count >= 2 else { return samples }
        let bucketCount = max(1, (options.sampleBudget - 2) / 2)
        let bucketSize = Double(samples.count) / Double(bucketCount)
        var reduced: [DiveSample] = [samples[0]]
        for bucket in 0..<bucketCount {
            let start = Int(Double(bucket) * bucketSize)
            let end = min(samples.count, Int(Double(bucket + 1) * bucketSize))
            guard start < end else { continue }
            let slice = samples[start..<end]
            guard let deepest = slice.min(by: { $0.depth < $1.depth }),
                  let shallowest = slice.max(by: { $0.depth < $1.depth }) else { continue }
            if deepest.id != shallowest.id { reduced.append(deepest) }
            reduced.append(shallowest)
        }
        reduced.append(samples[samples.count - 1])
        return reduced.sorted { $0.elapsed < $1.elapsed }
    }

    // MARK: - Değer

    /// little-endian kodlanan alan değeri.
    enum Value {
        case uint8(UInt8)
        case uint16(UInt16)
        case uint32(UInt32)
        case sint32(Int32)

        var bytes: [UInt8] {
            switch self {
            case .uint8(let value):
                return [value]
            case .uint16(let value):
                return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
            case .uint32(let value):
                return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                        UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
            case .sint32(let value):
                let bits = UInt32(bitPattern: value)
                return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
                        UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)]
            }
        }
    }

    // MARK: - Dosya adı

    public func suggestedFileName(_ log: LogEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let stamp = formatter.string(from: log.startDate)
        let site = (log.location ?? "dalış")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(stamp)_\(site).fit"
    }
}
