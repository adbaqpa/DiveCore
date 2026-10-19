#if os(watchOS)
import SwiftUI
import Combine
import DiveCore
import DiveWatch

/// `DiveSessionController` → SwiftUI arasındaki köprü.
///
/// Tüm kararlar `DiveCore.Presentation` katmanında verilir; bu sınıf yalnızca
/// durumu `@Published` olarak yayınlar ve kullanıcı eylemlerini iletir.
@MainActor
public final class DiveViewModel: ObservableObject {

    // MARK: - Yayınlar

    /// Ekranda gösterilecek hazır durum (metinler, renk rolleri, göstergeler).
    @Published public private(set) var display: DiveDisplayState
    /// Dalış sonu özeti (basit hâl — ADIM 3)
    @Published public private(set) var summary: DiveSummaryDisplay?
    /// Dalış sonu raporu (zengin hâl — ADIM 4)
    @Published public private(set) var report: DiveReportDisplay?
    /// Anlık çıkış rehberi (tavan tamponu, sonraki dura)
    @Published public private(set) var guidance: GuidanceDisplay
    /// Oksijen riski kartı (PO₂ / CNS / OTU)
    @Published public private(set) var oxygen: OxygenDisplay
    /// Mevcut deko planı (hesaplandığında)
    @Published public private(set) var decoPlan: DecoPlanDisplay?
    /// Dalış öncesi ayarlar (ADIM 6)
    @Published public var settings: DiveSettings = .recreational {
        didSet { refreshSettings() }
    }
    /// Ayarlar ekranı verisi
    @Published public private(set) var settingsDisplay: DiveSettingsDisplay
    /// Su kilidi denetleyicisi (ADIM 7)
    public let lock = DiveLockController()
    /// Su atma döngüsünün kalan adı (görünüm için)
    @Published public private(set) var ejectionStep: String?
    @Published public private(set) var ejectionProgress: Double = 0
    /// Acil durum menüsü açık mı
    @Published public private(set) var isEmergencyMenuPresented = false

    /// Dalış günlüğü (ADIM 5)
    @Published public private(set) var logbook: LogbookDisplay = LogbookDisplay(
        dives: [], statistics: DiveStatistics())
    /// Son kaydedilen dalış
    @Published public private(set) var lastLog: LogEntry?

    /// Always-On Display durumu (WatchKit ortamından gelir)
    @Published public var isAlwaysOn: Bool = false

    // MARK: - Monetizasyon (ADIM 1)

    /// Özellik kapısı — hangi özelliklerin açık olduğunu belirler.
    @Published public private(set) var featureGate = FeatureGate(entitlements: .none)
    /// Etkin paywall tetiği (nil = kapalı)
    @Published public var paywallTrigger: FeatureGate.PaywallTrigger?
    /// Satın alma servisi (platform tarafından atanır; testte sahte olabilir)
    ///
    /// - Note: `DiveCommerce` yalnızca iOS/watchOS'ta derlendiği için tip
    ///   `AnyObject` olarak tutulur ve `#if` ile kullanılır.
    public weak var storeManager: AnyObject?

    /// Etkin kapsam.
    public var tier: DiveTier { featureGate.tier }

    /// Pro etkin mi?
    public var isPro: Bool { featureGate.tier.unlocksPro }

    /// Yetkileri günceller (StoreManager dinleyicisinden gelir).
    public func updateEntitlements(_ entitlements: EntitlementSet) {
        featureGate = FeatureGate(entitlements: entitlements)
        if isPro { paywallTrigger = nil }
    }

    /// Bir özelliğe erişim isteği. Kilitliyse paywall açar.
    ///
    /// - Returns: erişim verildiyse `true`.
    @discardableResult
    public func request(_ feature: FeatureKey) -> Bool {
        let decision = featureGate.decision(for: feature)
        if decision.isAllowed { return true }

        // Dalış sırasında paywall açılmaz (güvenlik + dikkat)
        let trigger = featureGate.paywallTrigger(for: feature)
        guard let trigger,
              WatchPaywallPresentation.shouldPresent(phase: state.phase,
                                                      isDiving: system.session.isRunning,
                                                      trigger: trigger) else {
            lockedFeatureNotice = feature
            return false
        }
        paywallTrigger = trigger
        return false
    }

    /// Dalış sırasında kilitli özelliğe dokunulduğunda gösterilecek uyarı.
    @Published public var lockedFeatureNotice: FeatureKey?

    /// Paywall'ı kapat.
    public func closePaywall() {
        paywallTrigger = nil
    }

    /// Günlükte görüntülenebilir dalışlar (kapsama göre kısıtlı).
    public func visibleDives() -> [LoggedDive] {
        featureGate.visibleDives(logbook.dives)
    }

    /// Gizli dalış sayısı (rozet için).
    public var hiddenDiveCount: Int {
        featureGate.hiddenDiveCount(total: logbook.diveCount)
    }

    // MARK: - Enerji (ADIM 11)

    /// Enerji yöneticisi — tema, profil ve öneriler
    @Published public private(set) var energy = EnergyManager()
    /// Aktif ekran teması (kırmızı gece modu dâhil)
    @Published public private(set) var theme: DiveDisplayTheme = .standard
    /// Aktif önerilen sensör örnekleme aralığı (saniye)
    @Published public private(set) var samplingInterval: TimeInterval = 1

    // MARK: - Sistem

    private let system: DiveSystem
    private var cancellables = Set<AnyCancellable>()

    /// Kalıcılık + senkronizasyon servisi
    public let logbookService: DiveLogbook

    /// Dalış sonrası uygulanacak kalıcılık eylemi (varsayılan: kaydet)
    public var onDiveEnded: ((LogEntry, DiveReport) -> Void)?

    /// Action Button'ın o anki niyeti.
    public var actionIntent: DiveActionIntent {
        DiveActionButtonResolver.intent(for: system.session.state,
                                        isDiving: system.session.isRunning)
    }

    /// İkincil eylem (bitir).
    public var secondaryIntent: DiveActionIntent {
        DiveActionButtonResolver.secondaryIntent(for: system.session.state,
                                                 isDiving: system.session.isRunning)
    }

    public var state: DiveState { system.session.state }

    public init(system: DiveSystem = DiveSystem(configuration: .recreational),
                logbook: DiveLogbook? = nil) {
        self.system = system
        self.logbookService = logbook ?? DiveLogbook(store: InMemoryDiveLogStore())
        self.display = DiveDisplayBuilder.build(from: system.session.state)
        self.settingsDisplay = DiveSettingsDisplay(settings: .recreational,
                                                   targetDepth: 30, targetDuration: 20 * 60,
                                                   estimatedNDL: 0)
        self.guidance = GuidanceDisplay(guidance: system.session.guidance)
        self.oxygen = OxygenDisplay(status: system.session.oxygenStatus)

        system.session.onStateChange = { [weak self] state in
            guard let self else { return }
            // ADIM 11: tema ve örnekleme aralığı duruma göre güncellenir
            self.energy.update(state: EnergyState(
                batteryLevel: self.energy.state.batteryLevel,
                isLowPowerModeEnabled: self.energy.state.isLowPowerModeEnabled,
                thermalState: self.energy.state.thermalState,
                isAlwaysOn: self.isAlwaysOn,
                theme: self.energy.state.theme,
                isDiving: state.phase.isDiving,
                profile: self.settings.powerProfile))
            self.theme = self.energy.theme
            self.samplingInterval = self.energy.recommendedInterval
            let newDisplay = DiveDisplayBuilder.build(from: state,
                                                      isAlwaysOn: self.isAlwaysOn,
                                                      theme: self.energy.theme)
            if newDisplay != self.display {
                self.display = newDisplay
            }
            // ADIM 4: rehber ve oksijen kartı yalnızca yükselen/dipte
            // fazlarında anlamlıdır; her saniye yeniden hesaplanır.
            self.guidance = GuidanceDisplay(guidance: self.system.session.guidance)
            self.oxygen = OxygenDisplay(status: self.system.session.oxygenStatus)
            if state.phase == .surfaced, self.summary == nil {
                self.refreshLogbook()
                self.summary = DiveSummaryDisplay(state: state)
                self.report = DiveReportDisplay(report: self.system.session.makeReport())
            }
        }
    }

    /// AOD durumu değiştiğinde çağrılır (görünüm `onChange` ile bağlar).
    public func updateAlwaysOn(_ value: Bool) {
        guard value != isAlwaysOn else { return }
        isAlwaysOn = value
        refreshEnergy()
    }

    // MARK: - Monetizasyon (ADIM 1)

    /// Özellik kapısı — hangi özelliklerin açık olduğunu belirler.
    @Published public private(set) var featureGate = FeatureGate(entitlements: .none)
    /// Etkin paywall tetiği (nil = kapalı)
    @Published public var paywallTrigger: FeatureGate.PaywallTrigger?
    /// Satın alma servisi (platform tarafından atanır; testte sahte olabilir)
    ///
    /// - Note: `DiveCommerce` yalnızca iOS/watchOS'ta derlendiği için tip
    ///   `AnyObject` olarak tutulur ve `#if` ile kullanılır.
    public weak var storeManager: AnyObject?

    /// Etkin kapsam.
    public var tier: DiveTier { featureGate.tier }

    /// Pro etkin mi?
    public var isPro: Bool { featureGate.tier.unlocksPro }

    /// Yetkileri günceller (StoreManager dinleyicisinden gelir).
    public func updateEntitlements(_ entitlements: EntitlementSet) {
        featureGate = FeatureGate(entitlements: entitlements)
        if isPro { paywallTrigger = nil }
    }

    /// Bir özelliğe erişim isteği. Kilitliyse paywall açar.
    ///
    /// - Returns: erişim verildiyse `true`.
    @discardableResult
    public func request(_ feature: FeatureKey) -> Bool {
        let decision = featureGate.decision(for: feature)
        if decision.isAllowed { return true }

        // Dalış sırasında paywall açılmaz (güvenlik + dikkat)
        let trigger = featureGate.paywallTrigger(for: feature)
        guard let trigger,
              WatchPaywallPresentation.shouldPresent(phase: state.phase,
                                                      isDiving: system.session.isRunning,
                                                      trigger: trigger) else {
            lockedFeatureNotice = feature
            return false
        }
        paywallTrigger = trigger
        return false
    }

    /// Dalış sırasında kilitli özelliğe dokunulduğunda gösterilecek uyarı.
    @Published public var lockedFeatureNotice: FeatureKey?

    /// Paywall'ı kapat.
    public func closePaywall() {
        paywallTrigger = nil
    }

    /// Günlükte görüntülenebilir dalışlar (kapsama göre kısıtlı).
    public func visibleDives() -> [LoggedDive] {
        featureGate.visibleDives(logbook.dives)
    }

    /// Gizli dalış sayısı (rozet için).
    public var hiddenDiveCount: Int {
        featureGate.hiddenDiveCount(total: logbook.diveCount)
    }

    // MARK: - Enerji (ADIM 11)

    /// Cihaz enerji durumu değiştiğinde adaptörden çağrılır.
    public func updateEnergyState(_ state: EnergyState) {
        energy.update(state: state)
        theme = energy.theme
        samplingInterval = energy.recommendedInterval
        refreshDisplay()
    }

    /// Enerji profili değişti.
    public func setPowerProfile(_ profile: PowerProfile) {
        settings.powerProfile = profile
        energy.setProfile(profile)
        refreshEnergy()
    }

    /// Gece modu tercihi değişti.
    public func setNightMode(_ preference: EnergyManager.NightModePreference) {
        settings.nightModePreference = preference
        energy.setNightMode(preference)
        refreshEnergy()
        refreshSettings()
    }

    /// AOD tercihi değişti — AOD kapalıysa tema zorlanmaz.
    public func setAlwaysOnEnabled(_ enabled: Bool) {
        settings.allowsAlwaysOnDisplay = enabled
        refreshEnergy()
    }

    /// Enerji durumunu dalış durumu ve ayarlarla birlikte yeniden çözer.
    private func refreshEnergy() {
        let aodActive = isAlwaysOn && settings.allowsAlwaysOnDisplay
        energy.update(state: EnergyState(
            batteryLevel: energy.state.batteryLevel,
            isLowPowerModeEnabled: energy.state.isLowPowerModeEnabled,
            thermalState: energy.state.thermalState,
            isAlwaysOn: aodActive,
            theme: energy.state.theme,
            isDiving: system.session.state.phase.isDiving,
            profile: settings.powerProfile))
        theme = energy.theme
        samplingInterval = energy.recommendedInterval
        system.updateEnergy(energy.state, profile: energy.profile)
        refreshDisplay()
    }

    private func refreshDisplay() {
        let aodActive = isAlwaysOn && settings.allowsAlwaysOnDisplay
        display = DiveDisplayBuilder.build(from: system.session.state,
                                           isAlwaysOn: aodActive,
                                           theme: energy.theme)
    }

    // MARK: - Komplikasyon verisi

    /// Saat yüzü komplikasyonu için veri üretir.
    public func complicationData(for style: DiveComplicationData.Style) -> DiveComplicationData {
        DiveComplicationBuilder.build(from: system.session.state, style: style)
    }

    // MARK: - Yaşam döngüsü

    public func startDive(scenario: DiveScenario? = nil) throws {
        // Ayarlar oturuma uygulanır (GF + gaz planı)
        system.reconfigure(settings.configuration())
        lock.onDiveStarted()
        ejectionStep = nil
        ejectionProgress = 0
        summary = nil
        report = nil
        decoPlan = nil
        lastLog = nil
        try system.startDive(scenario: scenario)
        display = DiveDisplayBuilder.build(from: system.session.state, isAlwaysOn: isAlwaysOn)
    }

    @discardableResult
    public func endDive() -> LogEntry? {
        // Su atma döngüsü başlar (kilit, döngü bitene kadar açık kalır)
        let steps = lock.onDiveEnded()
        startEjection(steps)
        let log = system.endDive()
        lastLog = log
        if let log {
            summary = DiveSummaryDisplay(state: system.session.state, log: log)
            report = DiveReportDisplay(report: system.session.makeReport(log: log))
            refreshDecoPlan()
        }
        return log
    }

    // MARK: - Kullanıcı eylemleri

    /// Action Button basıldığında niyeti yürütür.
    @discardableResult
    public func performActionIntent() -> DiveActionButtonResolver.Outcome {
        switch actionIntent {
        case .startDive:
            try? system.startDive(scenario: DiveScenario.recreational30m)
            return .started
        case .placeMarker:
            system.addMarker()
            return .markerAdded
        case .acknowledgeAlarm:
            system.acknowledgeAlarm()
            return .alarmAcknowledged
        case .endDive, .none:
            return .ignored
        }
    }

    public func performSecondaryIntent() -> DiveActionButtonResolver.Outcome {
        guard secondaryIntent == .endDive else { return .ignored }
        _ = endDive()
        return .ended
    }

    // MARK: - Acil durum (ADIM 7)

    /// Action Button **basılı tutma**: acil durum menüsünü açar.
    @discardableResult
    public func performEmergencyIntent() -> DiveActionButtonResolver.Outcome {
        isEmergencyMenuPresented = true
        return .alarmAcknowledged
    }

    /// Acil durum menüsündeki bir eylemi çalıştırır.
    public func perform(_ action: DiveLockController.ButtonAction) {
        switch action {
        case .startSafetyStop:
            guidance = GuidanceDisplay(guidance: AscentAdvisor(safetyStopDepth: settings.gasPlan.water == .salt ? 5 : 5)
                .evaluate(system.session.state))
        case .ascentAssist:
            system.addMarker(label: "Çıkış yardımı istendi")
            refreshDecoPlan()
        case .endDive:
            _ = endDive()
        case .openEmergencyMenu, .placeMarker, .startDive, .acknowledgeAlarm, .none:
            break
        }
        isEmergencyMenuPresented = false
    }

    // MARK: - Su kilidi / su atma (ADIM 7)

    /// Su atma döngüsünü başlatır (ses/titreşim sırası).
    private func startEjection(_ steps: [DiveLockController.EjectionStep]) {
        guard !steps.isEmpty else {
            lock.onEjectionCompleted()
            return
        }
        var delay: TimeInterval = 0
        for (index, step) in steps.enumerated() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self.ejectionStep = step.name
                self.ejectionProgress = Double(index + 1) / Double(steps.count)
                self.system.acknowledgeAlarm()   // titreşim/ses üretir
            }
            delay += step.delay
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.ejectionStep = nil
            self.ejectionProgress = 0
            self.lock.onEjectionCompleted()
        }
    }

    /// Ayarlar ekranı verisini yeniler (GF önerisi + NDL tahmini).
    public func refreshSettings() {
        let engine = DecoEngine(gradientFactors: settings.gradientFactors,
                                gases: settings.gasPlan.cylinders.map(\.gas),
                                gasCylinderIndex: 0)
        settingsDisplay = DiveSettingsDisplay(
            settings: settings,
            targetDepth: settings.targetDepth,
            targetDuration: settings.targetDuration,
            estimatedNDL: engine.noDecompressionLimit(atDepth: settings.targetDepth),
            calculatedDeepStops: deepStopsPreview(engine: engine))
    }

    /// Derin durak önizlemesi (canlı hesap — hızlı, 10 sn çözünürlük).
    private func deepStopsPreview(engine: DecoEngine) -> [DeepStopCalculator.DeepStop] {
        guard settings.deepStops.isEnabled else { return [] }
        let simulator = DiveSimulator(scenario: DiveScenario(name: "önizleme", segments: [
            .descent(to: settings.targetDepth, at: 15),
            .hover(at: settings.targetDepth, for: settings.targetDuration)
        ]))
        var preview = engine
        for reading in simulator.readings.dropFirst() {
            preview.update(toDepth: reading.depth, duration: 1, gas: settings.gasPlan.startGas)
        }
        return DeepStopCalculator.deepStops(
            tissues: preview.tissues,
            maxDepth: preview.tissues.maxDepth,
            firstDecoStopDepth: TissueModel.roundToStopInterval(
                preview.ceiling(atDepth: settings.targetDepth).depthMeters),
            settings: settings.deepStops)
    }

    /// Deko planını yeniden hesaplar (yükseliş sırasında çağrılır).
    public func refreshDecoPlan() {
        decoPlan = DecoPlanDisplay(plan: system.session.decoPlan())
    }

    /// Dalış bittiğinde deftere kaydeder (ADIM 5).
    @discardableResult
    public func archive(_ log: LogEntry) -> LoggedDive? {
        guard let report = system.session.lastReport else { return nil }
        let dive = try? logbookService.add(log: log, report: report)
        refreshLogbook()
        return dive
    }

    /// Senkronizasyonu tetikler ve defteri yeniler.
    public func syncNow() {
        logbookService.syncNow()
        refreshLogbook()
    }

    /// Günlük toplamlarla birlikte defter ekranını yeniler.
    public func refreshLogbook() {
        logbook = logbookService.display()
    }

    public func switchGas(to index: Int) {
        system.switchGas(to: index)
        display = DiveDisplayBuilder.build(from: system.session.state, isAlwaysOn: isAlwaysOn)
    }
}
#endif