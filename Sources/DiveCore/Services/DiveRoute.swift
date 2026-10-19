import Foundation

/// Coğrafi koordinat — `CoreLocation`'dan bağımsız, test edilebilir tip.
///
/// `CLLocationCoordinate2D` bir yapı (struct) olduğu için `Equatable` uyumlu
/// değildir ve iOS dışında kullanılamaz. Bu yüzden çekirdekte kendi tipimiz
/// var; `DivePhone` katmanı bunu `CLLocationCoordinate2D`'ye çevirir.
public struct DiveCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Geçerli bir koordinat mı? (enlem ±90, boylam ±180)
    public var isValid: Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }

    /// Yaklaşık noktasal mesafe (metre) — Haversine.
    public func distance(to other: DiveCoordinate) -> Double {
        DiveRoute.haversine(self, other)
    }
}

/// ADIM 10 — dalış GPS rotası.
///
/// ## Veri kaynağı
/// Apple Watch'ta **yüzeyde** CoreLocation konumu alınır; su altında GPS
/// çözünürlüğü kötüdür ve batarya tüketir. Bu nedenle rota, yüzey
/// bölümlerinden (giriş, ara durak, çıkış) oluşan bir çizgi olarak
/// gösterilir; su altı örnekler konumsuzdur.
///
/// ## Hesaplanan büyüklükler
/// - Toplam ve segment mesafeleri (Haversine, orta dünya yarıçapı),
/// - Sürüklenme (GPS hatası) göstergesi: ölçülen mesafe / düz mesafe,
/// - Harita için `region` (merkez + sapma) — `MKCoordinateRegion` dönüşümü
///   iOS katmanında yapılır, hesap burada.
public struct DiveRoute: Codable, Equatable, Sendable {

    /// Rotadaki tek bir konum örneği.
    public struct Point: Codable, Equatable, Sendable, Identifiable {
        public let id: Int
        /// Dalış başlangıcından itibaren geçen süre (saniye)
        public let elapsed: TimeInterval
        public let coordinate: DiveCoordinate
        /// Derinlik (m) — yüzey örneklerinde 0
        public let depth: Double
        /// Sıcaklık (°C)
        public let temperature: Double
        /// Yatay hız (m/s) — önceki noktadan
        public let speed: Double

        public init(id: Int, elapsed: TimeInterval, coordinate: DiveCoordinate,
                    depth: Double, temperature: Double, speed: Double) {
            self.id = id
            self.elapsed = elapsed
            self.coordinate = coordinate
            self.depth = depth
            self.temperature = temperature
            self.speed = speed
        }
    }

    public let points: [Point]
    /// Dalış başlangıç tarihi (zaman etiketleri için)
    public let startDate: Date

    public init(points: [Point], startDate: Date) {
        self.points = points
        self.startDate = startDate
    }

    // MARK: - Kurulum

    /// `DiveSample` dizisinden rota oluşturur (konumu olan örnekler kullanılır).
    ///
    /// - Parameters:
    ///   - samples: Dalış örnekleri
    ///   - startDate: Dalış başlangıcı
    ///   - minimumSpacing: Ardışık noktalar arası en küçük mesafe (m).
    ///     GPS dalgalanmalarını (1-3 m) gürültü olarak ayıklar.
    public init(samples: [DiveSample], startDate: Date, minimumSpacing: Double = 5) {
        var result: [Point] = []
        var previous: DiveCoordinate?

        for sample in samples {
            guard let lat = sample.latitude, let lon = sample.longitude else { continue }
            let coordinate = DiveCoordinate(latitude: lat, longitude: lon)
            guard coordinate.isValid else { continue }

            if let previous {
                let gap = DiveRoute.haversine(previous, coordinate)
                guard gap >= minimumSpacing else { continue }
            }

            let speed: Double
            if let previous, let last = result.last {
                let gap = DiveRoute.haversine(previous, coordinate)
                let dt = max(0.001, sample.elapsed - last.elapsed)
                speed = gap / dt
            } else {
                speed = 0
            }

            result.append(Point(id: result.count,
                                elapsed: sample.elapsed,
                                coordinate: coordinate,
                                depth: sample.depth,
                                temperature: sample.temperature,
                                speed: speed))
            previous = coordinate
        }
        self.init(points: result, startDate: startDate)
    }

    // MARK: - Boş durum

    public static let empty = DiveRoute(points: [], startDate: Date(timeIntervalSince1970: 0))

    public var isEmpty: Bool { points.count < 2 }
    public var pointCount: Int { points.count }

    // MARK: - Mesafe

    /// Toplam rota uzunluğu (metre).
    public var totalDistance: Double {
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for index in 1..<points.count {
            sum += DiveRoute.haversine(points[index - 1].coordinate, points[index].coordinate)
        }
        return sum
    }

    /// İki nokta arası düz mesafe (metre) — sürüklenme karşılaştırması için.
    public var straightLineDistance: Double {
        guard points.count >= 2 else { return 0 }
        return DiveRoute.haversine(points[0].coordinate, points[points.count - 1].coordinate)
    }

    /// Sürüklenme oranı: ölçülen mesafe / düz mesafe. 1'e yakınsa rota düzgündür.
    public var driftRatio: Double {
        let straight = straightLineDistance
        guard straight > 1 else { return 1 }
        return totalDistance / straight
    }

    /// Ortalama yüzey hızı (m/s).
    public var averageSpeed: Double {
        guard let last = points.last, let first = points.first else { return 0 }
        let dt = max(0.001, last.elapsed - first.elapsed)
        return totalDistance / dt
    }

    // MARK: - Harita bölgesi

    /// Harita merkezi.
    public var center: DiveCoordinate? {
        guard !points.isEmpty else { return nil }
        let lat = points.map { $0.coordinate.latitude }.reduce(0, +) / Double(points.count)
        let lon = points.map { $0.coordinate.longitude }.reduce(0, +) / Double(points.count)
        return DiveCoordinate(latitude: lat, longitude: lon)
    }

    /// Enlem/boylam sınırları.
    public var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let first = points.first else { return nil }
        var minLat = first.coordinate.latitude, maxLat = minLat
        var minLon = first.coordinate.longitude, maxLon = minLon
        for point in points.dropFirst() {
            minLat = min(minLat, point.coordinate.latitude)
            maxLat = max(maxLat, point.coordinate.latitude)
            minLon = min(minLon, point.coordinate.longitude)
            maxLon = max(maxLon, point.coordinate.longitude)
        }
        return (minLat, maxLat, minLon, maxLon)
    }

    /// Harita görünümü için `delta` (derece cinsinden sapma) ve merkez.
    ///
    /// - Note: `MKMapRect` benzeri bir yakınlaştırma üretmek için
    ///   `MKCoordinateRegion(center:span:)` kullanılır; `span` = delta/2.
    ///   Dünya sınırına (180°) yakın rotalarda sapma en fazla 180 olur.
    public func mapRegion(padding: Double = 1.4) -> (center: DiveCoordinate, delta: Double)? {
        guard let center, let bounds = bounds else { return nil }
        let latSpan = max(0.0005, (bounds.maxLat - bounds.minLat) * padding)
        let lonSpan = max(0.0005, (bounds.maxLon - bounds.minLon) * padding)
        let delta = min(180, max(latSpan, lonSpan))
        return (center, delta)
    }

    // MARK: - Yardımcılar

    /// Haversine mesafe (metre) — orta dünya yarıçapı 6 371 000 m.
    public static func haversine(_ a: DiveCoordinate, _ b: DiveCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Bir noktanın zamana göre konumu (animasyon/sürükleme için).
    public func coordinate(atElapsed elapsed: TimeInterval) -> DiveCoordinate? {
        guard let first = points.first else { return nil }
        guard elapsed >= first.elapsed, let last = points.last, elapsed <= last.elapsed else {
            return points.first?.coordinate
        }
        var index = 0
        while index + 1 < points.count, points[index + 1].elapsed < elapsed {
            index += 1
        }
        let a = points[index]
        let b = points[min(index + 1, points.count - 1)]
        let span = b.elapsed - a.elapsed
        guard span > 0 else { return a.coordinate }
        let t = (elapsed - a.elapsed) / span
        return DiveCoordinate(
            latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * t,
            longitude: a.coordinate.longitude + (b.coordinate.longitude - a.coordinate.longitude) * t)
    }
}
