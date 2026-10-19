import XCTest
@testable import DiveCore

/// ADIM 6 — GF ayar kataloğu, Nitrox/MOD, çoklu gaz planı.
final class DiveSettingsTests: XCTestCase {

    // MARK: - Gradient Factors

    func testCatalogContainsRequestedPresets() {
        XCTAssertEqual(GradientFactors.balanced.displayText, "75/85")
        XCTAssertEqual(GradientFactors.relaxed.displayText, "90/90")
        XCTAssertNotNil(GradientFactorCatalog.preset(id: "ufuk"))
        XCTAssertNotNil(GradientFactorCatalog.preset(id: "balanced"))
        XCTAssertNotNil(GradientFactorCatalog.preset(id: "relaxed"))
    }

    func testCatalogPresetsAreValid() {
        for preset in GradientFactorCatalog.presets {
            XCTAssertTrue(GradientFactorCatalog.isValid(low: preset.factors.low,
                                                      high: preset.factors.high),
                          "\(preset.name) geçersiz")
            XCTAssertFalse(preset.summary.isEmpty)
        }
    }

    func testClosestPreset() {
        XCTAssertEqual(GradientFactorCatalog.closestPreset(to: .balanced).id, "balanced")
        XCTAssertEqual(GradientFactorCatalog.closestPreset(to: .relaxed).id, "relaxed")
        XCTAssertEqual(GradientFactorCatalog.closestPreset(to: .conservative).id, "ufuk")
    }

    func testSpread() {
        XCTAssertEqual(GradientFactorCatalog.spread(of: .balanced), 10)
        XCTAssertEqual(GradientFactorCatalog.spread(of: .relaxed), 0)
        XCTAssertEqual(GradientFactorCatalog.spread(of: .technical), 40)
    }

    func testValidation() {
        XCTAssertTrue(GradientFactorCatalog.isValid(low: 75, high: 85))
        XCTAssertFalse(GradientFactorCatalog.isValid(low: 5, high: 85))
        XCTAssertFalse(GradientFactorCatalog.isValid(low: 90, high: 10))
    }

    func testRecommendationByDepthAndDuration() {
        // Başlangıç → en muhafazakâr
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 12, duration: 1800).id, "ufuk")
        // 30 m kısa dalış → gevşek
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 30, duration: 15 * 60).id, "relaxed")
        // 30 m uzun dalış → dengeli
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 30, duration: 40 * 60).id, "balanced")
        // 45 m → derin
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 45, duration: 30 * 60).id, "deep")
        // 70 m → teknik
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 70, duration: 30 * 60).id, "technical")
    }

    func testRecommendationByExperience() {
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 30, duration: 1800,
                                                         experience: .beginner).id, "ufuk")
        XCTAssertEqual(GradientFactorCatalog.recommended(maxDepth: 30, duration: 1800,
                                                         experience: .technical).id, "technical")
    }

    func testUniformFlag() {
        XCTAssertTrue(GradientFactors.relaxed.isUniform)
        XCTAssertFalse(GradientFactors.balanced.isUniform)
    }

    // MARK: - Nitrox

    func testNitroxFactory() {
        XCTAssertEqual(GasMix.nitrox(32)?.oxygenFraction ?? 0, 0.32, accuracy: 0.0001)
        XCTAssertNil(GasMix.nitrox(20), "%21 altı geçersiz")
        XCTAssertNil(GasMix.nitrox(101))
        XCTAssertNotNil(GasMix.nitrox(21))
        XCTAssertNotNil(GasMix.nitrox(100))
    }

    func testNitroxValidationRange() {
        XCTAssertTrue(NitroxPicker.isValid(percent: 22))
        XCTAssertTrue(NitroxPicker.isValid(percent: 40))
        XCTAssertFalse(NitroxPicker.isValid(percent: 20))
        XCTAssertFalse(NitroxPicker.isValid(percent: 101))
        // Seçim aralığı EAN22–40 (UI kaydırıcısı)
        XCTAssertEqual(NitroxPicker.standardRange, 21...40)
    }

    func testNitroxRecommendedPercentRespectsMod() {
        // 30 m dalış: EAN35'in MOD'u tam 30.0 m → EAN35 seçilir
        XCTAssertEqual(NitroxPicker.recommendedPercent(targetDepth: 30), 35)
        // 34 m: EAN32 (MOD 34.4 m) hâlâ uygun
        XCTAssertEqual(NitroxPicker.recommendedPercent(targetDepth: 34), 32)
        // 40 m: EAN29 (MOD 38.3) yetmez, EAN28'in MOD'u tam 40.0 m
        XCTAssertEqual(NitroxPicker.recommendedPercent(targetDepth: 40), 28)
        // Sığ dalışta en zengin karışım (EAN40)
        XCTAssertEqual(NitroxPicker.recommendedPercent(targetDepth: 15), 40)
    }

    func testNitroxRecommendedNeverExceedsMod() {
        for depth in stride(from: 6.0, through: 42.0, by: 1.0) {
            let percent = NitroxPicker.recommendedPercent(targetDepth: depth)
            guard let mod = NitroxPicker.maximumDepth(for: percent) else {
                return XCTFail("EAN\(percent) oluşturulamadı")
            }
            XCTAssertGreaterThanOrEqual(mod, depth - 0.5,
                                        "\(depth) m'de EAN\(percent) MOD \(mod) yetersiz")
        }
    }

    func testNitroxHelpers() {
        XCTAssertEqual(NitroxPicker.nitrogenPercent(32), 68)
        XCTAssertNil(NitroxPicker.nitrogenPercent(15))
        XCTAssertTrue(GasMix.ean32.isNitrox)
        XCTAssertFalse(GasMix.air.isNitrox)
        XCTAssertEqual(GasMix.ean32.nitrogenPercent, 68)
        XCTAssertTrue(GasMix.ean32.maximumOperatingDepthText().hasSuffix("m"))
    }

    // MARK: - MOD

    func testModValuesMatchReference() {
        // MOD = (maxPO₂ / fO₂ − 1) × 10 m
        XCTAssertEqual(GasMix.air.maximumOperatingDepth(maxPO2: 1.4), 57.3, accuracy: 0.3)
        XCTAssertEqual(GasMix.ean32.maximumOperatingDepth(maxPO2: 1.4), 34.4, accuracy: 0.3)
        XCTAssertEqual(GasMix.ean36.maximumOperatingDepth(maxPO2: 1.4), 29.5, accuracy: 0.3)
        XCTAssertEqual(GasMix.oxygen.maximumOperatingDepth(maxPO2: 1.4), 4.6, accuracy: 0.3)
    }

    func testModRespectsCustomMaxPo2() {
        // Deko dalışlarında PO₂ limiti 1.6 → O₂ 6.6 m'ye kadar
        XCTAssertEqual(GasMix.oxygen.maximumOperatingDepth(maxPO2: 1.6), 6.6, accuracy: 0.3)
        XCTAssertLessThan(GasMix.ean32.maximumOperatingDepth(maxPO2: 1.2),
                          GasMix.ean32.maximumOperatingDepth(maxPO2: 1.6))
    }

    func testModIsAlwaysAboveSixAtDiveLimit() {
        // Deko gazı olarak kullanılan O₂, 1.6 bar limitte 6 m civarında olmalı
        XCTAssertGreaterThan(GasMix.oxygen.maximumOperatingDepth(maxPO2: 1.6), 6)
        XCTAssertLessThan(GasMix.oxygen.maximumOperatingDepth(maxPO2: 1.6), 7)
    }

    // MARK: - Çoklu gaz planı

    func testSingleCylinderPlan() {
        let plan = GasPlan.single(.ean32)
        XCTAssertEqual(plan.cylinders.count, 1)
        XCTAssertEqual(plan.startGas, .ean32)
        XCTAssertEqual(plan.labels, ["EAN32 · 12L"])
        XCTAssertTrue(plan.validate().isEmpty)
    }

    func testTwoCylinderPlanSwitchesToOxygen() {
        let plan = GasPlan.nitroxWithDeco(.ean32)
        XCTAssertEqual(plan.cylinders.count, 2)
        XCTAssertEqual(plan.cylinders[1].gas, .oxygen)
        // Deko O₂ 1.6 bar limitle → MOD ≈ 6.6 m
        XCTAssertTrue(plan.cylinders[1].isUsable(at: 6,
                                                 maxPO2: plan.cylinders[1].effectiveMaxPO2()))
        XCTAssertFalse(plan.cylinders[1].isUsable(at: 8,
                                                  maxPO2: plan.cylinders[1].effectiveMaxPO2()),
                       "O₂ 6.6 m'den derinde kullanılamaz")
        XCTAssertFalse(plan.cylinders[1].isUsable(at: 6, maxPO2: 1.4),
                       "1.4 bar limitte O₂'nin MOD'u 4.6 m")
        XCTAssertEqual(plan.bestIndex(at: 3), 1, "Sığda saf O2 tercih edilir")
        XCTAssertEqual(plan.bestIndex(at: 30), 0, "Derinde EAN kalınır")
    }

    func testGasSwitchRequiredWhenModPassed() {
        let plan = GasPlan.nitroxWithDeco(.ean32)   // MOD ≈ 34.4 m
        XCTAssertFalse(plan.requiresSwitch(at: 30, currentIndex: 0))
        XCTAssertFalse(plan.requiresSwitch(at: 34, currentIndex: 0))
        XCTAssertTrue(plan.requiresSwitch(at: 35, currentIndex: 0), "MOD geçilince değişmeli")
        // 35 m'de deko O₂ de kullanılamaz → öneri yok, dalış sınırı aşıldı
        XCTAssertNil(plan.suggestion(at: 35, currentIndex: 0))
        XCTAssertFalse(plan.canReach(depth: 35))
        XCTAssertTrue(plan.canReach(depth: 30))
    }

    func testSwitchTable() {
        // O₂'nin MOD'u 1.4 bar limitte 4.6 m → 3 m pay ile ~1.6 m
        let plan = GasPlan(cylinders: [GasPlan.Cylinder(gas: .ean32),
                                       GasPlan.Cylinder(gas: .oxygen)], maxPO2: 1.6)
        let table = plan.switchTable()
        XCTAssertEqual(table.count, 1)
        XCTAssertEqual(table.first?.from, .ean32)
        XCTAssertEqual(table.first?.to, .oxygen)
        XCTAssertEqual(table.first?.depth ?? 0, 3.6, accuracy: 0.5,
                       "O2 MOD (6.6 m) − 3 m pay")
    }

    func testPlanValidationDetectsWrongOrder() {
        // Saf O₂ 1.4 bar limitte → MOD 4.6 m (bu tek başına sorun değil),
        // ama ardından gelen hava silindiri sıralama hatası üretir.
        let plan = GasPlan(cylinders: [
            GasPlan.Cylinder(gas: .oxygen),      // MOD 4.6 m (1.4 bar limit)
            GasPlan.Cylinder(gas: .air)          // MOD 57 m → yanlış sıra
        ])
        let issues = plan.validate()
        XCTAssertTrue(issues.contains { if case .wrongOrder = $0 { return true }; return false })
        XCTAssertFalse(issues.isEmpty)
        XCTAssertFalse(issues[0].message.isEmpty)
    }

    func testPlanValidationFlagsDecoGasBeyondSixMeters() {
        // 1.8 bar limitli saf O₂ → MOD 8 m, 6 m kuralını aşıyor
        let plan = GasPlan(cylinders: [
            GasPlan.Cylinder(gas: .ean32),
            GasPlan.Cylinder(gas: .oxygen, maxPO2Override: 1.8)
        ], maxPO2: 1.4)
        let issues = plan.validate()
        XCTAssertTrue(issues.contains { if case .decoGasTooDeep = $0 { return true }; return false })
    }

    func testCorrectDecoGasPassesValidation() {
        // Standart plan: dip gazı 1.4 bar, deko O₂ 1.6 bar → uyarı yok
        let plan = GasPlan.nitroxWithDeco(.ean32)
        XCTAssertTrue(plan.validate().isEmpty)
        XCTAssertEqual(plan.cylinders[1].effectiveMaxPO2(), 1.6)
    }

    func testPlanValidationAcceptsCorrectOrder() {
        let plan = GasPlan(cylinders: [GasPlan.Cylinder(gas: .ean32),
                                       GasPlan.Cylinder(gas: .oxygen)])
        XCTAssertTrue(plan.validate().isEmpty)
    }

    func testAirPlanHasNoSwitch() {
        XCTAssertTrue(GasPlan.air().switchTable().isEmpty)
        XCTAssertEqual(GasPlan.air().bestIndex(at: 40), 0)
    }

    // MARK: - DiveSettings

    func testSettingsToConfiguration() {
        let settings = DiveSettings(gradientFactors: .balanced,
                                    gasPlan: .nitroxWithDeco(.ean32),
                                    targetDepth: 30, targetDuration: 25 * 60)
        let config = settings.configuration()

        XCTAssertEqual(config.gradientFactors, .balanced)
        XCTAssertEqual(config.gases, [.ean32, .oxygen])
        XCTAssertEqual(config.startGasIndex, 0)
    }

    func testSuggestedSettingsPickNitrox() {
        let settings = DiveSettings.suggested(targetDepth: 30, targetDuration: 25 * 60)
        XCTAssertEqual(settings.gasPlan.cylinders.count, 2)
        XCTAssertTrue(settings.gasPlan.startGas.isNitrox)
        XCTAssertTrue(settings.isStartGasUsable)
    }

    func testSuggestedSettingsForShallowDiveUseRichNitrox() {
        let settings = DiveSettings.suggested(targetDepth: 15, targetDuration: 40 * 60)
        // 15 m'de EAN40'ın MOD'u (25 m) yeterli → en zengin karışım önerilir
        XCTAssertEqual(settings.gasPlan.startGas.oxygenFraction, 0.40, accuracy: 0.001)
        XCTAssertEqual(settings.gasPlan.cylinders.count, 2)
        XCTAssertTrue(settings.isStartGasUsable)
    }

    func testSettingsCodableRoundTrip() throws {
        let settings = DiveSettings.nitrox
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(DiveSettings.self, from: data), settings)
    }

    // MARK: - Ayar ekranı verisi

    func testSettingsDisplayRows() {
        let settings = DiveSettings(gradientFactors: .balanced,
                                    gasPlan: .nitroxWithDeco(.ean32),
                                    deepStops: .standard,
                                    targetDepth: 30, targetDuration: 25 * 60)
        let display = DiveSettingsDisplay(settings: settings, targetDepth: 30,
                                          targetDuration: 25 * 60, estimatedNDL: 900)

        XCTAssertEqual(display.factorsText, "75/85")
        XCTAssertEqual(display.factorsRows.count, GradientFactorCatalog.presets.count)
        XCTAssertEqual(display.factorsRows.filter(\.isSelected).count, 1)
        XCTAssertTrue(display.recommendationNote.contains("Öneri"))

        XCTAssertEqual(display.gasRows.count, 2)
        XCTAssertEqual(display.gasRows[0].label, "EAN32")
        XCTAssertTrue(display.gasRows[0].isStartGas)
        XCTAssertTrue(display.gasRows[1].isDecoGas)
        XCTAssertTrue(display.switchNote.contains("EAN32 → O₂"))

        XCTAssertTrue(display.deepStopsEnabled)
        XCTAssertEqual(display.targetDepthText, "30 m")
        XCTAssertEqual(display.estimatedNDLText, "15:00")
    }

    func testSettingsDisplayFlagsUnusableGas() {
        let settings = DiveSettings(gradientFactors: .conservative,
                                    gasPlan: .single(.ean36),   // MOD ~27 m
                                    targetDepth: 35)
        let display = DiveSettingsDisplay(settings: settings, targetDepth: 35,
                                          targetDuration: 20 * 60, estimatedNDL: 300)
        XCTAssertFalse(display.gasRows[0].isUsableAtTargetDepth)
        XCTAssertEqual(display.gasRows[0].colorRole, .danger)
    }

    func testSettingsDisplayCustomRowCaution() {
        let narrow = DiveSettingsDisplay(settings: DiveSettings(gradientFactors: .balanced),
                                         targetDepth: 30, targetDuration: 1200, estimatedNDL: 600)
        XCTAssertFalse(narrow.customRow.isCaution)

        let wide = DiveSettingsDisplay(settings: DiveSettings(gradientFactors: .init(low: 10, high: 100)),
                                       targetDepth: 30, targetDuration: 1200, estimatedNDL: 600)
        XCTAssertTrue(wide.customRow.isCaution)
        XCTAssertTrue(wide.customRow.note.contains("geniş"))
    }

    func testSettingsDisplayDeepStopRows() {
        let settings = DiveSettings(deepStops: .standard, targetDepth: 45)
        let stops = [
            DeepStopCalculator.DeepStop(depth: 12, isLive: true, roundedPressure: 2.4, holdTime: 40),
            DeepStopCalculator.DeepStop(depth: 9, isLive: false, roundedPressure: 2.0, holdTime: 0)
        ]
        let display = DiveSettingsDisplay(settings: settings, targetDepth: 45,
                                          targetDuration: 40 * 60, estimatedNDL: 0,
                                          calculatedDeepStops: stops)
        XCTAssertEqual(display.deepStopRows.count, 2)
        XCTAssertEqual(display.deepStopRows[0].depthText, "12 m")
        XCTAssertEqual(display.deepStopRows[0].holdText, "00:40")
        XCTAssertTrue(display.deepStopNote.contains("1 canlı"))
    }

    func testSettingsDisplayDisabledDeepStops() {
        let display = DiveSettingsDisplay(settings: DiveSettings(deepStops: .disabled),
                                          targetDepth: 30, targetDuration: 1200, estimatedNDL: 600)
        XCTAssertFalse(display.deepStopsEnabled)
        XCTAssertTrue(display.deepStopNote.contains("Kapalı"))
    }
}