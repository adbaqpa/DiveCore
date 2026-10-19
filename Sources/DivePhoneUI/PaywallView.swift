#if os(iOS)
import SwiftUI
import DiveCore
import DiveCommerce

/// ADIM 1 — **Paywall** (satın alma ekranı).
///
/// ## Tasarım ilkeleri
/// - **Önce değer, sonra fiyat** — ekranın üst 2/3'ü özelliklerden oluşur,
///   fiyat en altta ve küçüktür. Apple'ın "değeri önce göster" rehberi.
/// - **Vurgulanan tek seçenek** — yıllık abonelik önerilir; abonelik
///   gelirinin büyük kısmı yıllıktan gelir.
/// - **Güvenlik vurgusu** — üst bantta "güvenlik özellikleri her zaman ücretsiz"
///   mesajı vardır; bu hem kullanıcıyı rahatlatır hem App Store incelemesinde
///   doğru sinyali verir.
/// - **Yeniden mimarlama yok** — sayfa açılırken seçim değişmez, fiyat
///   güncellenir; kullanıcı "hangi paket?" diye düşünmez.
struct PaywallView: View {

    /// Özellik kapısı
    let gate: FeatureGate
    /// Satın alma servisi
    let store: StoreManager
    /// Paywall'ı neyin açtığı (başlık değişir)
    var trigger: FeatureGate.PaywallTrigger = .manual
    /// Kapatma düğmesi
    var onClose: (() -> Void)?

    @State private var selected: DiveTier = .proAnnual
    @State private var showingRestore = false
    @State private var showingTerms = false
    @State private var hasAppeared = false

    init(gate: FeatureGate,
         store: StoreManager,
         trigger: FeatureGate.PaywallTrigger = .manual,
         onClose: (() -> Void)? = nil) {
        self.gate = gate
        self.store = store
        self.trigger = trigger
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    safetyBanner
                    hero
                    featureList
                    offerCards
                    purchaseButton
                    restoreButton
                    legalFooter
                }
                .padding(20)
            }
            .background(background)
            .navigationTitle("DiveLog Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat", action: onClose)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Geri Yükle") { showingRestore = true }
                        .font(.footnote)
                }
            }
            .task { await loadOnce() }
            .alert("Satın Alınamadı", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) { store.clearError() }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .sheet(isPresented: $showingTerms) { legalSheet }
        }
    }

    // MARK: - Güvenlik bandı

    private var safetyBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            Text("Dekompresyon, alarm ve emniyet durakları **her zaman ücretsiz**. "
                 + "Pro yalnızca analiz, ayar ve dışa aktarma özelliklerini açar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Başlık

    private var hero: some View {
        VStack(spacing: 6) {
            Text(trigger.headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(trigger.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: - Özellik listesi

    private var featureList: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(FeatureKey.Group.allCases, id: \.self) { group in
                let features = FeatureKey.allCases.filter {
                    $0.group == group && $0.isLocked(in: gate.tier)
                }
                if !features.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(features) { feature in
                            FeatureRow(feature: feature)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Paket seçimi

    private var offerCards: some View {
        VStack(spacing: 10) {
            ForEach(offerings) { offering in
                OfferCard(
                    offering: offering,
                    priceText: priceText(for: offering.tier),
                    isSelected: selected == offering.tier,
                    isPurchasing: store.isPurchasing
                ) {
                    withAnimation(.snappy) { selected = offering.tier }
                }
            }
        }
    }

    private var offerings: [ProductCatalog.Offering] {
        store.offerings()
    }

    // MARK: - Satın alma

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack {
                if store.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "lock.fill")
                }
                Text(buttonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.cyan)
        .disabled(store.isPurchasing || priceText(for: selected) == nil)
    }

    private var buttonTitle: String {
        guard let price = priceText(for: selected) else { return "Fiyat yükleniyor…" }
        return selected == .lifetime ? "Ömür Boyu Satın Al · \(price)"
                                     : "\(selected.title) Abonelik · \(price)"
    }

    private func purchase() async {
        let ok = await store.purchase(tier: selected)
        if ok { onClose?() }
    }

    // MARK: - Alt bilgi

    private var restoreButton: some View {
        Button {
            Task {
                await store.restore()
                if !store.entitlements.isEmpty { onClose?() }
            }
        } label: {
            Text(store.isRestoring ? "Geri yükleniyor…" : "Satın Alınanları Geri Yükle")
                .font(.footnote)
        }
        .disabled(store.isRestoring)
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            if selected.isSubscription {
                Text("Abonelik, seçtiğiniz süre boyunca otomatik yenilenir. "
                     + "Apple Hesabı Ayarları › Abonelikler'den istediğiniz zaman iptal edebilirsiniz. "
                     + "İptal, mevcut dönemin sonunda geçerli olur.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Tek seferlik ödemedir; yenilenmez ve iade edilmez.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Kullanım Koşulları ve Gizlilik Politikası") { showingTerms = true }
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Yardımcılar

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.02, green: 0.09, blue: 0.14),
                                Color(red: 0.01, green: 0.03, blue: 0.05)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private func priceText(for tier: DiveTier) -> String? {
        guard let product = store.product(for: tier) else { return nil }
        return product.displayPrice
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil },
                set: { if !$0 { store.clearError() } })
    }

    private func loadOnce() async {
        guard !hasAppeared else { return }
        hasAppeared = true
        selected = ProductCatalog.recommendedOffering().tier
        await store.bootstrap()
    }

    private var legalSheet: some View {
        NavigationStack {
            ScrollView {
                Text(LegalText.termsAndPrivacy)
                    .font(.footnote)
                    .padding()
            }
            .navigationTitle("Yasal Metinler")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Alt görünümler

/// Özellik satırı.
private struct FeatureRow: View {
    let feature: FeatureKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feature.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.medium))
                Text(feature.benefit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Paket kartı.
private struct OfferCard: View {
    let offering: ProductCatalog.Offering
    let priceText: String?
    let isSelected: Bool
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .cyan : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(offering.title)
                            .font(.headline)
                        if let badge = offering.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.2), in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                    }
                    Text(offering.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(priceText ?? "—")
                        .font(.headline)
                    if let equivalent = offering.equivalentMonthlyPrice {
                        Text(equivalent)
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.cyan : Color.white.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }
}
#endif
