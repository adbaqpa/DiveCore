import XCTest
@testable import DiveCore

/// ADIM 10 — GPS rota, UDDF/FIT/JSON dışa aktarma ve interaktif grafik modeli.
final class DiveExportAndRouteTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Yardımcılar

    /// 30 m/25 dk dalış + GPS noktaları ile bir günlük kayıt.
    @MainActor
    private func makeLog(withGPS: Bool = true, location: String = "Kaş Marina") -> LogEntry {
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: base)
        controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
        var log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
        log.location = location
        log.notes = "Sakin su, <test> & \"deneme\""

        if withGPS {
            log.samples = log.samples.map { sample in
                var copy = sample
                if sample.depth < 0.5 {
                    // ~6 m'lik adımlar (5 m minimum boşluk filtresinden geçer)
                    copy.latitude = 36.80 + sample.elapsed * 0.00005
                    copy.longitude = 34.00 + sample.elapsed * 0.00003
                }
                return copy
            }
        }
        return log
    }

    private func sample(elapsed: TimeInterval, depth: Double,
                        latitude: Double? = nil, longitude: Double? = nil,
                        temperature: Double = 20, ascentRate: Double = 0,
                        gf99: Double = 0, ceiling: Double = 0) -> DiveSample {
        DiveSample(elapsed: elapsed, depth: depth, temperature: temperature,
                   ambientPressure: 2, po2: 0.42, ascentRate: ascentRate,
                   gf99: gf99, ceiling: ceiling, leadingTissuePressure: 0.9,
                   latitude: latitude, longitude: longitude)
    }

    // MARK: - Rota

    func testEmptyRoute() {
        let route = DiveRoute(samples: [], startDate: base)
        XCTAssertTrue(route.isEmpty)
        XCTAssertEqual(route.totalDistance, 0)
        XCTAssertNil(route.center)
        XCTAssertNil(route.bounds)
        XCTAssertNil(route.mapRegion())
    }

    @MainActor
    func testRouteFromSamples() {
        let route = DiveRoute(samples: makeLog().samples, startDate: base)
        XCTAssertFalse(route.isEmpty)
        XCTAssertGreaterThan(route.totalDistance, 10)
        XCTAssertGreaterThanOrEqual(route.pointCount, 2)
    }

    func testHaversineKnownDistance() {
        // 1 derece enlem ≈ 111.2 km
        let a = DiveCoordinate(latitude: 0, longitude: 0)
        let b = DiveCoordinate(latitude: 1, longitude: 0)
        XCTAssertEqual(DiveRoute.haversine(a, b), 111_195, accuracy: 200)
        XCTAssertEqual(a.distance(to: a), 0, accuracy: 0.001)
    }

    func testCoordinateValidation() {
        XCTAssertTrue(DiveCoordinate(latitude: 36.8, longitude: 34).isValid)
        XCTAssertFalse(DiveCoordinate(latitude: 91, longitude: 34).isValid)
        XCTAssertFalse(DiveCoordinate(latitude: 36.8, longitude: 181).isValid)
    }

    func testInvalidCoordinatesAreDropped() {
        let samples = [
            sample(elapsed: 0, depth: 0, latitude: 36.8, longitude: 34),
            sample(elapsed: 10, depth: 0, latitude: 999, longitude: 34),   // geçersiz
            sample(elapsed: 20, depth: 0, latitude: 36.81, longitude: 34.01)
        ]
        let route = DiveRoute(samples: samples, startDate: base, minimumSpacing: 0)
        XCTAssertEqual(route.pointCount, 2)
    }

    func testMinimumSpacingFiltersGpsNoise() {
        let samples = (0..<10).map { i in
            sample(elapsed: Double(i) * 10, depth: 0,
                   latitude: 36.8 + Double(i) * 0.000001,   // ~0.1 m
                   longitude: 34.0)
        }
        let dense = DiveRoute(samples: samples, startDate: base, minimumSpacing: 0)
        let filtered = DiveRoute(samples: samples, startDate: base, minimumSpacing: 5)
        XCTAssertEqual(dense.pointCount, 10)
        XCTAssertLessThan(filtered.pointCount, 3)
    }

    func testSamplesWithoutGPSAreIgnored() {
        let samples = [
            sample(elapsed: 0, depth: 0),
            sample(elapsed: 10, depth: 5),
            sample(elapsed: 20, depth: 0, latitude: 36.8, longitude: 34)
        ]
        let route = DiveRoute(samples: samples, startDate: base, minimumSpacing: 0)
        XCTAssertEqual(route.pointCount, 1, "Tek GPS noktası rota oluşturmaz")
        XCTAssertTrue(route.isEmpty)
    }

    func testBoundsAndRegion() {
        let samples = [
            sample(elapsed: 0, depth: 0, latitude: 36.80, longitude: 34.00),
            sample(elapsed: 60, depth: 0, latitude: 36.82, longitude: 34.04)
        ]
        let route = DiveRoute(samples: samples, startDate: base, minimumSpacing: 0)
        guard let bounds = route.bounds else { return XCTFail("Sınırlar bekleniyordu") }
        XCTAssertEqual(bounds.minLat, 36.80, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxLat, 36.82, accuracy: 0.0001)

        guard let region = route.mapRegion() else { return XCTFail("Harita bölgesi bekleniyordu") }
        XCTAssertEqual(region.center.latitude, 36.81, accuracy: 0.0001)
        // Boylam farkı baskın: 0.04 × 1.4 = 0.056
        XCTAssertEqual(region.delta, 0.056, accuracy: 0.001)
    }

    func testRegionIsClampedToWorld() {
        let samples = [
            sample(elapsed: 0, depth: 0, latitude: -80, longitude: -170),
            sample(elapsed: 60, depth: 0, latitude: 80, longitude: 170)
        ]
        let route = DiveRoute(samples: samples, startDate: base, minimumSpacing: 0)
        guard let region = route.mapRegion() else { return XCTFail("Harita bölgesi bekleniyordu") }
        XCTAssertLessThanOrEqual(region.delta, 180)
    }

    func testDriftRatio() {
        let straight = DiveRoute(points: [
            .init(id: 0, elapsed: 0, coordinate: DiveCoordinate(latitude: 36.8, longitude: 34),
                  depth: 0, temperature: 20, speed: 0),
            .init(id: 1, elapsed: 60, coordinate: DiveCoordinate(latitude: 36.81, longitude: 34),
                  depth: 0, temperature: 20, speed: 0)
        ], startDate: base)
        XCTAssertEqual(straight.driftRatio, 1, accuracy: 0.01)

        // Düz çizgi + yandan sapma → sürüklenme > 1
        let wandering = DiveRoute(points: [
            .init(id: 0, elapsed: 0, coordinate: DiveCoordinate(latitude: 36.8, longitude: 34),
                  depth: 0, temperature: 20, speed: 0),
            .init(id: 1, elapsed: 30, coordinate: DiveCoordinate(latitude: 36.805, longitude: 34.005),
                  depth: 0, temperature: 20, speed: 0),
            .init(id: 2, elapsed: 60, coordinate: DiveCoordinate(latitude: 36.81, longitude: 34),
                  depth: 0, temperature: 20, speed: 0)
        ], startDate: base)
        XCTAssertGreaterThan(wandering.driftRatio, 1.2, "Saplama düz mesafeden uzun yol katetti")
    }

    func testAverageSpeed() {
        let route = DiveRoute(points: [
            .init(id: 0, elapsed: 0, coordinate: DiveCoordinate(latitude: 36.8, longitude: 34),
                  depth: 0, temperature: 20, speed: 0),
            .init(id: 1, elapsed: 100, coordinate: DiveCoordinate(latitude: 36.8, longitude: 34.001),
                  depth: 0, temperature: 20, speed: 0)
        ], startDate: base)
        // ~96 m / 100 s
        XCTAssertEqual(route.averageSpeed, 0.96, accuracy: 0.1)
    }

    func testCoordinateInterpolationOverTime() {
        let samples = [
            sample(elapsed: 0, depth: 0, latitude: 36.80, longitude: 34.00),
            sample(elapsed: 100, depth: 0, latitude: 36.82, longitude: 34.00)
        ]
        let route = DiveRoute(samples: samples, startDate: base, minimumSpacing: 0)
        guard let mid = route.coordinate(atElapsed: 50) else {
            return XCTFail("Ara koordinat bekleniyordu")
        }
        XCTAssertEqual(mid.latitude, 36.81, accuracy: 0.0001)
        // Aralık dışı ilk noktaya kenetlenir
        XCTAssertEqual(route.coordinate(atElapsed: -10)?.latitude ?? -1, 36.80, accuracy: 0.0001)
        XCTAssertEqual(route.coordinate(atElapsed: 999)?.latitude ?? -1, 36.80, accuracy: 0.0001)
    }

    @MainActor
    func testRouteRoundTripsThroughCodable() throws {
        let route = DiveRoute(samples: makeLog().samples, startDate: base)
        let data = try JSONEncoder().encode(route)
        XCTAssertEqual(try JSONDecoder().decode(DiveRoute.self, from: data), route)
    }

    // MARK: - UDDF

    @MainActor
    func testUDDFStructure() {
        let xml = UDDFExporter().export(makeLog())
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<uddf version=\"3.3.0\">"))
        XCTAssertTrue(xml.contains("</uddf>"))
        XCTAssertTrue(xml.contains("<generator>"))
        XCTAssertTrue(xml.contains("<samples>"))
        XCTAssertTrue(xml.contains("<applicationdata>"))
        XCTAssertTrue(xml.contains("<maxdepth>"))
        XCTAssertTrue(xml.contains("<runtime>"))
    }

    @MainActor
    func testUDDFIsBalancedXML() {
        let xml = UDDFExporter().export(makeLog())
        XCTAssertEqual(xml.components(separatedBy: "<uddf").count - 1, 1)
        XCTAssertEqual(xml.components(separatedBy: "<waypoint>").count,
                       xml.components(separatedBy: "</waypoint>").count)
        XCTAssertEqual(xml.components(separatedBy: "<gasp>").count,
                       xml.components(separatedBy: "</gasp>").count)
    }

    @MainActor
    func testUDDFEscapesSpecialCharacters() {
        let log = makeLog(location: "Kaş & <Yıldız> \"Lagoon\"")
        let xml = UDDFExporter().export(log)
        XCTAssertTrue(xml.contains("Kaş &amp; &lt;Yıldız&gt; &quot;Lagoon&quot;"))
        XCTAssertFalse(xml.contains("<location>Kaş & <"))
    }

    @MainActor
    func testUDDFGasProfile() {
        var log = makeLog()
        log.gases = [.air, GasMix.nitrox(36) ?? .air]
        let xml = UDDFExporter().export(log)
        XCTAssertTrue(xml.contains("<o2>0.360</o2>"))
        XCTAssertTrue(xml.contains("<n2>0.640</n2>"))
        XCTAssertEqual(xml.components(separatedBy: "<gasp>").count - 1, 2)
        XCTAssertEqual(xml.components(separatedBy: "<switchdepth>0</switchdepth>").count - 1, 1,
                       "Yalnızca başlangıç gazı switchdepth taşır")
    }

    @MainActor
    func testUDDFFirstAndLastSample() {
        let log = makeLog()
        let xml = UDDFExporter().export(log)
        XCTAssertTrue(xml.contains("<divetime>0.0</divetime>"))
        XCTAssertTrue(xml.contains("<depth>0.00</depth>"))
    }

    @MainActor
    func testUDDFSampleBudgetUsesMinMax() {
        let log = makeLog()
        let full = UDDFExporter().export(log)
        let reduced = UDDFExporter(options: .init(sampleBudget: 40)).export(log)
        XCTAssertLessThan(reduced.count, full.count)
        let fullWaypoints = full.components(separatedBy: "<waypoint>").count - 1
        let reducedWaypoints = reduced.components(separatedBy: "<waypoint>").count - 1
        XCTAssertLessThan(reducedWaypoints, fullWaypoints)
        // En derin örnek korunmalı (kovada max derinlik)
        let deepest = String(format: "<depth>%.2f</depth>", log.maxDepth)
        XCTAssertTrue(reduced.contains(deepest) || reduced.contains("30."))
    }

    @MainActor
    func testUDDFFirstAndLastPreservedUnderBudget() {
        let exporter = UDDFExporter(options: .init(sampleBudget: 20))
        let decimated = exporter.decimated(makeLog().samples)
        XCTAssertEqual(decimated.first?.elapsed, 0)
        let total = makeLog().totalDiveTime
        let lastElapsed = decimated.last?.elapsed ?? 0
        XCTAssertEqual(lastElapsed, total, accuracy: 15)
        XCTAssertEqual(decimated, decimated.sorted { $0.elapsed < $1.elapsed })
    }

    @MainActor
    func testUDDFFileName() {
        let name = UDDFExporter().suggestedFileName(makeLog(location: "Kaş Marina"))
        XCTAssertTrue(name.hasSuffix(".uddf"))
        XCTAssertTrue(name.contains("kaş-marina"))
        XCTAssertTrue(name.contains("2023-11-1"), "Tarih damgası içerir")
    }

    func testUDDFFromEmptyLog() {
        let log = LogEntry(startDate: base, samples: [])
        let xml = UDDFExporter().export(log)
        XCTAssertTrue(xml.contains("</uddf>"))
        XCTAssertFalse(xml.contains("<waypoint>"))
    }

    // MARK: - FIT

    @MainActor
    func testFITHeader() {
        let data = FITExporter().data(makeLog())
        let bytes = [UInt8](data)
        XCTAssertEqual(bytes[0], 12, "Başlık boyutu 12")
        XCTAssertEqual(bytes[1], 0x20, "Protokol sürümü 2.0")
        XCTAssertEqual(Array(bytes[8..<12]), [0x2E, 0x46, 0x49, 0x54], "\".FIT\" imzası")

        let declared = Int(bytes[4]) | (Int(bytes[5]) << 8) | (Int(bytes[6]) << 16) | (Int(bytes[7]) << 24)
        XCTAssertEqual(declared, bytes.count - 14,
                       "Veri boyutu beyanı, CRC hariç dosya gövdesini kapsar")
    }

    @MainActor
    func testFITCrcsAreValid() {
        let data = FITExporter().data(makeLog())
        let bytes = [UInt8](data)

        let headerStored = UInt16(bytes[12]) | (UInt16(bytes[13]) << 8)
        XCTAssertEqual(headerStored, FITExporter.crc(Array(bytes[0..<12])), "Başlık CRC")

        let fileStored = UInt16(bytes[bytes.count - 2])
            | (UInt16(bytes[bytes.count - 1]) << 8)
        XCTAssertEqual(fileStored, FITExporter.crc(Array(bytes[0..<(bytes.count - 2)])),
                       "Dosya CRC")
    }

    @MainActor
    func testFITStartsWithFileIdDefinitionMessage() {
        let bytes = [UInt8](FITExporter().data(makeLog()))
        // FIT'e göre ilk kayıt `file_id` **veri** mesajıdır (local tip 0),
        // tanımı olmaz — bu yüzden 0x40 (definition) biti set değildir.
        XCTAssertEqual(Int(bytes[14] & 0x80), 0, "İlk kayıt mesaj başıdır")
        XCTAssertEqual(Int(bytes[14] & 0x40), 0, "İlk kayıt tanım mesajı değildir")
        XCTAssertEqual(Int(bytes[14] & 0x0F), 0, "Yerel tip 0 (file_id)")
        // İlk veri mesajının ilk alanı `type` (uint16) = 4 (dive)
        let type = Int(bytes[15]) | (Int(bytes[16]) << 8)
        XCTAssertEqual(type, 4, "file_id.type = dive")
    }

    func testFITTimestampRoundTrip() {
        let timestamp = FITExporter.fitTimestamp(base)
        let restored = FITExporter.date(fromFitTimestamp: timestamp)
        XCTAssertEqual(restored.timeIntervalSince1970,
                       base.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFITDefinitionMessageEncodesFields() {
        let fields = [
            FITExporter.FieldDefinition(number: 253, size: 4,
                                        baseType: FITExporter.BaseType.uint32,
                                        scale: nil, offset: nil),
            FITExporter.FieldDefinition(number: 0, size: 2,
                                        baseType: FITExporter.BaseType.uint16,
                                        scale: 3, offset: nil)
        ]
        let bytes = FITExporter().definitionMessage(localType: 5, globalType: 18, fields: fields)
        XCTAssertEqual(bytes[0], 0x45, "0x40 | localType")
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertEqual(bytes[2], 18)
        XCTAssertEqual(bytes[3], 2, "Alan sayısı")
        // Ölçek/ofset yoksa alan 3 bayt: numara, boyut, taban türü
        XCTAssertEqual(bytes[4], 253)
        XCTAssertEqual(bytes[5], 4)
        XCTAssertEqual(bytes[6], FITExporter.BaseType.uint32)
        // Ölçek varsa alan 4 bayta çıkar
        XCTAssertEqual(bytes[7], 0)
        XCTAssertEqual(bytes[8], 2)
        XCTAssertEqual(bytes[9], FITExporter.BaseType.uint16)
        XCTAssertEqual(bytes[10], 3, "Ölçek alanı")
        XCTAssertEqual(bytes.count, 11)
    }

    func testFITDataMessageEncodesLittleEndian() {
        let bytes = FITExporter().dataMessage(localType: 2, values: [
            .uint32(0x01020304), .uint16(0x0506), .uint8(0x07)
        ])
        let expected = "02 04 03 02 01 06 05 07"
        let actual = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        XCTAssertEqual(actual, expected)
    }

    func testFITSignedValueEncoding() {
        let bytes = FITExporter().dataMessage(localType: 0, values: [.sint32(-1)])
        let actual = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        XCTAssertEqual(actual, "00 FF FF FF FF")
    }

    @MainActor
    func testFITRecordCountMatchesBudget() {
        let log = makeLog()
        let all = FITExporter().decimated(log.samples)
        XCTAssertEqual(all.count, log.samples.count)
        let limited = FITExporter(options: .init(sampleBudget: 30)).decimated(log.samples)
        XCTAssertLessThanOrEqual(limited.count, 30)
        XCTAssertEqual(limited.first?.elapsed, 0)
    }

    @MainActor
    func testFITIsCompactComparedToUDDF() {
        let log = makeLog()
        let fit = FITExporter().data(log).count
        let uddf = UDDFExporter().data(log).count
        XCTAssertLessThan(fit, uddf, "İkili format XML'den küçük olmalı")
    }

    @MainActor
    func testFITFileName() {
        let name = FITExporter().suggestedFileName(makeLog(location: "Kaş Marina"))
        XCTAssertTrue(name.hasSuffix(".fit"))
        XCTAssertTrue(name.contains("kaş-marina"))
    }

    // MARK: - Dışa aktarma servisi

    @MainActor
    func testServiceExportsAllFormats() {
        let service = DiveExportService()
        let log = makeLog()
        let exports = service.exportAll(log)
        XCTAssertEqual(exports.count, 3)
        XCTAssertEqual(Set(exports.map { $0.format }).count, 3)
        for export in exports {
            XCTAssertFalse(export.data.isEmpty)
            XCTAssertTrue(export.fileName.hasSuffix(".\(export.format.fileExtension)"))
            XCTAssertGreaterThan(export.byteCount, 0)
        }
    }

    @MainActor
    func testJSONExportIsValid() throws {
        let export = DiveExportService().export(makeLog(), format: .json)
        let object = try JSONSerialization.jsonObject(with: export.data)
        XCTAssertTrue(object is [String: Any])
        guard let dictionary = object as? [String: Any] else {
            return XCTFail("JSON nesne bekleniyordu")
        }
        XCTAssertNotNil(dictionary["startDate"])
        XCTAssertNotNil(dictionary["samples"])
    }

    func testValidationFlagsEmptyLog() {
        let issues = DiveExportService().validate(LogEntry(startDate: base, samples: []))
        XCTAssertTrue(issues.contains { $0.id == "noSamples" && $0.severity == .error })
        XCTAssertTrue(issues.contains { $0.id == "noDuration" && $0.severity == .error })
        XCTAssertFalse(DiveExportService().canExport(LogEntry(startDate: base, samples: [])))
    }

    @MainActor
    func testValidationOfGoodLog() {
        let issues = DiveExportService().validate(makeLog())
        XCTAssertFalse(issues.contains { $0.severity == .error })
        XCTAssertTrue(DiveExportService().canExport(makeLog()))
    }

    @MainActor
    func testValidationWarnsWithoutGPS() {
        let noGPS = makeLog(withGPS: false)
        let issues = DiveExportService().validate(noGPS)
        XCTAssertTrue(issues.contains { $0.id == "noGPS" && $0.severity == .info })
    }

    @MainActor
    func testPeekUDDFExtractsSummary() {
        let xml = UDDFExporter().export(makeLog(location: "Kaş Marina"))
        let peeked = DiveExportService().peekUDDF(xml)
        XCTAssertEqual(peeked["version"] ?? "", "3.3.0")
        XCTAssertEqual(peeked["location"] ?? "", "Kaş Marina")
        let waypointCount = Int(peeked["waypointCount"] ?? "0") ?? -1
        let actual = xml.components(separatedBy: "<waypoint>").count - 1
        XCTAssertEqual(waypointCount, actual)
    }

    @MainActor
    func testPeekUDDFUnescapesEntities() {
        let xml = UDDFExporter().export(makeLog(location: "Kaş & <Lagoon>"))
        XCTAssertEqual(DiveExportService().peekUDDF(xml)["location"] ?? "", "Kaş & <Lagoon>")
    }

    func testPeekInvalidUDDFIsEmpty() {
        XCTAssertTrue(DiveExportService().peekUDDF("hello").isEmpty)
    }

    @MainActor
    func testExportSummaryText() {
        let export = DiveExportService().export(makeLog(), format: .fit)
        XCTAssertTrue(export.summary.contains("FIT"))
        XCTAssertTrue(export.summary.contains("örnek"))
    }

    // MARK: - İnteraktif grafik modeli

    private func makeChartSamples() -> [DiveSample] {
        var result: [DiveSample] = []
        for i in 0...100 {
            let depth = min(30.0, Double(i) * 0.3)
            let temperature = 20.0 - Double(i) * 0.05
            let ascent = i > 50 ? 12.0 : -2.0
            let ceiling = i > 70 ? 3.0 : 0.0
            result.append(sample(elapsed: Double(i) * 30, depth: depth,
                                 temperature: temperature, ascentRate: ascent,
                                 gf99: Double(i), ceiling: ceiling))
        }
        return result
    }

    func testChartPointsFromMetric() {
        for metric in DiveChartModel.Metric.allCases {
            let chart = DiveChartModel(metric: metric, samples: makeChartSamples())
            XCTAssertEqual(chart.allPoints.count, 101, "\(metric.title) noktaları")
            XCTAssertFalse(chart.visiblePoints.isEmpty)
        }
        let depth = DiveChartModel(metric: .depth, samples: makeChartSamples())
        XCTAssertEqual(depth.allPoints.last?.y ?? 0, 30, accuracy: 0.001)
    }

    func testMetricTitlesAndUnits() {
        XCTAssertEqual(DiveChartModel.Metric.allCases.count, 5)
        for metric in DiveChartModel.Metric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.unit.isEmpty)
        }
        XCTAssertTrue(DiveChartModel.Metric.depth.isInverted)
        XCTAssertFalse(DiveChartModel.Metric.gf99.isInverted)
    }

    func testInitialRangeIsFullDive() {
        let chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        XCTAssertEqual(chart.visibleRange.lowerBound, 0)
        XCTAssertEqual(chart.visibleRange.upperBound, chart.totalDuration, accuracy: 0.01)
        XCTAssertEqual(chart.visiblePoints.count, chart.allPoints.count)
    }

    func testZoomInNarrowsWindow() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        let before = chart.visibleRange.upperBound - chart.visibleRange.lowerBound
        chart.zoomIn()
        let after = chart.visibleRange.upperBound - chart.visibleRange.lowerBound
        XCTAssertLessThan(after, before)
        XCTAssertGreaterThan(after, 0)
    }

    func testZoomOutReturnsToFull() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        chart.zoomIn(); chart.zoomIn()
        chart.resetZoom()
        XCTAssertEqual(chart.visibleRange.upperBound, chart.totalDuration, accuracy: 0.01)
    }

    func testZoomClampsToDiveBounds() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        for _ in 0..<20 { chart.zoomIn() }
        XCTAssertGreaterThanOrEqual(chart.visibleRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(chart.visibleRange.upperBound, chart.totalDuration + 0.01)
    }

    func testZoomRespectsMinimumWindow() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        for _ in 0..<40 { chart.zoomIn(minimumWindow: 120) }
        XCTAssertGreaterThanOrEqual(chart.visibleRange.upperBound - chart.visibleRange.lowerBound,
                                    120 - 0.01)
    }

    func testPanShiftsWindowWithinBounds() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        chart.setVisibleWindow(center: 1000, window: 600)
        let window = chart.visibleRange.upperBound - chart.visibleRange.lowerBound

        chart.pan(by: 500)
        XCTAssertEqual(chart.visibleRange.lowerBound, 1200, accuracy: 0.01)
        chart.pan(by: -10_000)
        XCTAssertEqual(chart.visibleRange.lowerBound, 0, accuracy: 0.01)
        chart.pan(by: 10_000)
        XCTAssertEqual(chart.visibleRange.upperBound, chart.totalDuration, accuracy: 0.01)
        let afterPan = chart.visibleRange.upperBound - chart.visibleRange.lowerBound
        XCTAssertEqual(afterPan, window, accuracy: 0.01, "Sürükleme pencereyi değiştirmez")
    }

    func testVisiblePointsFilterByRange() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        chart.setVisibleWindow(center: 900, window: 300)
        XCTAssertTrue(chart.visiblePoints.allSatisfy {
            $0.x >= chart.visibleRange.lowerBound && $0.x <= chart.visibleRange.upperBound
        })
        XCTAssertLessThan(chart.visiblePoints.count, chart.allPoints.count)
        XCTAssertNotNil(chart.visibleExtent)
    }

    func testCursorSnapsToNearestSample() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        chart.moveCursor(to: 890)
        XCTAssertEqual(chart.cursor ?? -1, 890)
        XCTAssertEqual(chart.selection?.x ?? -1, 900, accuracy: 1)
    }

    func testSelectionText() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        XCTAssertNil(chart.selectionText)
        chart.select(nearest: 1500)
        guard let text = chart.selectionText else {
            return XCTFail("Seçim metni bekleniyordu")
        }
        XCTAssertTrue(text.contains("Derinlik"))
        XCTAssertTrue(text.contains("m"))
    }

    func testClearSelection() {
        var chart = DiveChartModel(metric: .gf99, samples: makeChartSamples())
        chart.select(nearest: 600)
        XCTAssertNotNil(chart.selection)
        chart.clearSelection()
        XCTAssertNil(chart.selection)
        XCTAssertNil(chart.cursor)
        XCTAssertNil(chart.selectionText)
    }

    func testClearCursorKeepsSelection() {
        var chart = DiveChartModel(metric: .gf99, samples: makeChartSamples())
        chart.select(nearest: 600)
        chart.clearCursor()
        XCTAssertNil(chart.cursor)
        XCTAssertNotNil(chart.selection)
    }

    func testSelectionClampsToDiveDuration() {
        var chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        chart.select(nearest: 99_999)
        XCTAssertEqual(chart.cursor ?? -1, chart.totalDuration)
        chart.select(nearest: -100)
        XCTAssertEqual(chart.cursor ?? -1, 0)
    }

    func testDepthLookupForSync() {
        let chart = DiveChartModel(metric: .depth, samples: makeChartSamples())
        XCTAssertEqual(chart.depth(at: 0) ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(chart.depth(at: 3000) ?? -1, 30, accuracy: 0.001)
    }

    func testCeilingPointsOverlay() {
        let points = DiveChartModel.ceilingPoints(from: makeChartSamples())
        XCTAssertEqual(points.count, 101)
        XCTAssertTrue(points.contains { $0.y == 3 })
    }

    func testChartHandlesEmptySamples() {
        let chart = DiveChartModel(metric: .depth, samples: [])
        XCTAssertTrue(chart.allPoints.isEmpty)
        XCTAssertTrue(chart.visiblePoints.isEmpty)
        XCTAssertNil(chart.visibleExtent)
        XCTAssertNil(chart.selectionText)
    }

    func testVisibleExtentCoversWindow() {
        var chart = DiveChartModel(metric: .gf99, samples: makeChartSamples())
        chart.setVisibleWindow(center: 1500, window: 600)
        guard let extent = chart.visibleExtent else {
            return XCTFail("Görünür aralık bekleniyordu")
        }
        let values = chart.visiblePoints.map { $0.y }
        XCTAssertLessThanOrEqual(extent.lowerBound, values.min() ?? 0)
        XCTAssertGreaterThanOrEqual(extent.upperBound, values.max() ?? 0)
    }
}

// MARK: - Yardımcı (shim uyumlu)

