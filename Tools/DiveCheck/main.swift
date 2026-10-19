import DiveCore
import Foundation

/// `swift run divecheck` — Dekompresyon çekirdeğinin kalibrasyon raporu.
///
/// Çıktı, modelin NDL / tavan / TTS / GF99 / uçuş yasağı değerlerini PADI-NOAA
/// referans tablosuyla ve GF duyarlılığıyla birlikte gösterir. Bir dalış
/// bilgisayarının güvenlik parametreleri olduğu için bu rapor, ADIM 1'in
/// doğrulama çıktısı olarak CI'da da çalıştırılabilir.

func runDive(_ segments: [(depth: Double, duration: Double)],
             gas: GasMix = .air,
             gradientFactors: GradientFactors) -> DecoEngine {
    var engine = DecoEngine(gradientFactors: gradientFactors)
    for segment in segments {
        let steps = Int((segment.duration / 4).rounded(.up))
        let dt = segment.duration / Double(max(1, steps))
        for _ in 0..<steps {
            engine.update(toDepth: segment.depth, duration: dt, gas: gas)
        }
    }
    return engine
}

func line(_ text: String) { print(text) }
func section(_ title: String) {
    print("")
    print(String(repeating: "=", count: 70))
    print("  " + title)
    print(String(repeating: "=", count: 70))
}
func rule(_ title: String) {
    line("")
    line(String(repeating: "=", count: 78))
    line(title)
    line(String(repeating: "=", count: 78))
}

// MARK: - 1) Katsayılar

rule("1) ZH-L16C katsayıları ve yüzey M-değerleri")
line("  #  yarı ömür(dk)     a         b      M0 = a + 1/b (bar)")
for i in 0..<16 {
    let m0 = TissueModel.aCoefficients[i] + 1.0 / TissueModel.bCoefficients[i]
    line(String(format: "  %2d  %10.1f  %8.4f  %8.4f  %10.4f",
               i + 1, TissueModel.halfTimes[i],
               TissueModel.aCoefficients[i], TissueModel.bCoefficients[i], m0))
}

// MARK: - 2) NDL

rule("2) Havada no-döner süre (NDL) — PADI RDP karşılaştırması")
let reference: [(depth: Double, padi: Double)] = [
    (12, 147), (18, 56), (20, 45), (30, 20), (40, 9)
]
line("  derinlik   GF 100/100    GF 80/85   GF 30/70   PADI RDP")
for entry in reference {
    let gf100 = DecoEngine(gradientFactors: .default)
        .noDecompressionLimit(atDepth: entry.depth) / 60
    let gf8085 = DecoEngine(gradientFactors: .conservative)
        .noDecompressionLimit(atDepth: entry.depth) / 60
    let gf3070 = DecoEngine(gradientFactors: GradientFactors(low: 30, high: 70))
        .noDecompressionLimit(atDepth: entry.depth) / 60
    line(String(format: "  %5.0f m   %8.1f dk %9.1f dk %9.1f dk %8.0f dk",
               entry.depth, gf100, gf8085, gf3070, entry.padi))
}

// MARK: - 3) Senaryolar

rule("3) Senaryo özeti (GF 80/85, hava)")
line("  senaryo                 tavan     TTS     GF99    uçuş yasağı")
let scenarios: [(String, Double, Double)] = [
    ("12 m / 20 dk", 12, 20 * 60),
    ("18 m / 25 dk", 18, 25 * 60),
    ("18 m / 45 dk", 18, 45 * 60),
    ("30 m / 20 dk", 30, 20 * 60),
    ("30 m / 25 dk", 30, 25 * 60),
    ("30 m / 30 dk", 30, 30 * 60),
    ("40 m / 15 dk", 40, 15 * 60),
    ("45 m / 40 dk", 45, 40 * 60),
    ("45 m / 45 dk", 45, 45 * 60)
]
for scenario in scenarios {
    let engine = runDive([(scenario.1, scenario.2)], gradientFactors: .conservative)
    let ceiling = engine.ceiling(atDepth: scenario.1)
    line(String(format: "  %@                  %5.1f m  %6.1f dk  %5.0f%%  %6.1f sa",
               scenario.0 as NSString,
               ceiling.depthMeters,
               engine.timeToSurface(fromDepth: scenario.1) / 60,
               engine.gf99,
               engine.noFlyTime() / 3600))
}

// MARK: - 4) GF duyarlılığı

rule("4) Gradient Factor duyarlılığı — 30 m / 25 dk hava")
let presets: [GradientFactors] = [
    .default,                       // 100/100
    .conservative,                  // 80/85
    GradientFactors(low: 40, high: 85),
    .moderate,                      // 50/80
    GradientFactors(low: 30, high: 70),
    .aggressive,                    // 30/75
    .technical                      // 30/70
]
line("  GF         tavan     TTS     GF99")
for preset in presets {
    let engine = runDive([(30.0, 1500.0)], gradientFactors: preset)
    line(String(format: "  %3d/%-3d  %6.2f m %6.1f dk %6.0f%%",
               preset.low, preset.high,
               engine.ceiling(atDepth: 30).depthMeters,
               engine.timeToSurface(fromDepth: 30) / 60,
               engine.gf99))
}

// MARK: - 5) Gaz etkisi

rule("5) Gaz etkisi — 30 m / 25 dk (GF 80/85)")
line("  gaz   NDL(dip oncesi)   tavan     TTS     CNS     OTU      PO2")
for gas in [GasMix.air, .ean32, .ean36, .oxygen] {
    let ndlAtDepth = DecoEngine(gradientFactors: .conservative, gases: [gas], gasCylinderIndex: 0)
        .noDecompressionLimit(atDepth: 30) / 60
    // Gaz motorun başlangıç gazı olarak da verilmeli (aksi halde hava ile hesaplanır)
    var engine = DecoEngine(gradientFactors: .conservative, gases: [gas], gasCylinderIndex: 0)
    for reading in DiveSimulator(scenario: DiveScenario(name: "30 m / 25 dk", segments: [
        .descent(to: 30, at: 15), .hover(at: 30, for: 1500.0)
    ])).readings.dropFirst() {
        engine.update(toDepth: reading.depth, duration: 1)
    }
    line(String(format: "  %@  %10.1f dk %8.2f m %6.1f dk %6.1f%% %6.2f  %5.2f bar",
               gas.label as NSString,
               ndlAtDepth,
               engine.ceiling(atDepth: 30).depthMeters,
               engine.timeToSurface(fromDepth: 30) / 60,
               engine.oxygen.cnsPercent,
               engine.oxygen.otuUnits,
               engine.snapshot(atDepth: 30).po2))
}

rule("6) ADIM 2 — sensör / simülatör / alarm akışı")

let sensorScenarios: [(String, DiveScenario)] = [
    ("30 m / 20 dk (güvenli)", .recreational30m),
    ("12 m / 40 dk (başlangıç)", .beginner),
    ("Hızlı çıkış 18 m/dk", .fastAscentViolation),
    ("Emniyet durağı atlandı", .safetyStopSkipped),
    ("Deko dalışı 30 m / 45 dk", .decompressionDive)
]

@MainActor
func runSensorFlow() {
    print("  senaryo                        okuma  süre    max hız  tavan   GF99   alarmlar")
    for entry in sensorScenarios {
        let simulator = DiveSimulator(scenario: entry.1)
        let controller = DiveSessionController(configuration: .recreational)
        controller.start(at: simulator.startDate)

        var peakRate = 0.0
        var alarms: [String] = []
        controller.onStateChange = { state in peakRate = max(peakRate, state.ascentRate) }
        controller.onAlarms = { actions in
            for action in actions { alarms.append(action.sourceWarning?.rawValue ?? "?") }
        }
        controller.ingest(simulator.readings)

        let unique = Array(Set(alarms)).sorted().joined(separator: ",")
        print(String(format: "  %-30@ %5d %6.0f %7.1f %7.2f %6.0f   %@",
                     entry.0 as NSString, simulator.readings.count,
                     simulator.profileDuration, peakRate,
                     controller.state.ceilingDepth, controller.state.gf99,
                     unique.isEmpty ? "-" : unique as NSString))
    }
}

MainActor.assumeIsolated { runSensorFlow() }

rule("7) ADIM 3 — ekran/sunum kararlari")

@MainActor
func runDisplayFlow() {
    print("  faz          derinlik  sure    NDL/tavan  hiz     banner        AOD")
    let simulator = DiveSimulator(scenario: .recreational30m)
    let controller = DiveSessionController(configuration: .recreational)
    controller.start(at: simulator.startDate)

    var lastMode: DivePhase?
    var snapshotMode = false

    func report(_ state: DiveState, elapsed: TimeInterval) {
        let active = DiveDisplayBuilder.build(from: state)
        let aod = DiveDisplayBuilder.build(from: state, isAlwaysOn: true)
        let banner = active.banner.map { "\($0.title)" } ?? "-"
        print(String(format: "  %-11@ %8@ %8@ %9@ %6@  %-13@ %@",
                     active.mode.rawValue as NSString,
                     "\(active.depthText) m" as NSString,
                     active.diveTimeText as NSString,
                     (active.hasNdl ? "NDL \(active.ndlText)" : "T \(active.deco.ceilingText) m") as NSString,
                     active.ascentRate.text as NSString,
                     banner as NSString,
                     aod.banner == nil ? "sade" : "uyari" as NSString))
    }

    controller.onStateChange = { state in
        if state.phase != lastMode {
            lastMode = state.phase
            report(state, elapsed: state.diveTime)
        }
        // Emniyet durağı ortası ve hızlı çıkış anı gibi kritik anlar
        if !snapshotMode,
           state.safetyStop.isActive,
           state.safetyStop.accumulated >= 60, state.safetyStop.accumulated < 61 {
            snapshotMode = true
            report(state, elapsed: state.diveTime)
        }
    }
    controller.ingest(simulator.readings)

    // Hızlı çıkış senaryosu — kritik alarm anı
    print()
    let fast = DiveSimulator(scenario: .fastAscentViolation)
    let fastController = DiveSessionController(configuration: .recreational)
    fastController.start(at: fast.startDate)
    var printed = false
    fastController.onStateChange = { state in
        if !printed, state.warnings.contains(where: { $0.kind == .fastAscent }) {
            printed = true
            let display = DiveDisplayBuilder.build(from: state)
            print("  HIZLI CIKIS: role=\(display.backgroundColorRole) banner=\(display.banner?.title ?? "-") hiz=\(display.ascentRate.text) (\(display.ascentRate.level))")
            print("  komplikasyon: circular vurgu=\(DiveComplicationBuilder.build(from: state, style: .circular).accentRole)")
            print("  action button: \(DiveActionButtonResolver.intent(for: state, isDiving: true).label)")
        }
    }
    fastController.ingest(fast.readings)

    print()
    let endState = fastController.state
    let log = fastController.end(at: fast.startDate.addingTimeInterval(fast.profileDuration))
    let summary = DiveSummaryDisplay(state: endState, log: log)
    print("  OZET: azami \(summary.maxDepthText) | sure \(summary.diveTimeText) | notr \(summary.gradeText) | CNS \(summary.cnsText) | uclus \(summary.noFlyText)")
}

MainActor.assumeIsolated { runDisplayFlow() }

rule("8) ADIM 4 — deko plani, rehber, rapor, yuzey araligi")

@MainActor
func runStage4Flow() {
    let controller = DiveSessionController(configuration: .recreational)
    let simulator = DiveSimulator(scenario: .decompressionDive)
    controller.start(at: simulator.startDate)
    controller.ingest(simulator.readings)
    let log = controller.end(at: simulator.startDate.addingTimeInterval(simulator.profileDuration))

    let report = controller.lastReport ?? controller.makeReport()
    let display = DiveReportDisplay(report: report)

    print("  == Deko plani (dibe göre) ==")
    let plan = planDisplay(forDepth: report.maxDepth)
    print("   \(plan.headline)")
    for row in plan.rows {
        let tag = row.isSafetyStop ? " (emniyet)" : ""
        print("     \(row.depthText)  varış \(row.arrivalText) → kalış \(row.holdText) → \(row.departureText)  \(row.gasLabel)\(tag)")
    }
    print("     çıkış \(plan.ascentTimeText) · durakta \(plan.holdTimeText) · toplam \(plan.totalTimeText)")

    print("\n  == Çıkış rehberi (yüzeyde) ==")
    let guidance = GuidanceDisplay(guidance: controller.guidance)
    print("     \(guidance.instruction) | tavanüstü \(guidance.maximumAllowedText) | sonraki \(guidance.nextStopText) | TTS \(guidance.ttsText)")

    print("\n  == Dalış raporu ==")
    print("     \(display.headline) | not \(display.gradeText) (puan \(display.score))")
    print("     azami \(display.maxDepthText) · ort \(display.averageDepthText) · süre \(display.totalTimeText) · dipte \(display.bottomTimeText)")
    print("     hızlar \(display.maxRatesText) · sıcaklık \(display.temperatureText) · gaz \(display.gasText)")
    print("     PO₂ \(display.po2Text) · GF99 \(display.gf99Text) · CNS \(display.cnsText) · OTU \(display.otuText)")
    print("     emniyet durağı: \(display.safetyStopText) · deko: \(display.totalDecoText)")
    if display.decoStopRows.isEmpty {
        print("     (zorunlu deko durağı kaydı yok)")
    }
    for row in display.decoStopRows {
        print("     durak: \(row.label) [\(row.gasLabel)]")
    }
    if display.penaltyRows.isEmpty {
        print("     kesinti yok")
    }
    for row in display.penaltyRows {
        print("     kesinti: \(row.reason) [\(row.icon)]")
    }

    print("\n  == Yüzey aralığı ==")
    var surface = SurfaceIntervalManager(resolution: 60)
    surface.recordDiveEnd(at: simulator.startDate.addingTimeInterval(simulator.profileDuration),
                          log: log ?? LogEntry(startDate: Date(), endDate: Date()))
    for hours in [1.0, 4.0, 12.0] {
        let at = simulator.startDate.addingTimeInterval(simulator.profileDuration + hours * 3600)
        let view = SurfaceIntervalDisplay(status: surface.update(to: at))
        print(String(format: "     +%2.0f sa: GF99 %@ · desat %@ · uçuş %@ · %@",
                     hours, view.gf99Text, view.desaturationText, view.noFlyText, view.statusText))
    }

    print("\n  == Oksijen ==")
    let oxygen = OxygenDisplay(status: OxygenStatus.evaluate(
        po2: report.maxPO2, cnsPercent: report.cnsPercent,
        otuUnits: report.otuUnits, otuPercent: report.oxygen.otuPercent))
    for metric in oxygen.metrics {
        print("     \(metric.label) \(metric.valueText) — \(metric.level.label) [\(metric.colorRole.rawValue)]")
    }
    print("     genel: \(oxygen.headline) · alarm: \(oxygen.isAlarm ? "var" : "yok")")
}

/// Aynı derinlikte bir dalışın planını verir (kalibrasyon amaçlı).
func planDisplay(forDepth depth: Double) -> DecoPlanDisplay {
    var engine = DecoEngine(gradientFactors: .conservative, gases: [.air, .oxygen], gasCylinderIndex: 0)
    let scenario = DiveScenario(name: "t", segments: [
        .descent(to: depth, at: 15), .hover(at: depth, for: 45 * 60.0)
    ])
    for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
        engine.update(toDepth: reading.depth, duration: 1, gas: .air)
    }
    return DecoPlanDisplay(plan: DecoStopPlan.make(from: engine, currentDepth: depth))
}

MainActor.assumeIsolated { runStage4Flow() }

rule("9) ADIM 5 — kalicilik, senkronizasyon, istatistik, grafik")

@MainActor
func runStage5Flow() {
    let store = InMemoryDiveLogStore()
    let logbook = DiveLogbook(store: store)
    let transport = LoopbackSyncTransport()
    logbook.bind(transport: transport)

    // Üç dalış üret (bugün, dün, 3 gün önce)
    let scenarios: [(DiveScenario, Double, String)] = [
        (.recreational30m, 0, "watch"),
        (.beginner, -86400, "watch"),
        (.decompressionDive, -3 * 86400, "watch")
    ]
    for (scenario, offset, _) in scenarios {
        let controller = DiveSessionController(configuration: .recreational)
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
        controller.start(at: start)
        controller.ingest(DiveSimulator(scenario: scenario).readings)
        let log = controller.end(at: start.addingTimeInterval(controller.state.diveTime))!
        _ = try? logbook.add(log: log, report: controller.makeReport(log: log))
    }

    let stats = logbook.statistics
    print("  == Istatistik ==")
    print("     \(stats.diveCount) dalış · toplam \(DurationFormatter.hoursMinutes(stats.totalDiveTime))")
    print("     azami \(String(format: "%.1f", stats.deepestDive)) m · en uzun \(DurationFormatter.hoursMinutes(stats.longestDiveTime))")
    print("     deko: \(stats.divesWithDeco) · emniyet durağı tamamlanan: \(stats.completedSafetyStops) · en iyi not: \(stats.bestGrade.rawValue)")
    print("     gaz kullanımı: \(stats.gasUsage) · toplam OTU \(Int(stats.totalOTU))")

    print("\n  == Gunluk toplamlar ==")
    for totals in logbook.dailyTotals.prefix(3) {
        print("     \(totals.day): \(totals.diveCount) dalış · OTU %\(Int(totals.otuPercent)) (%\(Int(totals.otuSum))) · CNS %\(Int(totals.cnsPercent))")
        print("        → \(totals.advice())")
    }

    print("\n  == Senkronizasyon ==")
    print("     bekleyen: \(logbook.pendingSyncCount) · etiket: \(logbook.defaultSyncLabel())")
    logbook.syncNow()
    transport.drain()
    print("     gönderim sonrası bekleyen: \(logbook.pendingSyncCount) · durum: \(logbook.syncStatistics)")

    // Karşı taraftan yeni kayıt geliyor (iPhone → watch)
    let phoneDive = DiveSampleFixturesLog(identifier: UUID())
    logbook.accept([DiveSyncRecord(dive: phoneDive)])
    print("     gelen kayıt sonrası defter: \(logbook.diveCount) dalış")

    // Çakışma: eski sürüm gönderilirse yerel korunur
    var older = phoneDive
    older.updatedAt = phoneDive.updatedAt.addingTimeInterval(-3600)
    logbook.accept([DiveSyncRecord(dive: older)])
    print("     eski sürüm gönderilince: yerel korundu, bekleyen \(logbook.pendingSyncCount)")

    print("\n  == Grafik ==")
    for row in logbook.display().rows.prefix(3) {
        print("     \(row.title)")
    }
    let diveID = logbook.dives.last?.id
    if let diveID, let chart = logbook.chart(for: diveID, pointBudget: 40) {
        print("     profil grafiği: \(chart.series.count) seri · süre \(Int(chart.duration)) sn · azami \(String(format: "%.1f", chart.maxDepth)) m")
        print("     indirgeme: \(logbook.chart(for: diveID, pointBudget: 40)?.series(.depth)?.points.count ?? 0) nokta (bütçe 40)")
        for series in chart.series {
            let domain = series.valueDomain
            print("     \(series.kind.title): \(series.kind.unit) aralık \(String(format: "%.1f", domain.lowerBound))...\(String(format: "%.1f", domain.upperBound))")
        }
    }

    print("\n  == Kayıt örneği ==")
    if let first = logbook.dives.first {
        print("     id: \(first.id) · \(first.displayTitle)")
        print("     güncelleme: \(first.updatedAt) · cihaz: \(first.originDevice) · örnek: \(first.samples.count)")
    }
}

/// Karşı taraftan gelen kayıt örneği.
func DiveSampleFixturesLog(identifier: UUID) -> LoggedDive {
    let start = Date(timeIntervalSince1970: 1_700_000_000 - 7200)
    return LoggedDive(id: identifier, startDate: start, endDate: start.addingTimeInterval(1500),
                      totalDiveTime: 1500, maxDepth: 24, averageDepth: 15,
                      bottomTime: 900, minimumTemperature: 19, maximumTemperature: 24,
                      maxAscentRate: 9, maxDescentRate: 14,
                      gases: [.ean32], startGasIndex: 0,
                      maxPO2: 1.05, maxGF99: 64, cnsPercent: 18, otuUnits: 60,
                      hadDecoObligation: false, decoStops: [],
                      safetyStopCompleted: true, safetyStopAccumulated: 180,
                      noFlyTime: 7200, score: 5, grade: .excellent, penalties: [],
                      markerCount: 1, samples: [], updatedAt: start.addingTimeInterval(60),
                      originDevice: "phone")
}

MainActor.assumeIsolated { runStage5Flow() }

rule("10) ADIM 6 — GF ayarlari, coklu gaz, derin duraklar")

func runStage6Flow() {
    print("  == GF katalogu ==")
    for preset in GradientFactorCatalog.presets {
        let mark = String(repeating: " ", count: 0)
        print("     \(preset.factorsText.padding(toLength: 7, withPad: " ", startingAt: 0)) \(preset.name.padding(toLength: 16, withPad: " ", startingAt: 0)) — \(preset.summary)")
        _ = mark
    }

    print("\n  == Derinlige gore GF onerisi ==")
    for (depth, minutes) in [(12.0, 40.0), (30.0, 15.0), (30.0, 40.0), (45.0, 30.0), (70.0, 30.0)] {
        let preset = GradientFactorCatalog.recommended(maxDepth: depth, duration: minutes * 60)
        print("     \(Int(depth)) m / \(Int(minutes)) dk → \(preset.name) (\(preset.factorsText))")
    }

    print("\n  == Nitrox secimi ve MOD ==")
    for depth in stride(from: 12.0, through: 42.0, by: 6.0) {
        let percent = NitroxPicker.recommendedPercent(targetDepth: depth)
        let mod = NitroxPicker.maximumDepth(for: percent) ?? 0
        print("     \(Int(depth)) m → EAN%\(percent) (MOD \(String(format: "%.1f", mod)) m, N₂ %\(100 - percent))")
    }

    print("\n  == Coklu gaz plani (EAN35 + deko O2) ==")
    let plan = GasPlan.nitroxWithDeco(.nitrox(35) ?? .ean32)
    for (index, cylinder) in plan.cylinders.enumerated() {
        print("     \(index + 1). \(cylinder.label.padding(toLength: 14, withPad: " ", startingAt: 0)) MOD \(cylinder.gas.maximumOperatingDepthText(maxPO2: cylinder.effectiveMaxPO2()))")
    }
    for entry in plan.switchTable() {
        print("     gaz değişimi: \(Int(entry.depth)) m'de \(entry.from.label) → \(entry.to.label)")
    }
    print("     dogrulama: \(plan.validate().isEmpty ? "uygun" : plan.validate().map(\.message).joined(separator: ", "))")

    print("\n  == Derin duraklar (GF 80/85, 3 m aralik) ==")
    for (depth, minutes) in [(30.0, 50.0), (40.0, 60.0), (45.0, 70.0)] {
        var engine = DecoEngine(gradientFactors: .conservative, gases: [.air, .oxygen], gasCylinderIndex: 0)
        let scenario = DiveScenario(name: "t", segments: [.descent(to: depth, at: 15), .hover(at: depth, for: minutes * 60)])
        for reading in DiveSimulator(scenario: scenario).readings.dropFirst() {
            engine.update(toDepth: reading.depth, duration: 1, gas: .air)
        }
        let first = TissueModel.roundToStopInterval(engine.ceiling(atDepth: depth).depthMeters)
        let stops = DeepStopCalculator.deepStops(tissues: engine.tissues,
                                                 maxDepth: engine.tissues.maxDepth,
                                                 firstDecoStopDepth: first,
                                                 settings: .standard)
        let live = stops.filter { $0.isLive }
        let list = live.isEmpty ? "yok"
            : live.map { "\(Int($0.depth)) m (\(DurationFormatter.clock($0.holdTime)))" }.joined(separator: ", ")
        print("     \(Int(depth)) m / \(Int(minutes)) dk → tavan \(String(format: "%.1f", engine.ceiling(atDepth: depth).depthMeters)) m, ilk durak \(Int(first)) m | canlı derin durak: \(list)")
    }
}

runStage6Flow()

rule("11) ADIM 7 — su kilidi ve Action Button")

@MainActor
func runStage7Flow() {
    let lock = DiveLockController()
    print("  == Kilit yaşam döngüsü ==")
    print("     başlangıç: kilit=\(lock.isLocked) faz=\(lock.phase.rawValue)")
    lock.onDiveStarted()
    print("     dalış başladı: kilit=\(lock.isLocked) ekran dokunması=\(lock.blocksTouch(on: .diveScreen)) acil menü=\(lock.allowsEmergencyMenu)")
    let steps = lock.onDiveEnded()
    print("     dalış bitti: faz=\(lock.phase.rawValue) kilit=\(lock.isLocked) (kullanıcı kolunu çevirmeli)")
    print("     su atma döngüsü: \(steps.map { "\($0.name)/\($0.sound.rawValue)" }.joined(separator: " → "))")
    lock.onEjectionCompleted()
    print("     döngü bitti: faz=\(lock.phase.rawValue)")

    print("\n  == Action Button yönlendirmesi ==")
    print("     yüzeyde tek basış        → \(lock.action(for: .single, isDiving: false, hasCriticalAlarm: false).label)")
    print("     dalışta tek basış        → \(lock.action(for: .single, isDiving: true, hasCriticalAlarm: false).label)")
    print("     kritik alarm + tek basış → \(lock.action(for: .single, isDiving: true, hasCriticalAlarm: true).label)")
    print("     dalışta basılı tutma     → \(lock.action(for: .longPress, isDiving: true, hasCriticalAlarm: false).label)")
    print("     yüzeyde basılı tutma     → \(lock.action(for: .longPress, isDiving: false, hasCriticalAlarm: false).label)")

    print("\n  == Acil durum menüsü ==")
    let advisor = AscentAdvisor()
    let normal = advisor.evaluate(DiveState(phase: .ascending, currentDepth: 10, maxDepth: 40,
                                            diveTime: 2400, ascentRate: 2,
                                            ceilingDepth: 6, nextStopDepth: 6))
    let violation = advisor.evaluate(DiveState(phase: .ascending, currentDepth: 4, maxDepth: 40,
                                                diveTime: 2400, ascentRate: 2,
                                                ceilingDepth: 6, nextStopDepth: 6))
    print("     normal: \(lock.emergencyMenu(for: normal).map { $0.label }.joined(separator: ", "))")
    print("     tavan ihlali: \(lock.emergencyMenu(for: violation).map { $0.label }.joined(separator: ", "))")

    print("\n  == Su kilidi yönlendirmesi ==")
    print("     \(lock.waterLockGuidance)")
    lock.isSystemWaterLockEnabled = true
    print("     \(lock.waterLockGuidance)")
    print("     sistem API'si: Water Lock kamuya açık API ile açılamaz (kullanıcı Control Center'dan açar)")
}

MainActor.assumeIsolated { runStage7Flow() }

rule("Bitti.")
// MARK: - ADIM 8

@MainActor
func runStage8Flow() {
    section("ADIM 8 — Arka plan modu, kabin basıncı, tekrarlı dalış")
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let controller = DiveSessionController(configuration: .recreational)
    controller.start(at: base)
    controller.ingest(DiveSimulator(scenario: .decompressionDive).readings)
    let log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
    let diveEnd = log.endDate ?? base

    var surface = SurfaceIntervalManager(resolution: 60)
    surface.recordDiveEnd(at: diveEnd, log: log)
    let status = surface.update(to: diveEnd)

    print("\n  == Uçuş yasağı ve kabin basıncı ==")
    print(String(format: "  dalış sonu GF99 %%%.0f · desat %@",
                 status.gf99, DurationFormatter.clock(status.desaturationRemaining)))
    for cabin in FlightAltitudeCalculator.CabinProfile.all {
        let time = FlightAltitudeCalculator.noFlyTime(tissues: surface.residualTissues,
                                                      cabin: cabin)
        print(String(format: "     %-28@ f=%.2f (%.2f bar) → %@",
                     cabin.title as NSString, cabin.cabinFactor,
                     FlightAltitudeCalculator.cabinPressure(for: cabin),
                     DurationFormatter.hoursMinutes(time) as NSString))
    }

    print("\n  == Arka plan izleme planı ==")
    let policy = BackgroundMonitoringPolicy.standard
    print("  politika: max \(Int(policy.maximumInterval))sn · min \(Int(policy.minimumInterval))sn · bütçe \(policy.maximumChecks)")
    var cursor = diveEnd
    for _ in 0..<6 {
        let remaining = FlightAltitudeCalculator.noFlyTime(tissues: surface.residualTissues)
            - cursor.timeIntervalSince(diveEnd)
        guard let next = policy.nextCheckDate(now: cursor,
                                              remainingNoFly: max(0, remaining),
                                              remainingDesaturation: max(0, remaining)) else {
            print("  \(DurationFormatter.clock(cursor.timeIntervalSince(diveEnd))) → izleme bitti")
            break
        }
        print("  t=\(DurationFormatter.clock(cursor.timeIntervalSince(diveEnd))) → sonraki kontrol +\(DurationFormatter.clock(next.timeIntervalSince(cursor)))")
        cursor = next
    }
    let noFly = FlightAltitudeCalculator.noFlyTime(tissues: surface.residualTissues)
    print("  tahmini kontrol sayısı: \(policy.expectedCheckCount(remainingNoFly: noFly))")

    print("\n  == Tekrar dalış hesaplayıcısı ==")
    for hours in [0.1, 1.0, 4.0] {
        let at = diveEnd.addingTimeInterval(hours * 3600)
        _ = surface.update(to: at)
        let result = RepetitiveDiveCalculator.calculate(
            tissues: surface.residualTissues, targetDepth: 40, plannedDuration: 25 * 60)
        print(String(format: "  +%.1f sa → NDL %@ (taze %@) · deko %@ · uçuş %@ · gaz %@",
                     hours, DurationFormatter.clock(result.effectiveNDL) as NSString,
                     DurationFormatter.clock(result.freshNDL) as NSString,
                     result.hasDecoObligation ? "var" : "yok",
                     DurationFormatter.hoursMinutes(result.noFlyTime) as NSString,
                     result.suggestedGas.label as NSString))
        for warning in result.warnings { print("     ! \(warning)") }
    }

    print("\n  == Çoklu dalış planı (90 dk yüzey aralığı) ==")
    let sequence = RepetitiveDiveCalculator.sequence(
        dives: [(depth: 30.0, duration: 20.0 * 60),
                (depth: 30.0, duration: 20.0 * 60),
                (depth: 30.0, duration: 20.0 * 60)],
        surfaceInterval: 90 * 60)
    for (index, result) in sequence.enumerated() {
        print(String(format: "  %d. dalış: NDL %@ · uçuş %@",
                     index + 1,
                     DurationFormatter.clock(result.effectiveNDL) as NSString,
                     DurationFormatter.hoursMinutes(result.noFlyTime) as NSString))
    }
    rule("Bitti.")
}

MainActor.assumeIsolated { runStage8Flow() }


// MARK: - ADIM 9

@MainActor
func runStage9Flow() {
    section("ADIM 9 — Komplikasyon modları (canlı / yüzey aralığı / uçuş yasağı)")

    var diving = DiveState()
    diving.phase = .bottom
    diving.currentDepth = 24.6
    diving.maxDepth = 28.2
    diving.diveTime = 1_500
    diving.noDecompressionLimit = 600

    var deco = diving
    deco.noDecompressionLimit = 0
    deco.ceilingDepth = 3
    deco.nextStopDepth = 3

    let status = SurfaceIntervalStatus(elapsed: 3_600, gf99: 78,
                                       desaturationRemaining: 3_900,
                                       noFlyRemaining: 5_400,
                                       isNoFlyCleared: false,
                                       recommendation: "Yüzey aralığı sürüyor",
                                       statusDate: Date(timeIntervalSince1970: 1_700_000_000))

    print("\n  == Canlı modlar (dalış sırasında) ==")
    for style in [DiveComplicationData.Style.inline, .circular, .rectangular, .corner] {
        let live = DiveComplicationBuilder.build(mode: .liveDepth, state: diving,
                                                 isDiving: true, style: style, status: status)
        let ndl = DiveComplicationBuilder.build(mode: .liveNDL, state: diving,
                                                isDiving: true, style: style, status: status)
        print("  \(String(describing: style).padding(toLength: 12, withPad: " ", startingAt: 0)) canlı: \(live.primaryText) | \(live.secondaryText) | \(live.tertiaryText)")
        print("  \(String(describing: style).padding(toLength: 12, withPad: " ", startingAt: 0)) NDL : \(ndl.primaryText) | \(ndl.secondaryText) | \(ndl.tertiaryText)")
    }

    print("\n  == Deko yükümlülüğü varken ==")
    let decoData = DiveComplicationBuilder.build(mode: .liveNDL, state: deco, isDiving: true,
                                                 style: .rectangular, status: status)
    print("  \(decoData.primaryText) · \(decoData.secondaryText) · \(decoData.tertiaryText) [\(decoData.accentRole)]")

    print("\n  == Yüzey modları ==")
    for style in [DiveComplicationData.Style.inline, .circular, .rectangular, .corner] {
        let interval = SurfaceComplicationBuilder.build(mode: .surfaceInterval, status: status,
                                                       style: style)
        let noFly = SurfaceComplicationBuilder.build(mode: .noFly, status: status,
                                                    cabin: .standardFlight,
                                                    cabinRemaining: 19 * 3600, style: style)
        print("  \(String(describing: style).padding(toLength: 12, withPad: " ", startingAt: 0)) yüzey: \(interval.primaryText) | \(interval.secondaryText) | \(interval.tertiaryText)")
        print("  \(String(describing: style).padding(toLength: 12, withPad: " ", startingAt: 0)) uçuş : \(noFly.primaryText) | \(noFly.secondaryText) | \(noFly.tertiaryText)")
    }

    print("\n  == Mod çözümleme ==")
    let surfaced = DiveState(phase: .surfaced)
    for mode in DiveComplicationMode.allCases {
        let whileDiving = DiveComplicationModeResolver.effective(
            mode: mode, state: diving, isDiving: true, status: status)
        let onSurface = DiveComplicationModeResolver.effective(
            mode: mode, state: surfaced, isDiving: false, status: status)
        print("  \(mode.title.padding(toLength: 16, withPad: " ", startingAt: 0)) dalışta→\(whileDiving.title.padding(toLength: 16, withPad: " ", startingAt: 0)) yüzeyde→\(onSurface.title)")
    }

    print("\n  == Zaman çizelgesi (uçuş yasağı geri sayımı) ==")
    let entries = DiveComplicationTimeline.makeEntries(
        state: surfaced, isDiving: false, status: status,
        request: .init(mode: .noFly, style: .circular),
        now: status.snapshotDate ?? Date())
    print("  \(entries.count) giriş (sınır \(DiveComplicationTimeline.maximumEntries))")
    for entry in entries.prefix(6) {
        print("   t=\(DurationFormatter.clock(entry.date.timeIntervalSince(status.snapshotDate ?? Date())))  \(entry.data.primaryText)  [\(entry.countdownText ?? "-")]")
    }
    print("   …")
    if let last = entries.last {
        print("   t=\(DurationFormatter.clock(last.date.timeIntervalSince(status.snapshotDate ?? Date())))  \(last.data.primaryText)  [\(last.countdownText ?? "-")]")
    }
    if let refresh = DiveComplicationTimeline.nextRefreshDate(
        state: surfaced, isDiving: false, status: status,
        now: status.snapshotDate ?? Date()) {
        print("  sonraki yenileme: +\(DurationFormatter.clock(refresh.timeIntervalSince(status.snapshotDate ?? Date())))")
    }
    rule("Bitti.")
}

MainActor.assumeIsolated { runStage9Flow() }

// MARK: - ADIM 10

@MainActor
func runStage10Flow() {
    section("ADIM 10 — Rota, interaktif grafik ve UDDF/FIT dışa aktarma")

    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let controller = DiveSessionController(configuration: .recreational)
    controller.start(at: base)
    controller.ingest(DiveSimulator(scenario: .recreational30m).readings)
    var log = controller.end(at: base.addingTimeInterval(controller.state.diveTime))!
    log.location = "Kaş Marina"
    log.notes = "Sakin su, <test> & \"deneme\""

    // GPS yalnızca yüzeyde toplanır: burada "tekne dalışı" simüle edilir
    // (her 10 dakikada 10 saniye yüzeyde = tekne sürüklenmesi)
    var legIndex = 0.0
    log.samples = log.samples.map { sample in
        var copy = sample
        if Int(sample.elapsed).isMultiple(of: 600) {
            legIndex += 0.012
            copy.latitude = 36.80 + legIndex
            copy.longitude = 34.00 + legIndex * 0.6
        }
        return copy
    }

    print("\n  == GPS rota ==")
    let route = DiveRoute(samples: log.samples, startDate: base, minimumSpacing: 5)
    print("  nokta: \(route.pointCount) · mesafe: \(String(format: "%.1f", route.totalDistance)) m")
    print(String(format: "  ort. hız: %.3f m/s · sürüklenme: %.2f×", route.averageSpeed, route.driftRatio))
    if let region = route.mapRegion() {
        print(String(format: "  harita: %.4f, %.4f · delta %.4f°",
                     region.center.latitude, region.center.longitude, region.delta))
    }

    print("\n  == İnteraktif grafik ==")
    var chart = DiveChartModel(metric: .depth, samples: log.samples,
                               totalDuration: log.totalDiveTime)
    print("  toplam: \(Int(chart.totalDuration))sn · nokta: \(chart.allPoints.count)")
    chart.setVisibleWindow(center: chart.totalDuration / 2, window: 600)
    print(String(format: "  yakınlaştırılmış pencere: %.0f–%.0f sn (%d nokta)",
                 chart.visibleRange.lowerBound, chart.visibleRange.upperBound,
                 chart.visiblePoints.count))
    chart.moveCursor(to: chart.totalDuration * 0.5)
    print("  seçim: \(chart.selectionText ?? "-")")
    chart.zoomIn()
    print(String(format: "  bir kez daha yakınlaştır: %.0f–%.0f sn",
                 chart.visibleRange.lowerBound, chart.visibleRange.upperBound))
    chart.resetZoom()
    print("  sıfırlandı: \(Int(chart.visibleRange.lowerBound))–\(Int(chart.visibleRange.upperBound)) sn")

    print("\n  == Dışa aktarma denetimi ==")
    let service = DiveExportService()
    for issue in service.validate(log) {
        print("  [\(issue.severity.rawValue)] \(issue.message)")
    }

    print("\n  == Dışa aktarma ==")
    for export in service.exportAll(log) {
        print("  \(export.format.title): \(export.fileName) · \(export.byteCount) bayt · \(export.sampleCount) örnek")
    }

    print("\n  == UDDF yapısı ==")
    let xml = UDDFExporter().export(log)
    let lines = xml.split(separator: "\n").map(String.init)
    print("  satır: \(lines.count) · karakter: \(xml.count)")
    for line in lines.prefix(14) { print("  \(line)") }
    print("  …")
    let escaped = "&lt;test&gt; &amp; &quot;deneme&quot;"
    print("  kaçış denetimi: " + (xml.contains(escaped) ? "OK (\(escaped))" : "HATA"))

    print("\n  == FIT yapısı ==")
    let fit = FITExporter().data(log)
    let bytes = [UInt8](fit)
    print("  boyut: \(bytes.count) bayt")
    print("  ilk 14 bayt: " + bytes[0..<14].map { String(format: "%02X", $0) }.joined(separator: " "))
    print("  imza: " + String(bytes: bytes[8..<12], encoding: .ascii)!)
    let declared = Int(bytes[4]) | (Int(bytes[5]) << 8) | (Int(bytes[6]) << 16) | (Int(bytes[7]) << 24)
    print("  veri boyutu beyanı: \(declared) · gerçek: \(bytes.count - 14)")
    let headerCRC = UInt16(bytes[12]) | (UInt16(bytes[13]) << 8)
    print("  başlık CRC: \(headerCRC == FITExporter.crc(Array(bytes[0..<12])) ? "geçerli" : "GEÇERSİZ")")
    let fileCRC = UInt16(bytes[bytes.count - 2]) | (UInt16(bytes[bytes.count - 1]) << 8)
    print("  dosya CRC:   \(fileCRC == FITExporter.crc(Array(bytes[0..<(bytes.count - 2)])) ? "geçerli" : "GEÇERSİZ")")
    print("  UDDF/FIT oranı: \(String(format: "%.1f", Double(xml.count) / Double(fit.count)))×")
    rule("Bitti.")
}

MainActor.assumeIsolated { runStage10Flow() }

// MARK: - ADIM 11

@MainActor
func runStage11Flow() {
    section("ADIM 11 — Pil optimizasyonu, kırmızı gece modu, dinamik örnekleme")

    print("\n  == OLED kanal maliyeti (göreli) ==")
    for color in [DiveRGB.off,
                  DiveRGB(red: 1, green: 0, blue: 0),
                  DiveRGB(red: 0, green: 1, blue: 0),
                  DiveRGB(red: 0, green: 0, blue: 1),
                  DiveRGB.fullWhite] {
        let label: String
        switch (color.red, color.green, color.blue) {
        case (0, 0, 0): label = "siyah  "
        case (1, 0, 0): label = "kırmızı"
        case (0, 1, 0): label = "yeşil  "
        case (0, 0, 1): label = "mavi   "
        default: label = "beyaz  "
        }
        print(String(format: "  %@ parlaklık %.2f · OLED maliyeti %.2f",
                     label as NSString, color.perceivedBrightness, color.oledCost))
    }

    print("\n  == Tema güç karşılaştırması (AOD açık) ==")
    for theme in DiveDisplayTheme.allCases {
        let spec = DiveThemeCatalog.spec(for: theme)
        let milliwatts = EnergyBudget.displayMilliwatts(theme: theme, isAlwaysOn: true)
        print(String(format: "  %-14@ güç %.2f · ekran %6.1f mW · saniye %@ · ayrıntı %@",
                     spec.theme.title as NSString, spec.estimatedPower(), milliwatts,
                     (spec.showsSeconds ? "var" : "yok") as NSString,
                     (spec.showsSecondaryDetails ? "var" : "yok") as NSString))
    }

    print("\n  == Önerilen aralık ve süre öngörüsü ==")
    for profile in PowerProfile.allCases {
        for battery in [1.0, 0.5, 0.2] {
            let manager = EnergyManager(state: EnergyState(batteryLevel: battery,
                                                          isAlwaysOn: true,
                                                          isDiving: true,
                                                          profile: profile))
            let hours = manager.projectedHours
            print(String(format: "  %-14@ pil %3d%% → aralık %4.1f sn · tema %-12@ · %@ · %5.1f mW",
                         profile.title as NSString, Int(battery * 100),
                         manager.recommendedInterval, manager.theme.title as NSString,
                         (hours.isFinite ? "\(Int(hours * 60)) dk" : "—") as NSString,
                         manager.currentMilliwatts))
        }
    }

    print("\n  == Tam dalış boyunca tema/örnekleme ==")
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let controller = DiveSessionController(configuration: .recreational)
    controller.start(at: base)
    let manager = EnergyManager(state: EnergyState(batteryLevel: 0.85, isDiving: true))
    let policy = AdaptiveSamplingPolicy(profile: .balanced, state: manager.state)
    var sampler = AdaptiveSampler(policy: policy)
    var lastReason = ""
    var samples = 0
    for reading in DiveSimulator(scenario: .decompressionDive).readings {
        controller.ingest(reading)
        samples += 1
        let state = controller.state
        let context = AdaptiveSamplingPolicy.Context(state: state)
        let decision = sampler.update(context: context, elapsed: state.diveTime)
        if decision.reason.rawValue != lastReason {
            lastReason = decision.reason.rawValue
            print(String(format: "  t=%@ %5.1f m → %@ (%.1f sn)",
                         DurationFormatter.clock(state.diveTime) as NSString,
                         state.currentDepth, decision.reason.rawValue, decision.interval))
        }
    }
    print("  \(samples) sensör okuması · \(sampler.changeCount) mod değişimi · son aralık \(String(format: "%.1f", sampler.currentDecision.interval)) sn")
    print("  dalış sonu GF99 %\(Int(controller.state.gf99)) · enerji \(String(format: "%.1f", manager.currentMilliwatts)) mW")

    print("\n  == Kırmızı gece modu ekran verisi ==")
    var state = controller.state
    state.currentDepth = 18.4
    state.maxDepth = 30.2
    state.diveTime = 905
    let standard = DiveDisplayBuilder.build(from: state, isAlwaysOn: true, theme: .standard)
    let red = DiveDisplayBuilder.build(from: state, isAlwaysOn: true, theme: .alwaysOnRed)
    print("  standart: \(standard.depthText)m · maks \(standard.maxDepthText)m · süre \(standard.diveTimeText) · \(standard.gasLabel)")
    print("  AOD kırmızı: \(red.depthText)m · maks \(red.maxDepthText)m · süre \(red.diveTimeText) · gaz '\(red.gasLabel)'")

    print("\n  == Enerji önerileri (pil %8) ==")
    let low = EnergyManager(state: EnergyState(batteryLevel: 0.08, isDiving: true))
    for item in low.guidance {
        print("  [\(item.kind.rawValue)] \(item.message)\(item.action.map { " → \($0)" } ?? "")")
    }
    rule("Bitti.")
}

MainActor.assumeIsolated { runStage11Flow() }

// MARK: - ADIM 12

@MainActor
func runStage12Flow() {
    section("ADIM 12 — Sınır durum ve stres testleri")

    let base = Date(timeIntervalSince1970: 1_700_000_000)

    print("\n  == Aşırı hızlı çıkış (15+ m/dk) ==")
    var monitor = AscentRateMonitor(limit: DiveSafetyLimits.maximumAscentRate)
    for step in 1...40 {
        let elapsed = TimeInterval(step)
        let depth = max(0, 30 - 18.0 / 60.0 * Double(step))
        let update = monitor.update(with: DepthReading(
            depth: depth, timestamp: base.addingTimeInterval(elapsed), elapsed: elapsed))
        if step == 1 || step == 20 || step == 40 {
            print(String(format: "  t=%2ds derinlik %5.2f m · hız %6.2f m/dk · ihlal %@ · alarm %@",
                         step, depth, update.smoothedRate,
                         update.exceededLimit ? "EVET" : "hayır",
                         update.alarmDue ? "VAR" : "yok"))
        }
    }
    print("  toplam yükseliş: \(String(format: "%.1f", monitor.totalAscent)) m")

    print("\n  == Alarm zinciri (uçtan uca) ==")
    let haptic = RecordingHapticEngine()
    let controller = DiveSessionController(configuration: .recreational, haptic: haptic)
    controller.start(at: base)
    var elapsed: TimeInterval = 0
    while controller.state.currentDepth < 29.9 {
        elapsed += 1
        controller.ingest(DepthReading(depth: controller.state.currentDepth + 12.0 / 60.0,
                                       timestamp: base.addingTimeInterval(elapsed), elapsed: elapsed))
    }
    let bottomEnd = elapsed
    for step in 1...30 {
        elapsed += 1
        controller.ingest(DepthReading(depth: max(0, 30 - 18.0 / 60.0 * Double(step)),
                                       timestamp: base.addingTimeInterval(elapsed), elapsed: elapsed))
    }
    print("  dibe varış: \(DurationFormatter.clock(bottomEnd)) · 18 m/dk çıkış sonrası hız: \(String(format: "%.1f", controller.state.ascentRate)) m/dk")
    for warning in controller.state.warnings {
        print("  uyarı: [\(warning.severity.rawValue)] \(warning.message)")
    }
    print("  üretilen titreşim: \(haptic.performed.count)")

    print("\n  == Sığ suda dip zamanı sınırı ==")
    for depth in [3.0, 5.0, 8.0, 10.0, 12.0] {
        var line = String(format: "  %2.0f m:", depth)
        for hours in [1.0, 3.0, 6.0] {
            var engine = DecoEngine(gradientFactors: .conservative,
                                    gases: [.air, .oxygen], gasCylinderIndex: 0)
            engine.update(toDepth: depth, duration: depth / 15.0 * 60, gas: .air)
            engine.update(toDepth: depth, duration: hours * 3600, gas: .air)
            let ceiling = engine.ceiling(atDepth: depth).depthMeters
            let ndl = engine.noDecompressionLimit(atDepth: depth)
            line += String(format: "  %dsa tavan %@ (NDL %@)",
                           Int(hours), ceiling > 0 ? String(format: "%.1f m", ceiling) : "—",
                           ndl > 0 ? DurationFormatter.clock(ndl) : "0")
        }
        print(line)
    }

    print("\n  == Performans: bisection vs doğrusal (ADIM 12 bulgusu) ==")
    var engine = DecoEngine(gradientFactors: .conservative,
                            gases: [.air, .oxygen], gasCylinderIndex: 0)
    engine.update(toDepth: 5, duration: 3 * 3600, gas: .air)
    let t0 = Date()
    let ndl = engine.noDecompressionLimit(atDepth: 5)
    let t1 = Date()
    let desat = engine.desaturationTimeUntilGF99()
    let t2 = Date()
    let ndlText = ndl >= 6 * 3600 ? "6s+ (NDL sınırı)" : DurationFormatter.hoursMinutes(ndl)
    print(String(format: "  NDL: %@ (%.2f ms) · desatürasyon: %@ (%.2f ms)",
                 ndlText as NSString, t1.timeIntervalSince(t0) * 1000,
                 DurationFormatter.hoursMinutes(desat) as NSString,
                 t2.timeIntervalSince(t1) * 1000))
    print("  bisection ile ~40 adım (doğrusal taramada binlerce adım)")

    let t3 = Date()
    let soak = DiveSessionController(configuration: .recreational)
    soak.start(at: base)
    for step in 1...10_800 {
        let e = TimeInterval(step)
        soak.ingest(DepthReading(depth: 5, timestamp: base.addingTimeInterval(e), elapsed: e))
    }
    print(String(format: "  soak: 3 saat / 10.800 okuma → %.2f sn, GF99 %d",
                 Date().timeIntervalSince(t3), Int(soak.state.gf99)))

    print("\n  == Senkronizasyon: kopma ve yeniden bağlanma ==")
    var sync = DiveSyncEngine()
    for _ in 0..<10 { sync.enqueue(DiveSampleFixturesLog(identifier: UUID())) }
    print("  kuyruk: \(sync.pendingIDs.count) kayıt")
    let unreachable = OfflineTransport()
    for _ in 0..<3 { sync.flush(using: unreachable) }
    print("  3 başarısız deneme sonrası kuyruk: \(sync.pendingIDs.count) (korunmalı), hata: \(sync.statistics.failures)")
    let reachable = CollectingTransport()
    sync.flush(using: reachable)
    let delivered = reachable.delivered.count
    sync.acknowledge(reachable.delivered.map(\.id))
    print("  yeniden bağlanınca taşınan: \(delivered) · kalan kuyruk: \(sync.pendingIDs.count)")

    print("\n  == Çakışma çözümü ==")
    var _ = DiveSyncEngine(), b = DiveSyncEngine()
    let base2 = DiveSampleFixturesLog(identifier: UUID())
    var remote = base2
    remote.score = 2
    remote.updatedAt = base2.updatedAt.addingTimeInterval(60)
    b.receive([DiveSyncRecord(dive: remote)])
    let plan = b.mergePlan(against: [base2])
    print("  yeni uzak sürüm → güncelleme: \(plan.updated.count), çakışma: \(b.statistics.conflicts)")

    // Not: aynı motora hem yeni hem eski sürüm gönderilirse `receive`
    // yalnızca en yeniyi tutar. Karşılaştırma ayrı bir motorla yapılır:
    // "yerelde yeni sürüm var, uzaktan eski sürüm geldi" durumu.
    var localEngine = DiveSyncEngine()
    var newer = DiveSampleFixturesLog(identifier: UUID())
    newer.score = 5
    var staleRecord = DiveSyncRecord(dive: newer)
    staleRecord.updatedAt = newer.updatedAt.addingTimeInterval(-300)
    localEngine.receive([staleRecord])
    let plan2 = localEngine.mergePlan(against: [newer])
    print("  yerel yeni, uzak eski → güncelleme: \(plan2.updated.count) (olmamalı), geri gönderim: \(plan2.orphaned.count) (olmalı)")

    var equalEngine = DiveSyncEngine()
    equalEngine.receive([DiveSyncRecord(dive: newer)])
    let plan3 = equalEngine.mergePlan(against: [newer])
    print("  eşit zaman damgaları → değişiklik: \(plan3.changeCount), değişmeyen: \(plan3.unchanged) (veri kaybı olmamalı)")

    print("\n  == Dayanıklılık ==")
    let emptyCount = (try? DiveSyncEngine.decode(Data()))?.count ?? -1
    print("  boş paket → \(emptyCount) kayıt (hata fırlatmamalı)")
    let whitespaceCount = (try? DiveSyncEngine.decode(Data([0x20, 0x0A])))?.count ?? -1
    print("  yalnızca boşluk → \(whitespaceCount) kayıt (hata fırlatmamalı)")
    var truncatedThrows = false
    do { _ = try DiveSyncEngine.decode(Data([0x5B, 0x7B])) } catch { truncatedThrows = true }
    print("  kesik paket → hata: \(truncatedThrows ? "evet" : "HAYIR")")
    rule("Bitti.")
}

/// ADIM 12 — kalibrasyonda kullanılan çevrimdışı taşıma katmanı.
final class OfflineTransport: DiveSyncTransport {
    var onRecords: (([DiveSyncRecord]) -> Void)?
    var onAcknowledgement: (([UUID]) -> Void)?
    var onFailure: ((Error) -> Void)?
    var isReachable: Bool { false }
    struct Offline: Error {}
    func activate() {}
    func deactivate() {}
    func send(_ records: [DiveSyncRecord]) { onFailure?(Offline()) }
}

/// ADIM 12 — gönderilenleri toplayan taşıma katmanı.
final class CollectingTransport: DiveSyncTransport {
    var onRecords: (([DiveSyncRecord]) -> Void)?
    var onAcknowledgement: (([UUID]) -> Void)?
    var onFailure: ((Error) -> Void)?
    var isReachable: Bool { true }
    private(set) var delivered: [DiveSyncRecord] = []
    func activate() {}
    func deactivate() {}
    func send(_ records: [DiveSyncRecord]) { delivered.append(contentsOf: records) }
}

MainActor.assumeIsolated { runStage12Flow() }

// MARK: - ADIM 13

func runStage13Flow() {
    section("ADIM 13 — Dağıtım hazırlığı (TestFlight)")

    print("\n  == Sürümleme ==")
    print("  pazarlama sürümü: \(AppDistribution.currentVersion) · build: \(AppDistribution.currentBuild)")
    print("  biçim geçerli    : \(AppDistribution.isValidVersion(AppDistribution.currentVersion)) / \(AppDistribution.isValidBuildNumber(AppDistribution.currentBuild))")
    print("  minimum sürüm    : \(AppDistribution.minimumMarketingVersion)")
    print("  sayısal karşılaştırma: \(AppDistribution.compare("9.0", "10.0") == .orderedAscending ? "doğru" : "HATA") (sözlüksel karşılaştırma tuzağı)")

    print("\n  == Bundle kimlikleri ==")
    print("  watchOS : \(AppDistribution.BundleID.watchAppFull)")
    print("  iOS     : \(AppDistribution.BundleID.iOSApp)")
    print("  widget  : \(AppDistribution.BundleID.widgetExtension)")

    print("\n  == Arka plan modları ==")
    print("  watchOS: \(AppDistribution.watchBackgroundModes.joined(separator: ", "))")
    print("  iOS    : \(AppDistribution.iOSBackgroundModes.joined(separator: ", "))")
    print("  widget : \(AppDistribution.widgetBackgroundModes.isEmpty ? "yok (doğru)" : "TANIMLI OLMAMALI")")
    print("  BGTask : \(AppDistribution.backgroundTaskIdentifiers.joined(separator: ", "))")

    print("\n  == Kullanım açıklamaları ==")
    print("  iOS (\(AppDistribution.iOSUsageDescriptions.count)): \(AppDistribution.iOSUsageDescriptions.keys.sorted().joined(separator: ", "))")
    print("  watchOS (\(AppDistribution.watchUsageDescriptions.count)): \(AppDistribution.watchUsageDescriptions.keys.sorted().joined(separator: ", "))")
    var short = 0
    for (_, text) in AppDistribution.iOSUsageDescriptions where text.count < 20 { short += 1 }
    print("  çok kısa metin: \(short) (0 olmalı)")

    print("\n  == Yetkilendirme ==")
    let missing = AppDistribution.validate(entitlements: [:])
    print("  eksik yetkilendirme: \(missing.map(\.message).joined(separator: ", "))")
    var entitlements: [String: Any] = [:]
    for key in AppDistribution.requiredEntitlements { entitlements[key] = true }
    print("  tam yetkilendirme geçerli mi: \(AppDistribution.passes(AppDistribution.validate(entitlements: entitlements)))")

    print("\n  == Kontrol listesi (zorunlu) ==")
    for (index, item) in AppDistribution.releaseChecklist.filter(\.isRequired).enumerated() {
        print("  \(index + 1). [ ] \(item.title)")
    }
    print("  önerilen: \(AppDistribution.releaseChecklist.filter { !$0.isRequired }.map(\.title).joined(separator: ", "))")

    print("\n  == Doğrulama (örnek plist) ==")
    var plist: [String: Any] = [:]
    for key in AppDistribution.requiredKeys {
        switch key {
        case "CFBundleVersion": plist[key] = 1
        case "LSRequiresIPhoneOS": plist[key] = true
        case "UIRequiredDeviceCapabilities": plist[key] = ["arm64"]
        case "UISupportedInterfaceOrientations": plist[key] = ["UIInterfaceOrientationPortrait"]
        default: plist[key] = "deger"
        }
    }
    plist["CFBundleIdentifier"] = AppDistribution.BundleID.watchAppFull
    plist["CFBundleShortVersionString"] = AppDistribution.currentVersion
    plist["MinimumOSVersion"] = AppDistribution.watchAppRequirements.minimumSystemVersion
    for (key, text) in AppDistribution.watchUsageDescriptions { plist[key] = text }
    plist["UIBackgroundModes"] = AppDistribution.watchBackgroundModes
    let ok = AppDistribution.validate(plist: plist, requirements: AppDistribution.watchAppRequirements)
    print("  tam plist → \(AppDistribution.passes(ok) ? "geçti" : "kaldı") (\(ok.count) bulgu)")

    plist["UIBackgroundModes"] = ["workout-processing"]
    plist["NSMotionUsageDescription"] = ""
    plist["CFBundleShortVersionString"] = "1.0"
    plist["MinimumOSVersion"] = "9.0"
    let bad = AppDistribution.validate(plist: plist, requirements: AppDistribution.watchAppRequirements)
    print("  bozuk plist → \(AppDistribution.passes(bad) ? "GEÇTİ (HATA)" : "doğru şekilde reddedildi")")
    for error in bad.filter({ $0.severity == .error }) {
        print("    ✗ \(error.message)")
    }
    rule("Bitti.")
}

MainActor.assumeIsolated { runStage13Flow() }

// MARK: - Monetizasyon (ADIM 1)

@MainActor
func runCommerceFlow() {
    section("Monetizasyon (ADIM 1) — StoreKit 2 ve kapsamlar")

    let base = Date(timeIntervalSince1970: 1_700_000_000)

    print("\n  == Kapsamlar ==")
    for tier in DiveTier.allCases {
        print(String(format: "  %-12@ %@",
                     tier.title as NSString,
                     (tier.unlocksPro ? "Pro özellikler açık" : "güvenlik + sınırlı günlük") as NSString))
    }

    print("\n  == Ürün kataloğu ==")
    for offering in ProductCatalog.offerings() {
        let badge = offering.badge.map { " [\($0)]" } ?? ""
        print("  \(offering.productIdentifier) → \(offering.title)\(badge)")
    }
    print("  önerilen: \(ProductCatalog.recommendedOffering().title)")

    print("\n  == Kilitli özellikler (Temel sürüm) ==")
    let free = FeatureGate(entitlements: .none, now: base)
    for feature in free.lockedFeatures {
        print("  • \(feature.title) — \(feature.benefit)")
    }
    print("  toplam: \(free.lockedFeatures.count) / \(FeatureKey.allCases.count)")

    print("\n  == Günlük sınırı ==")
    for total in [1, 3, 5, 10, 40] {
        print(String(format: "  %2d dalış → görünen %2d · gizli %2d",
                     total,
                     free.visibleDives(Array(repeating: 0, count: total)).count,
                     free.hiddenDiveCount(total: total)))
    }

    print("\n  == Abonelik yaşam döngüsü ==")
    let sub = EntitlementSet.make(transactionIDs: [ProductCatalog.monthlyIdentifier],
                                  expiration: base.addingTimeInterval(30 * 86400), now: base)
    for day in [0, 15, 30, 31, 38, 60] {
        let date = base.addingTimeInterval(Double(day) * 86400)
        let gate = FeatureGate(entitlements: sub, now: date)
        print(String(format: "  +%2d gün → %-12@ kilitli özellik: %d",
                     day, gate.tier.title as NSString, gate.lockedFeatures.count))
    }
    let life = EntitlementSet.make(transactionIDs: [ProductCatalog.lifetimeIdentifier],
                                   expiration: nil, now: base)
    for year in [1, 10, 50] {
        let gate = FeatureGate(entitlements: life,
                               now: base.addingTimeInterval(Double(year) * 365 * 86400))
        print(String(format: "  Ömür boyu +%2d yıl → %@ (kilitli: %d)",
                     year, gate.tier.title as NSString, gate.lockedFeatures.count))
    }

    print("\n  == GÜVENLİK GARANTİSİ ==")
    print("  kapsam başına kilitli güvenlik kabiliyeti sayısı:")
    let gates: [(String, FeatureGate)] = [
        ("Temel", free),
        ("Pro Aylık", FeatureGate(entitlements: sub, now: base)),
        ("Ömür Boyu", FeatureGate(entitlements: life, now: base))
    ]
    for (name, gate) in gates {
        print("    \(name): \(gate.lockedSafetyCapabilityCount) (her zaman 0 olmalı)")
    }
    let critical: [SafetyCapability] = [.noDecompressionLimit, .ceiling, .decoStops,
                                        .ascentRateAlarm, .emergencyMenu, .waterLock]
    for capability in critical {
        let ok = free.canPerform(capability)
        print(String(format: "    %-22@ %@", capability.title as NSString,
                     (ok ? "ücretsiz ✓" : "KİLİTLİ ✗") as NSString))
    }
    print("  güvenlik kabiliyeti toplamı: \(SafetyCapability.allCases.count)")

    print("\n  == Bölüm kilitleri ==")
    print("  ayarlar   : \(free.lockedSettingsSections().map(\.title).joined(separator: ", "))")
    print("  günlük    : \(free.lockedLogbookSections().map(\.title).joined(separator: ", "))")
    print("  eşlikçi   : \(free.lockedCompanionSections().map(\.title).joined(separator: ", "))")

    print("\n  == Paywall metinleri ==")
    for trigger in [FeatureGate.PaywallTrigger.feature(.nitroxSupport),
                    .logHistory(hidden: 7),
                    .manual] {
        print("  başlık: \(trigger.headline)")
        print("  metin : \(trigger.message)")
    }
    rule("Bitti.")
}

MainActor.assumeIsolated { runCommerceFlow() }
