import XCTest
@testable import DiveCore

/// Gradient Factors: interpolasyon, ön ayarlar, doğrulama.
final class GradientFactorsTests: XCTestCase {

    func testInterpolationBetweenHighAtSurfaceAndLowAtMaxDepth() {
        let gf = GradientFactors(low: 80, high: 85)

        XCTAssertEqual(gf.value(atDepth: 0, maxDepth: 30), 0.85, accuracy: 1e-9)
        XCTAssertEqual(gf.value(atDepth: 30, maxDepth: 30), 0.80, accuracy: 1e-9)
        XCTAssertEqual(gf.value(atDepth: 15, maxDepth: 30), 0.825, accuracy: 1e-9)
    }

    func testInterpolationIsClampedOutsideDiveRange() {
        let gf = GradientFactors(low: 30, high: 75)

        // Yüzeyin üstünde ve maksimum derinliğin altında uç değerler
        XCTAssertEqual(gf.value(atDepth: 0, maxDepth: 40), 0.75, accuracy: 1e-9)
        XCTAssertEqual(gf.value(atDepth: 80, maxDepth: 40), 0.30, accuracy: 1e-9)
        XCTAssertEqual(gf.value(atDepth: -10, maxDepth: 40), 0.75, accuracy: 1e-9)
    }

    func testShallowDiveWithoutMaxDepthUsesHigh() {
        let gf = GradientFactors(low: 30, high: 75)
        // Henüz dalış derinliği oluşmadıysa yalnızca GF High geçerli
        XCTAssertEqual(gf.value(atDepth: 5, maxDepth: 0), 0.75, accuracy: 1e-9)
    }

    func testUniformGradientFactors() {
        let gf = GradientFactors(uniform: 85)
        XCTAssertEqual(gf.low, 85)
        XCTAssertEqual(gf.high, 85)
        XCTAssertEqual(gf.value(atDepth: 0, maxDepth: 40), 0.85, accuracy: 1e-9)
        XCTAssertEqual(gf.value(atDepth: 40, maxDepth: 40), 0.85, accuracy: 1e-9)
    }

    func testInitializerSwapsInvertedValues() {
        // low > high verilirse normalize edilir
        let gf = GradientFactors(low: 90, high: 80)
        XCTAssertEqual(gf.low, 80)
        XCTAssertEqual(gf.high, 90)
    }

    func testOutOfRangeValuesAreClamped() {
        let gf = GradientFactors(low: 0, high: 200)
        XCTAssertEqual(gf.low, 10)
        XCTAssertEqual(gf.high, 100)
    }

    func testValidationRejectsInvalidInput() {
        XCTAssertNil(GradientFactors.validated(low: 5, high: 80))     // low < 10
        XCTAssertNil(GradientFactors.validated(low: 30, high: 120))   // high > 100
        XCTAssertNil(GradientFactors.validated(low: 80, high: 50))    // low > high
        XCTAssertEqual(GradientFactors.validated(low: 80, high: 85), GradientFactors.conservative)
    }

    func testPresets() {
        XCTAssertEqual(GradientFactors.conservative, GradientFactors(low: 80, high: 85))
        XCTAssertEqual(GradientFactors.moderate, GradientFactors(low: 50, high: 80))
        XCTAssertEqual(GradientFactors.default, GradientFactors(uniform: 100))
        XCTAssertEqual(GradientFactors.aggressive, GradientFactors(low: 30, high: 75))
    }

    func testLowerGradientFactorIsMoreConservative() {
        XCTAssertLessThan(GradientFactors.aggressive, GradientFactors.moderate)
        XCTAssertLessThan(GradientFactors.moderate, GradientFactors.conservative)
        XCTAssertLessThan(GradientFactors.conservative, GradientFactors.default)
    }

    func testDescription() {
        XCTAssertEqual(GradientFactors.conservative.description, "80/85")
    }

    func testCodableRoundTrip() throws {
        let gf = GradientFactors.moderate
        let data = try JSONEncoder().encode(gf)
        XCTAssertEqual(try JSONDecoder().decode(GradientFactors.self, from: data), gf)
    }
}