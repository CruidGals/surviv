//
//  ContentView.swift
//  surviv.io
//
//  Created by Khai Ta on 3/21/26.
//

import SwiftUI
import SwiftData
import MapKit
import Network

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: Coordinator
    @Query(sort: \HazardPin.timestamp, order: .reverse) private var pins: [HazardPin]
    @StateObject private var model = MapViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            HazardMapView(
                region: $model.region,
                pins: pins,
                onDropPin: { coordinate in
                    let pin = HazardPin(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        pinType: model.selectedPinType,
                        radiusMeters: model.zoneRadiusMeters
                    )
                    modelContext.insert(pin)
                    coordinator.broadcastPin(pin)
                }
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

                if let threat = coordinator.threatAlert {
                    StatusCard(title: "THREAT DETECTED", subtitle: "Acoustic sensor detected: \(threat)")
                        .onTapGesture { coordinator.dismissThreatAlert() }
                }

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
                    selectedPinType: model.selectedPinType,
                    zoneRadiusMeters: $model.zoneRadiusMeters,
                    pinCount: pins.count,
                    isDownloading: model.isDownloading,
                    onSelectType: model.selectPinType(_:),
                    onApplyRadiusToLast: {
                        guard let last = pins.first else { return }
                        last.radiusMeters = model.zoneRadiusMeters
                    },
                    onDownloadArea: model.downloadCurrentArea,
                    onClearPins: {
                        for pin in pins { modelContext.delete(pin) }
                    }
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

enum ProjectTheme {
    static let signal = Color(red: 0.12, green: 0.72, blue: 0.52)
    static let warning = Color(red: 0.90, green: 0.20, blue: 0.20)
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
    let selectedPinType: PinType
    @Binding var zoneRadiusMeters: Double
    let pinCount: Int
    let isDownloading: Bool
    let onSelectType: (PinType) -> Void
    let onApplyRadiusToLast: () -> Void
    let onDownloadArea: () -> Void
    let onClearPins: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hazard Mapping")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(ProjectTheme.textPrimary)
            Text("Choose a zone type, then tap the map to place it.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ProjectTheme.textSecondary)

            HStack(spacing: 8) {
                ZoneTypeButton(
                    title: "Danger",
                    icon: "exclamationmark.triangle.fill",
                    color: ProjectTheme.warning,
                    isSelected: selectedPinType == .danger,
                    onTap: { onSelectType(.danger) }
                )

                ZoneTypeButton(
                    title: "Safe Route",
                    icon: "figure.walk.diamond.fill",
                    color: ProjectTheme.signal,
                    isSelected: selectedPinType == .safeRoute,
                    onTap: { onSelectType(.safeRoute) }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Zone Radius")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(ProjectTheme.textSecondary)
                    Spacer()
                    Text("\(Int(zoneRadiusMeters)) m")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(ProjectTheme.textPrimary)
                }
                Slider(value: $zoneRadiusMeters, in: 50...800, step: 10)
                    .tint(selectedPinType == .danger ? ProjectTheme.warning : ProjectTheme.signal)
                Button(action: onApplyRadiusToLast) {
                    Label("Apply Radius To Last Zone", systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label("\(pinCount) Hazard Zones", systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark")
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
                    Label("Clear Zones", systemImage: "trash")
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

private struct ZoneTypeButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(color.opacity(isSelected ? 0.95 : 0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.opacity(isSelected ? 1 : 0.55), lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
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

// MARK: - View Model

final class MapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.5017, longitude: 34.4668),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @Published var selectedPinType: PinType = .danger
    @Published var zoneRadiusMeters: Double = 120
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

    func selectPinType(_ type: PinType) {
        selectedPinType = type
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

// MARK: - Connectivity

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

// MARK: - Offline Map Cache

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

// MARK: - Map View

struct HazardMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let pins: [HazardPin]
    let onDropPin: (CLLocationCoordinate2D) -> Void

    final class PinAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let pinType: PinType

        init(coordinate: CLLocationCoordinate2D, pinType: PinType) {
            self.coordinate = coordinate
            self.pinType = pinType
        }
    }

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

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        longPress.cancelsTouchesInView = false
        mapView.addGestureRecognizer(longPress)
        tap.require(toFail: longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if !mapView.region.isClose(to: region) {
            mapView.setRegion(region, animated: false)
        }

        let renderKey = pins.map { pin in
            "\(pin.id.uuidString)|\(pin.pinType.rawValue)|\(pin.latitude)|\(pin.longitude)|\(pin.radiusMeters)"
        }.joined(separator: ";")

        if context.coordinator.lastRenderKey != renderKey {
            mapView.removeOverlays(mapView.overlays)
            let overlays = pins.map { pin in
                let circle = MKCircle(center: pin.coordinate, radius: pin.radiusMeters)
                circle.title = pin.pinType.rawValue
                return circle
            }
            mapView.addOverlays(overlays)

            let existingAnnotations = mapView.annotations.compactMap { $0 as? PinAnnotation }
            mapView.removeAnnotations(existingAnnotations)

            let newAnnotations = pins.map { pin in
                PinAnnotation(coordinate: pin.coordinate, pinType: pin.pinType)
            }
            mapView.addAnnotations(newAnnotations)

            context.coordinator.lastRenderKey = renderKey
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HazardMapView
        var lastRenderKey = ""

        init(_ parent: HazardMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView = recognizer.view as? MKMapView else { return }

            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onDropPin(coordinate)
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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let pinType = PinType(rawValue: circle.title ?? "") ?? .danger

            let renderer = MKCircleRenderer(circle: circle)
            switch pinType {
            case .danger:
                renderer.fillColor = UIColor(ProjectTheme.warning.opacity(0.30))
                renderer.strokeColor = UIColor(ProjectTheme.warning)
            case .safeRoute:
                renderer.fillColor = UIColor(ProjectTheme.signal.opacity(0.42))
                renderer.strokeColor = UIColor(ProjectTheme.signal)
            }
            renderer.lineWidth = 3
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pinAnnotation = annotation as? PinAnnotation else {
                return nil
            }

            let reuseId = "zone-center-pin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseId) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: pinAnnotation, reuseIdentifier: reuseId)

            view.annotation = pinAnnotation
            view.glyphImage = UIImage(systemName: "mappin")
            view.glyphTintColor = .white
            view.markerTintColor = pinAnnotation.pinType == .danger
                ? UIColor(ProjectTheme.warning)
                : UIColor(ProjectTheme.signal)
            view.displayPriority = .required
            view.canShowCallout = false
            return view
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
    let container = try! ModelContainer(for: HazardPin.self, AudioRecording.self)
    ContentView()
        .environmentObject(Coordinator(modelContainer: container))
        .modelContainer(container)
}
