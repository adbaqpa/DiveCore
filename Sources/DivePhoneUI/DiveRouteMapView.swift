#if os(iOS)
import SwiftUI
import MapKit
import DiveCore

/// ADIM 10 — **GPS rota haritası**.
///
/// ## Neden yalnızca yüzey noktaları?
/// Apple Watch'ta su altında GPS çözünürlüğü 5-10 metreyi bulur ve hızla
/// pil tüketir. Bu nedenle konum kaydı **yüzeyde** (giriş, ara durak,
/// çıkış) yapılır; harita da bu noktaları çizgi olarak gösterir.
///
/// Tüm geometri `DiveRoute` içinde hesaplanır (test edilebilir); bu görünüm
/// yalnızca `Map` kamera ayarını uygular.
struct DiveRouteMapView: View {

    /// Hesaplanmış rota
    let route: DiveRoute
    /// Seçili an (grafikle senkron)
    @Binding var selectedElapsed: TimeInterval?
    /// Dalış renk paletiyle uyumli vurgu
    var accent: Color = .cyan

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera) {
            // Rotanın kendisi (koridor)
            if route.points.count >= 2 {
                MapPolyline(coordinates: route.points.map { $0.coordinate })
                    .stroke(accent.opacity(0.9), lineWidth: 4)
            }

            // Başlangıç ve bitiş
            if let first = route.points.first {
                Marker("Başlangıç", systemImage: "arrow.down.to.line",
                       coordinate: first.coordinate)
                    .tint(.green)
            }
            if let last = route.points.last, route.points.count >= 2 {
                Marker("Bitiş", systemImage: "flag.checkered", coordinate: last.coordinate)
                    .tint(.red)
            }

            // Grafikte seçili an
            if let selectedElapsed,
               let coordinate = route.coordinate(atElapsed: selectedElapsed) {
                Annotation("Seçili", coordinate: coordinate) {
                    Circle()
                        .fill(accent)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onAppear(perform: frameRoute)
        .onChange(of: route.pointCount) { _, _ in frameRoute() }
        .overlay(alignment: .bottomLeading) { legend }
        .overlay(alignment: .topTrailing) { statistics }
    }

    // MARK: - Kamera

    private func frameRoute() {
        guard let region = route.mapRegion() else { return }
        let center = CLLocationCoordinate2D(latitude: region.center.latitude,
                                            longitude: region.center.longitude)
        let span = MKCoordinateSpan(latitudeDelta: region.delta,
                                    longitudeDelta: region.delta)
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Katmanlar

    private var legend: some View {
        HStack(spacing: 10) {
            Label("Başlangıç", systemImage: "arrow.down.to.line")
            Label("Bitiş", systemImage: "flag.checkered")
        }
        .font(.caption2)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    @ViewBuilder
    private var statistics: some View {
        if !route.isEmpty {
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f m mesafe", route.totalDistance))
                Text(String(format: "%.1f m/s ortalama", route.averageSpeed))
                if route.driftRatio > 1.15 {
                    Text("⚠︎ GPS kayması")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2.monospacedDigit())
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(8)
        }
    }
}

// MARK: - Konum dönüşümleri

extension DiveCoordinate {
    /// CoreLocation karşılığı.
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Array where Element == DiveCoordinate {
    init(coordinates: [DiveCoordinate]) {
        self = coordinates
    }
}
#endif
