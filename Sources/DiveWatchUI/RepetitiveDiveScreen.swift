#if os(watchOS)
import SwiftUI
import DiveCore

/// **ADIM 8 — Tekrar Dalış Hesaplayıcısı** ekranı.
///
/// Bir önceki dalıştan kalan gaz yüküyle, planlanan derinlik ve süredeki
/// dalışın sonucunu *önceden* gösterir: gerçekçi NDL, zorunlu deko planı,
/// dalış sonundaki uçuş yasağı ve önerilen gaz.
///
/// Tüm hesaplar `DiveCore` içindedir; ekran yalnızca `RepetitiveDiveDisplay`
/// verisini biçimlendirir.
struct RepetitiveDiveScreen: View {

    /// Artık doku durumu (yüzey aralığı yöneticisinden gelir)
    let tissues: TissueModel
    /// Seçili kabin profili
    var cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel

    @State private var targetDepth: Double = 30
    @State private var plannedMinutes: Double = 20

    /// Hesaplanmış sonuç.
    private var result: RepetitiveDiveCalculator.Result {
        RepetitiveDiveCalculator.calculate(
            tissues: tissues,
            targetDepth: targetDepth,
            plannedDuration: plannedMinutes * 60,
            gradientFactors: .conservative,
            gas: .air,
            water: .salt)
    }

    /// Ekran verisi.
    private var display: RepetitiveDiveDisplay {
        RepetitiveDiveDisplay(
            result: result,
            cabinNoFly: FlightAltitudeCalculator.noFlyTime(
                tissues: result.endTissues, cabin: cabin),
            cabinTitle: cabin.title)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                depthPicker
                durationPicker
                ndlComparison
                if display.hasDecoRows { decoSection }
                gasSection
                flightSection
                warningsSection
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.surfaceBackground.ignoresSafeArea())
    }

    // MARK: - Başlık

    private var header: some View {
        HStack {
            Text("TEKRAR DALIŞ")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DivePalette.secondaryText)
            Spacer()
            Text(display.gf99Label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DivePalette.secondaryText)
        }
    }

    // MARK: - Girişler

    private var depthPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hedef derinlik \(display.targetDepthText)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DivePalette.primaryText)
            Slider(value: $targetDepth, in: 6...60, step: 1)
                .tint(DivePalette.accent)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Planlı süre \(display.plannedDurationText)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DivePalette.primaryText)
            Slider(value: $plannedMinutes, in: 5...60, step: 1)
                .tint(DivePalette.accent)
        }
    }

    // MARK: - NDL

    private var ndlComparison: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                label("Kalan NDL", display.effectiveNDLText)
                Spacer()
                label("Taze NDL", display.freshNDLText)
            }
            if display.showsResidualPenalty {
                Text("Artık yük nedeniyle \(display.lossText)")
                    .font(.system(size: 11))
                    .foregroundStyle(DivePalette.cautionText)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Deko

    private var decoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.decoStatusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DivePalette.primaryText)
            ForEach(display.decoRows) { row in
                HStack {
                    Text(row.depthText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Spacer()
                    Text(row.durationText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text(row.isSafetyStop ? "opsiyonel" : row.gasLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(DivePalette.secondaryText)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Gaz

    private var gasSection: some View {
        HStack {
            label("Önerilen gaz", display.gasLabel)
            Spacer()
            Text(display.gasModText)
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.secondaryText)
        }
    }

    // MARK: - Uçuş

    private var flightSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            label("Uçuş yasağı", display.noFlyText)
            Text(display.noFlyCabinText)
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.secondaryText)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Uyarılar

    @ViewBuilder
    private var warningsSection: some View {
        ForEach(display.warnings, id: \.self) { warning in
            Text("! " + warning)
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.cautionText)
        }
    }

    // MARK: - Yardımcılar

    private func label(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DivePalette.primaryText)
        }
    }
}
#endif