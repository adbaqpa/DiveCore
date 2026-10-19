import XCTest
@testable import DiveCore

/// Action Button niyeti, komplikasyon verisi ve dalış sonu özeti.
final class DiveAccessoryDataTests: XCTestCase {

    // MARK: - Yardımcı

    private func makeState(phase: DivePhase = .bottom,
                           warnings: [DiveWarning] = [],
                           maxDepth: Double = 0,
                           diveTime: TimeInterval = 0,
                           currentDepth: Double = 0,
                           ascentRate: Double = 0,
                           cns: Double = 0,
                           ndl: TimeInterval = 600) -> DiveState {
        DiveState(
            phase: phase,
            currentDepth: currentDepth, maxDepth: maxDepth,
            diveTime: diveTime,
            ascentRate: ascentRate,
            gas: .ean32, gases: [.air, .ean32], gasIndex: 1,
            noDecompressionLimit: ndl,
            gradientFactors: .conservative,
            cnsPercent: cns,
            warnings: warnings)
    }

    // MARK: - Action Button

    func testActionIntentOnSurfaceStartsDive() {
        XCTAssertEqual(DiveActionButtonResolver.intent(for: makeState(phase: .preDive),
                                                       isDiving: false),
                       .startDive)
    }

    func testActionIntentDuringDivePlacesMarker() {
        XCTAssertEqual(DiveActionButtonResolver.intent(for: makeState(phase: .bottom, currentDepth: 20),
                                                       isDiving: true),
                       .placeMarker)
        XCTAssertEqual(DiveActionButtonResolver.intent(for: makeState(phase: .ascending, currentDepth: 8),
                                                       isDiving: true),
                       .placeMarker)
    }

    func testActionIntentPrioritizesCriticalAlarm() {
        let warning = DiveWarning(kind: .fastAscent, severity: .critical,
                                  message: "HIZLI", raisedAtElapsed: 100)
        XCTAssertEqual(DiveActionButtonResolver.intent(for: makeState(phase: .ascending,
                                                                    warnings: [warning],
                                                                    currentDepth: 12),
                                                       isDiving: true),
                       .acknowledgeAlarm)
    }

    func testActionIntentAfterDiveIsNone() {
        XCTAssertEqual(DiveActionButtonResolver.intent(for: makeState(phase: .surfaced),
                                                       isDiving: false), .none)
        XCTAssertEqual(DiveActionButtonResolver.intent(for: makeState(phase: .ended),
                                                       isDiving: false), .none)
    }

    func testSecondaryIntentEndsDive() {
        XCTAssertEqual(DiveActionButtonResolver.secondaryIntent(for: makeState(phase: .bottom,
                                                                              currentDepth: 20),
                                                               isDiving: true), .endDive)
        XCTAssertEqual(DiveActionButtonResolver.secondaryIntent(for: makeState(phase: .preDive),
                                                               isDiving: false), .none)
    }

    func testIntentLabelsAndSymbols() {
        XCTAssertEqual(DiveActionIntent.startDive.label, "Dalışı Başlat")
        XCTAssertEqual(DiveActionIntent.placeMarker.symbolName, "mappin")
        XCTAssertEqual(DiveActionIntent.endDive.symbolName, "stop.fill")
        XCTAssertEqual(DiveActionIntent.none.symbolName, "circle")
    }

    // MARK: - Komplikasyon verisi

    func testInlineComplicationCombinesDepthTimeAndGas() {
        let data = DiveComplicationBuilder.build(from: makeState(diveTime: 760,
                                                                 currentDepth: 24.6), style: .inline)
        XCTAssertEqual(data.primaryText, "24.6m · 12:40")
        XCTAssertEqual(data.secondaryText, "EAN32")
        XCTAssertEqual(data.style, .inline)
    }

    func testInlineComplicationShowsPhaseAfterSurfacing() {
        let surfaced = DiveComplicationBuilder.build(from: makeState(phase: .surfaced), style: .inline)
        XCTAssertTrue(surfaced.primaryText.contains("Yüzey"),
                      "Yüzeydeyken süre yerine faz gösterilir")
    }

    func testCircularComplicationShowsDepthAndRate() {
        let data = DiveComplicationBuilder.build(from: makeState(maxDepth: 20,
                                                                 diveTime: 600,
                                                                 currentDepth: 12.0,
                                                                 ascentRate: 8), style: .circular)
        XCTAssertEqual(data.primaryText, "12.0")
        XCTAssertEqual(data.secondaryText, "8")
        XCTAssertEqual(data.tertiaryText, "10:00")
        XCTAssertEqual(data.accentRole, .caution)
    }

    func testRectangularComplicationShowsMaxDepthAndNdl() {
        let data = DiveComplicationBuilder.build(from: makeState(maxDepth: 22.0,
                                                                 diveTime: 1200,
                                                                 currentDepth: 18.4), style: .rectangular)
        XCTAssertEqual(data.primaryText, "18.4m  22.0m")
        XCTAssertEqual(data.tertiaryText, "20:00  NDL 10:00")
    }

    func testRectangularComplicationShowsTtsWhenInDeco() {
        let data = DiveComplicationBuilder.build(from: makeState(maxDepth: 30,
                                                                 diveTime: 2400,
                                                                 currentDepth: 18,
                                                                 ndl: 0), style: .rectangular)
        XCTAssertTrue(data.tertiaryText.contains("TTS"), "Deko varsa TTS gösterilir")
    }

    func testCornerComplicationIsCompact() {
        let data = DiveComplicationBuilder.build(from: makeState(maxDepth: 30,
                                                                 currentDepth: 30,
                                                                 ascentRate: -4), style: .corner)
        XCTAssertEqual(data.primaryText, "30.0")
        XCTAssertEqual(data.secondaryText, "▼")
    }

    func testComplicationFlagsActiveAlarm() {
        let warning = DiveWarning(kind: .ceilingViolation, severity: .critical,
                                  message: "TAVAN", raisedAtElapsed: 10)
        let data = DiveComplicationBuilder.build(from: makeState(warnings: [warning]), style: .circular)
        XCTAssertTrue(data.isAlarmActive)
        XCTAssertEqual(data.accentRole, .danger)
    }

    func testComplicationGaugeStaysInRange() {
        for style in [DiveComplicationData.Style.inline, .circular, .rectangular, .corner] {
            let data = DiveComplicationBuilder.build(from: makeState(maxDepth: 45, currentDepth: 45),
                                                      style: style)
            XCTAssertTrue((0...1).contains(data.gauge), "\(style): gauge aralık dışında")
        }
    }

    func testComplicationIntentLabelReflectsState() {
        XCTAssertEqual(DiveComplicationBuilder.build(from: makeState(phase: .preDive),
                                                     style: .inline).intentLabel,
                       DiveActionIntent.startDive.label)
        XCTAssertEqual(DiveComplicationBuilder.build(from: makeState(phase: .bottom, currentDepth: 20),
                                                     style: .inline).intentLabel,
                       DiveActionIntent.placeMarker.label)
    }

    // MARK: - Dalış özeti

    func testSummaryFormatting() {
        let state = makeState(phase: .ended, maxDepth: 30.4, diveTime: 1500,
                              currentDepth: 0, cns: 24)
        let summary = DiveSummaryDisplay(state: state)
        XCTAssertEqual(summary.title, "Dalış Tamamlandı")
        XCTAssertEqual(summary.maxDepthText, "30.4 m")
        XCTAssertEqual(summary.diveTimeText, "25dk")
        XCTAssertEqual(summary.gf99Text, "0%")
        XCTAssertEqual(summary.cnsText, "24%")
    }

    func testSummaryDetectsDecoObligation() {
        var state = makeState(phase: .ended, maxDepth: 40, diveTime: 3000)
        state.ceilingDepth = 3
        XCTAssertEqual(DiveSummaryDisplay(state: state).decoText, "Deko yapıldı")

        let noDeco = makeState(phase: .ended, maxDepth: 18, diveTime: 1200)
        XCTAssertEqual(DiveSummaryDisplay(state: noDeco).decoText, "Deko yok")
    }

    func testGradePenalisesFastAscentAndMissingStop() {
        let perfect = DiveGrade.grade(for: makeState(maxDepth: 18), log: nil)
        XCTAssertEqual(perfect.stars, 4, "Emniyet durağı tamamlanmadığı için 4 yıldız")

        let deepPerfect = DiveGrade.grade(
            for: makeState(maxDepth: 38),
            log: nil)
        XCTAssertGreaterThanOrEqual(deepPerfect.stars, 3)

        let bad = DiveGrade.grade(
            for: makeState(warnings: [DiveWarning(kind: .fastAscent, severity: .critical,
                                                message: "x", raisedAtElapsed: 1)],
                           maxDepth: 45, cns: 90),
            log: nil)
        XCTAssertEqual(bad, .poor)
        XCTAssertEqual(DiveGrade.text(for: makeState(maxDepth: 18)).count, 5)
    }

    func testGradeUsesLogForAscentHistory() {
        var engine = DecoEngine(gradientFactors: .conservative, gases: [.air], gasCylinderIndex: 0)
        _ = engine
        let samples = (0...10).map { index in
            DiveSample(elapsed: Double(index) * 60, depth: 20 - Double(index),
                       temperature: 20, ambientPressure: 3, po2: 0.6,
                       ascentRate: 18, gasIndex: 0, gf99: 50, ceiling: 0,
                       leadingTissuePressure: 1.2)
        }
        let log = LogEntry(startDate: Date(), endDate: Date(), gases: [.air], samples: samples)

        // Hızlı çıkış (−2) ve eksik emniyet durağı (−1) puan düşürür
        XCTAssertEqual(DiveGrade.grade(for: makeState(maxDepth: 20), log: log).stars, 3)
        XCTAssertEqual(DiveGrade.grade(for: makeState(maxDepth: 20), log: log), .fair)
    }

    // MARK: - Kodlama

    func testComplicationDataCodable() throws {
        let data = DiveComplicationBuilder.build(from: makeState(currentDepth: 10), style: .corner)
        let encoded = try JSONEncoder().encode(data)
        XCTAssertEqual(try JSONDecoder().decode(DiveComplicationData.self, from: encoded), data)
    }
}