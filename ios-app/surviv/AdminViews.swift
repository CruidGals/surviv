import SwiftUI
import MapKit
import SwiftData

enum AdminTab {
    case masterMap
    case broadcast
}

struct AdminTabView: View {
    @Binding var isAdmin: Bool
    @EnvironmentObject private var networker: SurvivNetworker
    @State private var selectedTab: AdminTab = .masterMap

    var body: some View {
        Group {
            switch selectedTab {
            case .masterMap:
                MasterMapView()
            case .broadcast:
                AdminBroadcastView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            AdminBottomBar(selectedTab: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(.clear)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.impact(.medium)
                isAdmin = false
            } label: {
                Label("Exit Admin", systemImage: "person")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.56), in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .onAppear {
            networker.applyAppAdminState(isAdmin)
        }
        .onChange(of: isAdmin) { _, newValue in
            networker.applyAppAdminState(newValue)
        }
    }
}

private struct PendingAdminPinDraft: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let pinType: PinType
    let radiusMeters: Double
}

private enum MasterMapActiveSheet: Identifiable {
    case compose(PendingAdminPinDraft)
    case detail(UUID)

    var id: String {
        switch self {
        case .compose(let d): return "compose-\(d.id.uuidString)"
        case .detail(let u): return "detail-\(u.uuidString)"
        }
    }
}

private struct MasterMapView: View {
    @EnvironmentObject private var coordinator: Coordinator
    @Query(sort: \HazardPin.timestamp, order: .reverse) private var pins: [HazardPin]
    @StateObject private var mapModel = MapViewModel()
    @State private var bottomHazardExpanded = false
    @State private var activeSheet: MasterMapActiveSheet?

    /// Cluster overlapping danger zones into combined zones
    private var clusteredPins: [HazardPin] {
        let dangerPins = pins.filter { $0.pinType == .danger }
        let safeRoutePins = pins.filter { $0.pinType == .safeRoute }
        
        guard !dangerPins.isEmpty else { return pins }
        
        var processed = Set<UUID>()
        var clustered: [HazardPin] = []
        
        for pin in dangerPins {
            guard !processed.contains(pin.id) else { continue }
            
            // Find all pins that overlap with this one
            var cluster = [pin]
            processed.insert(pin.id)
            
            for otherPin in dangerPins {
                guard !processed.contains(otherPin.id) else { continue }
                
                // Calculate distance between centers
                let distance = pin.coordinate.distance(to: otherPin.coordinate)
                
                // If distance <= sum of radii, they overlap
                if distance <= pin.radiusMeters + otherPin.radiusMeters {
                    cluster.append(otherPin)
                    processed.insert(otherPin.id)
                }
            }
            
            // If cluster has multiple pins, merge them
            if cluster.count > 1 {
                let mergedPin = mergeCluster(cluster)
                clustered.append(mergedPin)
            } else {
                clustered.append(pin)
            }
        }
        
        return clustered + safeRoutePins
    }

    private var dangerPinCount: Int { pins.filter { $0.pinType == .danger }.count }
    private var safeRoutePinCount: Int { pins.filter { $0.pinType == .safeRoute }.count }

    /// Merge multiple overlapping pins into a single combined zone
    private func mergeCluster(_ pins: [HazardPin]) -> HazardPin {
        let avgLat = pins.map { $0.latitude }.reduce(0, +) / Double(pins.count)
        let avgLon = pins.map { $0.longitude }.reduce(0, +) / Double(pins.count)
        let centerCoord = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
        
        // Calculate radius to encompass all pins
        let maxDistance = pins.map { pin in
            centerCoord.distance(to: pin.coordinate) + pin.radiusMeters
        }.max() ?? 120
        
        let merged = HazardPin(
            id: pins[0].id,
            latitude: avgLat,
            longitude: avgLon,
            pinType: .danger,
            threatSource: pins[0].threatSource,
            radiusMeters: maxDistance,
            label: "Combined (\(pins.count))",
            createdByUsername: pins[0].createdByUsername,
            threatClassLabel: pins[0].threatClassLabel,
            reasonMessage: pins[0].reasonMessage,
            sourceDeviceID: pins[0].sourceDeviceID,
            timestamp: pins[0].timestamp
        )
        return merged
    }

    var body: some View {
        ZStack {
            HazardMapView(
                region: $mapModel.region,
                selectedPinId: Binding(
                    get: {
                        if case .detail(let uuid) = activeSheet { return uuid }
                        return nil
                    },
                    set: { newValue in
                        if let uuid = newValue {
                            activeSheet = .detail(uuid)
                        } else if case .detail = activeSheet {
                            activeSheet = nil
                        }
                    }
                ),
                pins: clusteredPins,
                userLocation: coordinator.locationManager.lastKnownMapCoordinate(),
                onDropPin: { coordinate in
                    activeSheet = .compose(
                        PendingAdminPinDraft(
                            coordinate: coordinate,
                            pinType: mapModel.selectedPinType,
                            radiusMeters: mapModel.zoneRadiusMeters
                        )
                    )
                }
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                Spacer(minLength: 0)

                AdminBottomHazardChrome(
                    isExpanded: $bottomHazardExpanded,
                    selectedPinType: mapModel.selectedPinType,
                    zoneRadiusMeters: $mapModel.zoneRadiusMeters,
                    pinCount: clusteredPins.count,
                    dangerPinCount: dangerPinCount,
                    safeRoutePinCount: safeRoutePinCount,
                    onSelectType: mapModel.selectPinType(_:),
                    onApplyRadiusToLast: {
                        guard let last = pins.first else { return }
                        last.radiusMeters = mapModel.zoneRadiusMeters
                    },
                    onUndoLastPin: {
                        guard let last = pins.first else { return }
                        coordinator.deleteHazardPinAndBroadcast(id: last.id)
                    },
                    onClearDangerZones: {
                        coordinator.clearHazardPinsByTypeAndBroadcast(.danger)
                    },
                    onClearSafeRouteZones: {
                        coordinator.clearHazardPinsByTypeAndBroadcast(.safeRoute)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(Color.black)
        .onAppear {
            if let c = coordinator.locationManager.lastKnownMapCoordinate() {
                mapModel.centerOnUserIfNeeded(c)
            }
        }
        .onChange(of: coordinator.locationRevision) { _, _ in
            if let c = coordinator.locationManager.lastKnownMapCoordinate() {
                mapModel.centerOnUserIfNeeded(c)
            }
        }
        .sheet(item: $activeSheet) { token in
            switch token {
            case .compose(let draft):
                AdminHazardPinComposeSheet(
                    pinType: draft.pinType,
                    onCancel: { activeSheet = nil },
                    onCommit: { threatClass, reason, label in
                        coordinator.dropHazardPin(
                            at: draft.coordinate,
                            pinType: draft.pinType,
                            radiusMeters: draft.radiusMeters,
                            threatClassLabel: threatClass,
                            reasonMessage: reason,
                            label: label
                        )
                        activeSheet = nil
                    }
                )
            case .detail(let id):
                if let pin = pins.first(where: { $0.id == id }) {
                    HazardPinDetailSheet(snapshot: HazardPinDetailSnapshot(pin: pin)) {
                        coordinator.deleteHazardPinAndBroadcast(id: id)
                        activeSheet = nil
                    }
                } else {
                    Color.clear.onAppear { activeSheet = nil }
                }
            }
        }
    }
}

private struct AdminBottomHazardChrome: View {
    @Binding var isExpanded: Bool
    let selectedPinType: PinType
    @Binding var zoneRadiusMeters: Double
    let pinCount: Int
    let dangerPinCount: Int
    let safeRoutePinCount: Int
    let onSelectType: (PinType) -> Void
    let onApplyRadiusToLast: () -> Void
    let onUndoLastPin: () -> Void
    let onClearDangerZones: () -> Void
    let onClearSafeRouteZones: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.38))
                .frame(width: 40, height: 5)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        isExpanded.toggle()
                    }
                }

            if isExpanded {
                AdminMappingPanel(
                    selectedPinType: selectedPinType,
                    zoneRadiusMeters: $zoneRadiusMeters,
                    pinCount: pinCount,
                    dangerPinCount: dangerPinCount,
                    safeRoutePinCount: safeRoutePinCount,
                    onSelectType: onSelectType,
                    onApplyRadiusToLast: onApplyRadiusToLast,
                    onUndoLastPin: onUndoLastPin,
                    onClearDangerZones: onClearDangerZones,
                    onClearSafeRouteZones: onClearSafeRouteZones
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        isExpanded = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.94, green: 0.67, blue: 0.15))
                        Text("Hazard map")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(pinCount) zones")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.07, green: 0.11, blue: 0.14).opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let dy = value.translation.height
                    if isExpanded, dy > 28 {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            isExpanded = false
                        }
                    } else if !isExpanded, dy < -28 {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            isExpanded = true
                        }
                    }
                }
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isExpanded)
        .safeAreaPadding(.bottom, 8)
    }
}

private struct AdminMappingPanel: View {
    let selectedPinType: PinType
    @Binding var zoneRadiusMeters: Double
    let pinCount: Int
    let dangerPinCount: Int
    let safeRoutePinCount: Int
    let onSelectType: (PinType) -> Void
    let onApplyRadiusToLast: () -> Void
    let onUndoLastPin: () -> Void
    let onClearDangerZones: () -> Void
    let onClearSafeRouteZones: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hazard Mapping")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Choose a zone type, then tap the map to place it.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))

            HStack(spacing: 8) {
                AdminZoneTypeButton(
                    title: "Danger",
                    icon: "exclamationmark.triangle.fill",
                    color: Color(red: 0.90, green: 0.20, blue: 0.20),
                    isSelected: selectedPinType == .danger,
                    onTap: { onSelectType(.danger) }
                )

                AdminZoneTypeButton(
                    title: "Safe Route",
                    icon: "figure.walk.diamond.fill",
                    color: Color(red: 0.12, green: 0.72, blue: 0.52),
                    isSelected: selectedPinType == .safeRoute,
                    onTap: { onSelectType(.safeRoute) }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Zone Radius")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.78))
                    Spacer()
                    Text("\(Int(zoneRadiusMeters)) m")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Slider(value: $zoneRadiusMeters, in: 50...800, step: 10)
                    .tint(selectedPinType == .danger ? Color(red: 0.90, green: 0.20, blue: 0.20) : Color(red: 0.12, green: 0.72, blue: 0.52))
                Button(action: onApplyRadiusToLast) {
                    Label("Apply Radius To Last Zone", systemImage: "arrow.uturn.backward.circle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label("\(pinCount) Hazard Zones", systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.94, green: 0.67, blue: 0.15))
                Spacer()
            }

            VStack(spacing: 8) {
                Button(action: onUndoLastPin) {
                    Label("Undo Last Zone", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(pinCount == 0)

                HStack(spacing: 8) {
                    Button(action: onClearDangerZones) {
                        Label("Clear danger", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.90, green: 0.20, blue: 0.20))
                    .disabled(dangerPinCount == 0)

                    Button(action: onClearSafeRouteZones) {
                        Label("Clear safe", systemImage: "figure.walk.diamond.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.12, green: 0.72, blue: 0.52))
                    .disabled(safeRoutePinCount == 0)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.07, green: 0.11, blue: 0.14).opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct AdminZoneTypeButton: View {
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

private struct AdminBroadcastView: View {
    @EnvironmentObject private var networker: SurvivNetworker
    @State private var messageInput = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(networker.incomingMessages.reversed(), id: \.id) { packet in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(packet.senderName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SurvivTheme.safe)
                            Text(packet.message)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(packet.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(SurvivTheme.textSecondary)
                        }
                        .listRowBackground(Color.black.opacity(0.9))
                    }
                } header: {
                    Text("Mesh feed")
                        .foregroundStyle(SurvivTheme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .safeAreaInset(edge: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Evacuate North…", text: $messageInput, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    Button {
                        let trimmed = messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        networker.broadcast(message: trimmed)
                        messageInput = ""
                    } label: {
                        Label("Broadcast to mesh", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SurvivTheme.danger)
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .padding(.bottom, 70)
            }
            .navigationTitle("Announcements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct AdminBottomBar: View {
    @Binding var selectedTab: AdminTab

    var body: some View {
        HStack(spacing: 8) {
            AdminTabButton(title: "Map", icon: "map", isSelected: selectedTab == .masterMap) {
                Haptics.impact(.light)
                selectedTab = .masterMap
            }
            AdminTabButton(title: "Alert", icon: "megaphone.fill", isSelected: selectedTab == .broadcast) {
                Haptics.impact(.light)
                selectedTab = .broadcast
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct AdminTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? SurvivTheme.safe.opacity(0.9) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension CLLocationCoordinate2D {
    /// Calculate distance in meters between two coordinates using Haversine formula
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let R = 6371000.0 // Earth's radius in meters
        
        let lat1 = latitude * .pi / 180
        let lat2 = coordinate.latitude * .pi / 180
        let dLat = (coordinate.latitude - latitude) * .pi / 180
        let dLon = (coordinate.longitude - longitude) * .pi / 180
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return R * c
    }
}
