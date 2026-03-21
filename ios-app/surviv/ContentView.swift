//
//  ContentView.swift
//  surviv.io
//
//  Created by Khai Ta on 3/21/26.
//

import SwiftUI
import MapKit
import Network

struct ContentView: View {
    @StateObject private var model = HazardMapViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            HazardMapView(
                region: $model.region,
                pins: model.pins,
                onDropPin: model.addHazardPin(at:)
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    ProjectTheme.overlayTop,
                    .clear,
                    ProjectTheme.overlayBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                HeaderBar(isOnline: model.isOnline, hasOfflineArea: model.hasOfflineArea)

                if !model.isOnline {
                    StatusCard(
                        title: "Offline Mode",
                        subtitle: model.hasOfflineArea
                            ? "Showing cached map data for previously downloaded areas."
                            : "No downloaded area found yet. Download an area while online."
                    )
                }

                if let status = model.downloadStatusMessage {
                    StatusCard(title: "Offline Download", subtitle: status)
                }

                ControlPanel(
                    pinCount: model.pins.count,
                    isDownloading: model.isDownloading,
                    onDownloadArea: model.downloadCurrentArea,
                    onClearPins: model.clearPins
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .task {
            model.loadOfflineMetadata()
        }
    }
}

private enum ProjectTheme {
    static let signal = Color(red: 0.12, green: 0.72, blue: 0.52)
    static let warning = Color(red: 0.93, green: 0.38, blue: 0.28)
    static let caution = Color(red: 0.94, green: 0.67, blue: 0.15)
    static let panel = Color(red: 0.07, green: 0.11, blue: 0.14).opacity(0.84)
    static let panelBorder = Color.white.opacity(0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.78)
    static let overlayTop = Color.black.opacity(0.45)
    static let overlayBottom = Color.black.opacity(0.5)
}

private struct HeaderBar: View {
    let isOnline: Bool
    let hasOfflineArea: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SURVIV")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(ProjectTheme.textPrimary)

            Text("Mesh Crisis Map")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ProjectTheme.textSecondary)

            HStack(spacing: 8) {
                StatusChip(
                    text: isOnline ? "Link Active" : "No Link",
                    color: isOnline ? ProjectTheme.signal : ProjectTheme.warning,
                    icon: isOnline ? "dot.radiowaves.left.and.right" : "wifi.slash"
                )

                StatusChip(
                    text: hasOfflineArea ? "Cache Ready" : "Cache Missing",
                    color: hasOfflineArea ? ProjectTheme.signal : ProjectTheme.caution,
                    icon: hasOfflineArea ? "internaldrive.fill" : "internaldrive"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
        )
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.9), in: Capsule())
    }
}

private struct ControlPanel: View {
    let pinCount: Int
    let isDownloading: Bool
    let onDownloadArea: () -> Void
    let onClearPins: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hazard Mapping")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(ProjectTheme.textPrimary)
            Text("Long press anywhere on the map to drop a Hazard Pin.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ProjectTheme.textSecondary)

            HStack {
                Label("\(pinCount) Hazard Pins", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ProjectTheme.caution)
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onDownloadArea) {
                    Label(
                        isDownloading ? "Caching..." : "Preload Area",
                        systemImage: "arrow.down.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading)

                Button(action: onClearPins) {
                    Label("Clear Pins", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
        )
    }
}

private struct StatusCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ProjectTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ProjectTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProjectTheme.warning.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct HazardPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let createdAt = Date()
}

private final class HazardMapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5017, longitude: 34.4668),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @Published var pins: [HazardPin] = []
    @Published var isDownloading = false
    @Published var downloadStatusMessage: String?
    @Published private(set) var hasOfflineArea = false
    @Published private(set) var isOnline = true

    private let connectivity = ConnectivityMonitor()

    init() {
        connectivity.$isOnline
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOnline)
    }

    func addHazardPin(at coordinate: CLLocationCoordinate2D) {
        pins.append(HazardPin(coordinate: coordinate))
    }

    func clearPins() {
        pins.removeAll()
    }

    func loadOfflineMetadata() {
        hasOfflineArea = OfflineMapCacheManager.shared.hasAnyOfflineArea
        if let area = OfflineMapCacheManager.shared.latestOfflineArea {
            downloadStatusMessage = "Area cached on \(area.createdAt.formatted(date: .abbreviated, time: .shortened))."
        }
    }

    func downloadCurrentArea() {
        guard !isDownloading else { return }

        isDownloading = true
        downloadStatusMessage = "Preparing local map cache..."

        let targetRegion = region
        Task {
            do {
                let area = try await OfflineMapCacheManager.shared.predownload(region: targetRegion)
                await MainActor.run {
                    self.hasOfflineArea = true
                    self.isDownloading = false
                    self.downloadStatusMessage = "Cached \(area.snapshotCount) map snapshots for offline use."
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadStatusMessage = "Offline cache failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private final class ConnectivityMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "surviv.connectivity.monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

private struct OfflineAreaMetadata: Codable {
    let centerLatitude: CLLocationDegrees
    let centerLongitude: CLLocationDegrees
    let latitudeDelta: CLLocationDegrees
    let longitudeDelta: CLLocationDegrees
    let createdAt: Date
    let snapshotCount: Int
}

private struct OfflineAreaSummary {
    let createdAt: Date
    let snapshotCount: Int
}

private final class OfflineMapCacheManager {
    static let shared = OfflineMapCacheManager()

    private let fileManager = FileManager.default
    private let metadataFile = "offline-area-metadata.json"

    private init() {}

    var hasAnyOfflineArea: Bool {
        fileManager.fileExists(atPath: metadataURL.path)
    }

    var latestOfflineArea: OfflineAreaSummary? {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(OfflineAreaMetadata.self, from: data) else {
            return nil
        }
        return OfflineAreaSummary(createdAt: metadata.createdAt, snapshotCount: metadata.snapshotCount)
    }

    func predownload(region: MKCoordinateRegion) async throws -> OfflineAreaSummary {
        try createDirectoryIfNeeded()

        let points = samplingCoordinates(for: region)
        var count = 0

        for (index, coordinate) in points.enumerated() {
            let tileRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: region.span.latitudeDelta / 3,
                    longitudeDelta: region.span.longitudeDelta / 3
                )
            )

            let image = try await snapshot(for: tileRegion)
            let url = cacheDirectory.appendingPathComponent("snapshot-\(index).jpg")
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                continue
            }
            try data.write(to: url, options: .atomic)
            count += 1
        }

        let metadata = OfflineAreaMetadata(
            centerLatitude: region.center.latitude,
            centerLongitude: region.center.longitude,
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta,
            createdAt: Date(),
            snapshotCount: count
        )

        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)

        return OfflineAreaSummary(createdAt: metadata.createdAt, snapshotCount: count)
    }

    private func snapshot(for region: MKCoordinateRegion) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 512, height: 512)
        options.scale = UIScreen.main.scale

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await snapshotter.start()
        return snapshot.image
    }

    private func samplingCoordinates(for region: MKCoordinateRegion) -> [CLLocationCoordinate2D] {
        let latStep = region.span.latitudeDelta / 3
        let lonStep = region.span.longitudeDelta / 3

        return [
            .init(latitude: region.center.latitude + latStep, longitude: region.center.longitude - lonStep),
            .init(latitude: region.center.latitude + latStep, longitude: region.center.longitude),
            .init(latitude: region.center.latitude + latStep, longitude: region.center.longitude + lonStep),
            .init(latitude: region.center.latitude, longitude: region.center.longitude - lonStep),
            .init(latitude: region.center.latitude, longitude: region.center.longitude),
            .init(latitude: region.center.latitude, longitude: region.center.longitude + lonStep),
            .init(latitude: region.center.latitude - latStep, longitude: region.center.longitude - lonStep),
            .init(latitude: region.center.latitude - latStep, longitude: region.center.longitude),
            .init(latitude: region.center.latitude - latStep, longitude: region.center.longitude + lonStep)
        ]
    }

    private var cacheDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("surviv-offline-map-cache", isDirectory: true)
    }

    private var metadataURL: URL {
        cacheDirectory.appendingPathComponent(metadataFile)
    }

    private func createDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
}

private struct HazardMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let pins: [HazardPin]
    let onDropPin: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isRotateEnabled = true
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        longPress.cancelsTouchesInView = false
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if !mapView.region.isClose(to: region) {
            mapView.setRegion(region, animated: false)
        }

        if context.coordinator.lastPinCount != pins.count {
            mapView.removeAnnotations(mapView.annotations)
            let annotations = pins.map { pin -> MKPointAnnotation in
                let annotation = MKPointAnnotation()
                annotation.coordinate = pin.coordinate
                annotation.title = "Hazard Pin"
                return annotation
            }
            mapView.addAnnotations(annotations)
            context.coordinator.lastPinCount = pins.count
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HazardMapView
        var lastPinCount = 0

        init(_ parent: HazardMapView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let mapView = recognizer.view as? MKMapView else { return }

            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onDropPin(coordinate)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }
    }
}

private extension MKCoordinateRegion {
    func isClose(to other: MKCoordinateRegion) -> Bool {
        abs(center.latitude - other.center.latitude) < 0.0001 &&
        abs(center.longitude - other.center.longitude) < 0.0001 &&
        abs(span.latitudeDelta - other.span.latitudeDelta) < 0.0001 &&
        abs(span.longitudeDelta - other.span.longitudeDelta) < 0.0001
    }
}

#Preview {
    ContentView()
}
