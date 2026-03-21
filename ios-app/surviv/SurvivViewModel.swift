import SwiftUI
import MapKit

final class SurvivViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.336, longitude: -122.009),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    @Published var zones: [ZoneItem] = [
        ZoneItem(
            kind: .danger,
            center: CLLocationCoordinate2D(latitude: 31.5075, longitude: 34.4620),
            radiusMeters: 360,
            createdAt: .now.addingTimeInterval(-360)
        ),
        ZoneItem(
            kind: .safeRoute,
            center: CLLocationCoordinate2D(latitude: 31.4960, longitude: 34.4720),
            radiusMeters: 230,
            createdAt: .now.addingTimeInterval(-180)
        )
    ]

    @Published var threatQueue: [ThreatQueueItem] = [
        ThreatQueueItem(type: "Drone", timeLabel: "2m ago", distanceLabel: "0.8 km"),
        ThreatQueueItem(type: "Roadblock", timeLabel: "7m ago", distanceLabel: "1.5 km"),
        ThreatQueueItem(type: "Troops", timeLabel: "13m ago", distanceLabel: "2.1 km")
    ]

    @Published var showReportSheet = false
    @Published var crisisMode = false
    @Published var selectedZoneKind: ZoneKind = .danger

    @Published var peerCount: Int = 5
    @Published var queueCount: Int = 3
    @Published var lastSyncText: String = "14s"

    let sitrepText: String = """
    SITREP // MODEL: GEMINI-MOCK
    -------------------------------------------------
    GRID: GAZA-31.50/34.46
    RELAY STATUS: STABLE
    THREAT CLUSTERS: 3 ACTIVE
    PRIORITY: EVACUATE CIVILIANS FROM SECTOR C2

    AI NOTES:
    - Rotor signature detected in north corridor.
    - Civilian movement increased near safe route.
    - Intermittent signal loss from node C-17.
    """

    func report(category: HazardCategory) {
        Haptics.impact(.medium)
        let kind: ZoneKind = category == .roadblock ? .safeRoute : .danger
        addZone(kind: kind, at: region.center, radius: category == .roadblock ? 180 : 280)
        threatQueue.insert(
            ThreatQueueItem(type: category.rawValue, timeLabel: "now", distanceLabel: "0.2 km"),
            at: 0
        )
        queueCount = threatQueue.count
    }

    func addZone(kind: ZoneKind, at coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 250) {
        zones.append(
            ZoneItem(kind: kind, center: coordinate, radiusMeters: radius, createdAt: .now)
        )
    }

    func drawAtCenter(_ kind: ZoneKind) {
        Haptics.impact(.light)
        selectedZoneKind = kind
        addZone(kind: kind, at: region.center, radius: kind == .danger ? 340 : 220)
    }

    func broadcast(_ item: ThreatQueueItem) {
        Haptics.success()
        queueCount = max(0, queueCount - 1)
    }

    func quarantine(_ item: ThreatQueueItem) {
        Haptics.impact(.rigid)
        threatQueue.removeAll { $0.id == item.id }
        queueCount = threatQueue.count
    }
}
