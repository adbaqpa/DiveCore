import Foundation

/// Dalış sırasında sensör/sistem hataları.
public enum DepthSensorError: Error, Equatable, LocalizedError {
    case notAvailable(String)
    case permissionDenied
    case calibrationRequired
    case failedToStart(String)
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable(let detail): return "Sensör kullanılamıyor: \(detail)"
        case .permissionDenied: return "Sensör izni reddedildi"
        case .calibrationRequired: return "Yüzey referans basıncı kalibre edilmeli"
        case .failedToStart(let detail): return "Sensör başlatılamadı: \(detail)"
        case .underlying(let detail): return "Sensör hatası: \(detail)"
        }
    }
}

/// Derinlik/basınç verisi sağlayan kaynak.
///
/// Hem gerçek donanım (`CMAltimeter`) hem de simülatör bu protokolü uygular;
/// `DiveSessionController` yalnızca bu arayüzü tanır (bağımlılık tersine çevirme).
@MainActor
public protocol DepthSensor: AnyObject {

    /// Okuma üretildiğinde çağrılır. Ana iş parçacığında teslim edilir.
    var onReading: ((DepthReading) -> Void)? { get set }

    /// Hata oluştuğunda çağrılır.
    var onError: ((DepthSensorError) -> Void)? { get set }

    /// Kaynak şu anda çalışıyor mu?
    var isRunning: Bool { get }

    /// Kaynağın kısa adı (arayüz/hata ayıklama için).
    var sourceName: String { get }

    /// Veri akışını başlatır.
    func start() throws

    /// Veri akışını durdurur.
    func stop()
}

/// Testler ve önizlemelerde kullanılan, elle beslenen sensör.
///
/// `DiveSimulator` ile birleştirildiğinde gerçek zamanlı taklit akışı elde edilir.
@MainActor
public final class MockDepthSensor: DepthSensor {

    public var onReading: ((DepthReading) -> Void)?
    public var onError: ((DepthSensorError) -> Void)?
    public private(set) var isRunning = false
    public let sourceName: String

    /// `start()` çağrıldıktan sonra kaç kez başlatıldı (testler için).
    public private(set) var startCount = 0

    /// Elle enjekte edilen okumalar.
    private var queue: [DepthReading] = []
    /// Otomatik üretim için kaynak (verilirse `tick()` veri üretir).
    private var generator: (() -> DepthReading?)?

    public init(sourceName: String = "Mock", generator: (() -> DepthReading?)? = nil) {
        self.sourceName = sourceName
        self.generator = generator
    }

    public func start() throws {
        guard !isRunning else { return }
        isRunning = true
        startCount += 1
    }

    public func stop() {
        isRunning = false
    }

    // MARK: - Besleme

    /// Okuma kuyruğuna ekler.
    public func enqueue(_ readings: [DepthReading]) {
        queue.append(contentsOf: readings)
    }

    public func enqueue(_ reading: DepthReading) {
        queue.append(reading)
    }

    /// Kuyruktaki sıradaki okumayı teslim eder.
    @discardableResult
    public func deliverNext() -> Bool {
        guard isRunning, !queue.isEmpty else { return false }
        onReading?(queue.removeFirst())
        return true
    }

    /// Kuyruktaki tüm okumaları teslim eder.
    public func deliverAll() {
        while deliverNext() {}
    }

    /// Üreteçten bir okuma üretip teslim eder.
    @discardableResult
    public func tick() -> Bool {
        guard isRunning else { return false }
        if !queue.isEmpty {
            return deliverNext()
        }
        guard let generator, let reading = generator() else { return false }
        onReading?(reading)
        return true
    }

    /// Hata üretir.
    public func fail(_ error: DepthSensorError) {
        onError?(error)
    }
}