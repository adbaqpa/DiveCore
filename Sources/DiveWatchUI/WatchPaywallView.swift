#if os(watchOS)
import SwiftUI
import DiveCore

/// ADIM 1 — **watchOS Paywall**.
///
/// Küçük ekranda uzun liste okunmaz; bu yüzden:
/// - en fazla **4** özellik gösterilir (en çok istenenler),
/// - üç paket yan yana **yatay** dizilir (tek bakışta karşılaştırma),
/// - güvenlik mesajı en üstte sabit durur.
///
/// ## Güvenlik davranışı
/// Dalış sırasında paywall **asla** açılmaz: kullanıcı su altındayken
/// ekranı değiştirmek hem dikkat dağıtır hem de yanlışlıkla kaydırma
/// riski taşır. `WatchPaywallPresentation` bu kuralı uygular.
struct WatchPaywallView: View {

    let gate: FeatureGate
    var trigger: FeatureGate.PaywallTrigger = .manual
    var onPurchase: ((DiveTier) -> Void)?
    var onRestore: (() -> Void)?
    var onClose: (() -> Void)?

    /// Küçük ekranda gösterilecek en fazla özellik sayısı.
    static let maximumVisibleFeatures = 4

    @State private var selected: DiveTier = .proAnnual

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                safetyNotice
                header
                offerRow
                features
                actions
            }
            .padding(.horizontal, 4)
        }
        .background(DivePalette.surfaceBackground.ignoresSafeArea())
    }

    // MARK: - Güvenlik bildirimi

    private var safetyNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10))
                .foregroundStyle(DivePalette.color(for: .safe))
            Text(CommerceText.safetyNoticeShort)
                .font(.system(size: 10))
                .foregroundStyle(DivePalette.color(for: .secondary))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DivePalette.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Başlık

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trigger.headline)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(DivePalette.color(for: .hero))
            Text(trigger.message)
                .font(.system(size: 11))
                .foregroundStyle(DivePalette.color(for: .secondary))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Paketler

    private var offerRow: some View {
        HStack(spacing: 4) {
            ForEach([DiveTier.proMonthly, .proAnnual, .lifetime], id: \.self) { tier in
                offerChip(tier)
            }
        }
    }

    private func offerChip(_ tier: DiveTier) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { selected = tier }
        } label: {
            VStack(spacing: 2) {
                Text(tier == .lifetime ? "Ömür" : (tier == .proAnnual ? "Yıllık" : "Aylık"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                if tier == .proAnnual {
                    Text("EN İYİ")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DivePalette.color(for: .safe))
                } else {
                    Text(" ")
                        .font(.system(size: 7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected == tier
                          ? DivePalette.color(for: .accent).opacity(0.25)
                          : DivePalette.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected == tier
                                  ? DivePalette.color(for: .accent)
                                  : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(DivePalette.color(for: selected == tier ? .hero : .secondary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Özellikler

    private var features: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(visibleFeatures) { feature in
                HStack(spacing: 5) {
                    Image(systemName: feature.symbolName)
                        .font(.system(size: 11))
                        .frame(width: 14)
                    Text(feature.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DivePalette.color(for: .secondary))
            }
            let hidden = gate.lockedFeatures.count - visibleFeatures.count
            if hidden > 0 {
                Text("+ \(hidden) özellik daha")
                    .font(.system(size: 10))
                    .foregroundStyle(DivePalette.color(for: .accent))
            }
        }
    }

    /// Küçük ekranda gösterilecek özellikler (en kritikler önce).
    private var visibleFeatures: [FeatureKey] {
        let priority: [FeatureKey] = [.unlimitedLogHistory, .nitroxSupport,
                                      .advancedGradientFactors, .dataExport,
                                      .companionMap, .deepStops]
        let locked = gate.lockedFeatures
        return priority.filter { locked.contains($0) }
            .prefix(WatchPaywallView.maximumVisibleFeatures)
            .map { $0 }
    }

    // MARK: - Eylemler

    private var actions: some View {
        VStack(spacing: 4) {
            Button {
                onPurchase?(selected)
            } label: {
                Text(CommerceText.purchaseTitle(tier: selected))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .tint(DivePalette.color(for: .accent))

            HStack(spacing: 8) {
                if let onRestore {
                    Button(CommerceText.restore) { onRestore() }
                        .font(.system(size: 10))
                        .tint(DivePalette.color(for: .secondary))
                }
                if let onClose {
                    Button(CommerceText.cancel) { onClose() }
                        .font(.system(size: 10))
                        .tint(DivePalette.color(for: .secondary))
                }
            }
        }
    }
}

/// Paywall'ın **ne zaman açılabileceğini** belirleyen kural.
///
/// ## Kural
/// Dalış sürerken paywall açılmaz. Kullanıcı bu ekrana ancak
/// - yüzeyde hazırlık ekranındayken,
/// - dalış bittikten sonra özet ekranındayken,
/// - ayarlar bölümünde bir Pro özelliğine dokunduğunda
/// ulaşabilir. Bu hem dikkat dağıtmaz hem de Action Button yanlışlıkla
/// tetiklenip ekranı değiştirmez.
public enum WatchPaywallPresentation {

    /// Paywall açılmalı mı?
    ///
    /// - Parameters:
    ///   - phase: Dalışın mevcut fazı
    ///   - isDiving: Oturum çalışıyor mu
    ///   - trigger: Tetikleyen özellik (nil = manuel açılış)
    public static func shouldPresent(phase: DivePhase,
                                     isDiving: Bool,
                                     trigger: FeatureGate.PaywallTrigger?) -> Bool {
        // Tetik yoksa paywall açılmaz
        guard let trigger else { return false }
        // Dalış sırasında **hiçbir** koşulda açılmaz
        guard !isDiving || !phase.isDiving else { return false }
        return true
    }

    /// Dalış sırasında bir Pro özelliğine dokunulursa ne gösterilir?
    ///
    /// - Returns: kullanıcıya gösterilecek bilgilendirme metni.
    public static func blockedDuringDiveMessage(for feature: FeatureKey) -> String {
        "Dalış sırasında \(feature.title) açılamaz. Yüzeye döndüğünüzde "
        + "Pro özelliklerini açabilirsiniz."
    }
}
#endif
