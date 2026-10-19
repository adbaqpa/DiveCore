import Foundation

/// ADIM 9 — komplikasyon zaman çizelgesi (WidgetKit `TimelineProvider` çekirdeği).
///
/// watchOS komplikasyonları anlık veri çekmez; sistem onlara **zaman
/// çizelgesi** verir ve bir sonraki güncellemeyi uygulamanın belirlediği
/// tarihe planlar. Bu yüzden:
///
/// 1. Her giriş noktasında bir **veri örneği** (`Entry`) üretilir,
/// 2. Sonraki yenileme tarihi **uçuş yasağı geri sayımına** göre seçilir,
/// 3. Kaç giriş üretileceği pil bütçesiyle sınırlıdır.
///
/// Yenileme tarihi `BackgroundMonitoringPolicy` ile aynı mantığı paylaşır;
/// böylece "arka planda kaç kez uyanacağız" sorusunun tek cevabı olur.
public enum DiveComplicationTimeline {

    /// Tek bir zaman çizelgesi girişi.
    public struct Entry: Equatable, Codable, Sendable, Identifiable {
        public let date: Date
        public let data: DiveComplicationData
        public var id: Date { date }
        /// WidgetKit'in geri sayım metni (yüzey modlarında kullanılır)
        public let countdownText: String?

        public init(date: Date, data: DiveComplicationData, countdownText: String? = nil) {
            self.date = date
            self.data = data
            self.countdownText = countdownText
        }
    }

    /// Bir komplikasyon tanımı (hangi mod, hangi stil).
    public struct Request: Equatable, Codable, Sendable {
        public let mode: DiveComplicationMode
        public let style: DiveComplicationData.Style

        public init(mode: DiveComplicationMode, style: DiveComplicationData.Style) {
            self.mode = mode
            self.style = style
        }

        /// Sık kullanılan dört kurulum.
        public static let presets: [Request] = [
            Request(mode: .liveDepth, style: .circular),
            Request(mode: .liveNDL, style: .rectangular),
            Request(mode: .noFly, style: .circular),
            Request(mode: .surfaceInterval, style: .inline)
        ]
    }

    /// Maksimum giriş sayısı (WidgetKit'in kabul ettiği sınır).
    public static let maximumEntries = 24

    /// Zaman çizelgesini üretir.
    ///
    /// - Parameters:
    ///   - state: Anlık dalış durumu
    ///   - isDiving: Dalış sürüyor mu
    ///   - status: Yüzey aralığı durumu (yüzey modları için)
    ///   - request: Mod + stil
    ///   - now: Başlangıç zamanı
    ///   - policy: Yenileme politikası
    ///   - cabin: Kabin profili
    /// - Returns: Tarih sırasıyla ilerleyen girişler (daima `now` içerir).
    public static func makeEntries(state: DiveState,
                                   isDiving: Bool,
                                   status: SurfaceIntervalStatus?,
                                   request: Request,
                                   now: Date = Date(),
                                   policy: BackgroundMonitoringPolicy = .standard,
                                   cabin: FlightAltitudeCalculator.CabinProfile = .seaLevel) -> [Entry] {
        func makeEntry(at date: Date) -> Entry {
            // Yüzeydeyse durum, uçuş yasağı bitimine doğru **doğrusal** olarak
            // ilerletilir. Bu bir yeniden simülasyon değildir; yalnızca
            // komplikasyonun geri sayımını zamanla eşleştirmek içindir
            // (DiveCore'daki gerçek hesap `SurfaceIntervalManager` ile yapılır).
            let projected = status?.projected(to: date)
            let data = DiveComplicationBuilder.build(mode: request.mode,
                                                     state: state,
                                                     isDiving: isDiving,
                                                     style: request.style,
                                                     status: projected,
                                                     cabin: cabin)
            // Geri sayım metni yalnızca yüzey modlarında anlamlıdır;
            // dalış sırasında komplikasyon canlı veriyi gösterir.
            let countdown = (isDiving && state.phase.isDiving) ? nil
                : projected.map { DurationFormatter.clock($0.noFlyRemaining) }
            return Entry(date: date, data: data, countdownText: countdown)
        }

        var entries: [Entry] = [makeEntry(at: now)]

        // Dalış sırasında veri anlıktır; kısa bir ileri bakış yeterlidir.
        if isDiving && state.phase.isDiving {
            for step in 1...3 {
                entries.append(makeEntry(at: now.addingTimeInterval(Double(step) * 60)))
            }
            return entries
        }

        // Yüzeyde: geri sayımın sonuna doğru seyrek girişler.
        guard let status, !status.isNoFlyCleared, status.noFlyRemaining > 0 else {
            return entries
        }

        var used = 0
        var cursor = now
        while entries.count < maximumEntries && used < policy.maximumChecks {
            let remaining = status.noFlyRemaining - cursor.timeIntervalSince(now)
            guard remaining > 0 else { break }
            let interval = policy.checkInterval(remaining: remaining, usedChecks: used)
            guard interval < remaining else { break }
            cursor = cursor.addingTimeInterval(interval)
            // Son giriş uçuş yasağı bitimini aşmamalı
            guard cursor.timeIntervalSince(now) < status.noFlyRemaining else { break }
            entries.append(makeEntry(at: cursor))
            used += 1
        }
        return entries
    }

    /// Bir sonraki yenileme tarihi (sistem bunu kullanır).
    ///
    /// - Note: Uçuş yasası yoksa `nil` döner — WidgetKit'in "gelecekte
    ///   güncelle" tanımıdır ve pil dostudur.
    public static func nextRefreshDate(state: DiveState,
                                       isDiving: Bool,
                                       status: SurfaceIntervalStatus?,
                                       now: Date = Date(),
                                       policy: BackgroundMonitoringPolicy = .standard,
                                       minimumInterval: TimeInterval = 60) -> Date? {
        if isDiving && state.phase.isDiving {
            return now.addingTimeInterval(minimumInterval)
        }
        guard let status, !status.isNoFlyCleared, status.noFlyRemaining > 0 else { return nil }
        let interval = max(minimumInterval, policy.checkInterval(remaining: status.noFlyRemaining))
        return now.addingTimeInterval(min(interval, status.noFlyRemaining))
    }
}
