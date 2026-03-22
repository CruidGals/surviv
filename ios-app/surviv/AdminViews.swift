import SwiftUI
import MapKit
import SwiftData

enum AdminTab {
    case masterMap
    case broadcast
    case threatHistory
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
            case .threatHistory:
                ThreatHistoryView()
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
    @Environment(\.modelContext) private var modelContext
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
                    onSelectType: mapModel.selectPinType(_:),
                    onApplyRadiusToLast: {
                        guard let last = pins.first else { return }
                        last.radiusMeters = mapModel.zoneRadiusMeters
                    },
                    onUndoLastPin: {
                        guard let last = pins.first else { return }
                        modelContext.delete(last)
                        try? modelContext.save()
                    },
                    onClearAllPins: {
                        for pin in pins { modelContext.delete(pin) }
                        try? modelContext.save()
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
                    HazardPinDetailSheet(pin: pin)
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
    let onSelectType: (PinType) -> Void
    let onApplyRadiusToLast: () -> Void
    let onUndoLastPin: () -> Void
    let onClearAllPins: () -> Void

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
                    onSelectType: onSelectType,
                    onApplyRadiusToLast: onApplyRadiusToLast,
                    onUndoLastPin: onUndoLastPin,
                    onClearAllPins: onClearAllPins
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
    let onSelectType: (PinType) -> Void
    let onApplyRadiusToLast: () -> Void
    let onUndoLastPin: () -> Void
    let onClearAllPins: () -> Void

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

                Button(action: onClearAllPins) {
                    Label("Clear All Zones", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(pinCount == 0)
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

    private var trimmedMessage: String {
        messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canBroadcast: Bool {
        !trimmedMessage.isEmpty
    }

    var body: some View {
        NavigationStack {
            let feedMessages = Array(networker.incomingMessages.reversed())

            ZStack {
                Color.black
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [Color(red: 0.22, green: 0.05, blue: 0.07).opacity(0.30), .clear, Color(red: 0.05, green: 0.11, blue: 0.13).opacity(0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(SurvivTheme.danger.opacity(0.18))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "megaphone.fill")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(SurvivTheme.danger)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Mesh Alerts")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(SurvivTheme.textPrimary)
                                Text("Broadcast and monitor emergency updates")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(SurvivTheme.textSecondary)
                            }

                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 8) {
                            Label("\(feedMessages.count) messages", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(SurvivTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08), in: Capsule())

                            Label("Mesh online", systemImage: "dot.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(SurvivTheme.safe)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SurvivTheme.safe.opacity(0.14), in: Capsule())

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    if feedMessages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(SurvivTheme.textSecondary)
                            Text("No Active Alerts")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(SurvivTheme.textPrimary)
                            Text("Your broadcasts will appear here in real time")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(SurvivTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(feedMessages, id: \.id) { packet in
                                    AdminBroadcastRow(packet: packet)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Compose Alert")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(SurvivTheme.textSecondary)
                        Spacer(minLength: 0)
                        Text("\(trimmedMessage.count) chars")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(SurvivTheme.textSecondary)
                    }

                    TextField("Evacuate North Gate. Avoid Main Street.", text: $messageInput, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SurvivTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )

                    Button {
                        guard canBroadcast else { return }
                        networker.broadcast(message: trimmedMessage)
                        messageInput = ""
                    } label: {
                        Label("Broadcast", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(SurvivTheme.danger.opacity(canBroadcast ? 0.95 : 0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SurvivTheme.danger.opacity(0.95), lineWidth: 1)
                    )
                    .disabled(!canBroadcast)
                }
                .padding(16)
                .background(Color(red: 0.08, green: 0.10, blue: 0.12).opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 70)
            }
            .navigationTitle("Announcements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct AdminBroadcastRow: View {
    let packet: SurvivPacket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(packet.senderName, systemImage: "person.wave.2.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(SurvivTheme.safe)
                Spacer(minLength: 0)
                Text(packet.timestamp, style: .time)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurvivTheme.textSecondary)
            }

            Text(packet.message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(SurvivTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
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
            AdminTabButton(title: "History", icon: "clock.fill", isSelected: selectedTab == .threatHistory) {
                Haptics.impact(.light)
                selectedTab = .threatHistory
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct ThreatHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HazardPin.timestamp, order: .reverse) private var pins: [HazardPin]

    private var dangerCount: Int {
        pins.filter { $0.pinType == .danger }.count
    }

    private var safeCount: Int {
        pins.filter { $0.pinType == .safeRoute }.count
    }

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SurvivTheme.danger.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(SurvivTheme.danger)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Threat Timeline")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(SurvivTheme.textPrimary)
                    Text("All network reports with source and location")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SurvivTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label("\(pins.count) total", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurvivTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: Capsule())

                Label("\(dangerCount) danger", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurvivTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SurvivTheme.danger.opacity(0.14), in: Capsule())

                Label("\(safeCount) safe", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurvivTheme.safe)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SurvivTheme.safe.opacity(0.14), in: Capsule())

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if pins.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(SurvivTheme.textSecondary)
                        Text("No Threats Reported")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(SurvivTheme.textPrimary)
                        Text("Hazards will appear here as they're reported")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SurvivTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 12) {
                        historyHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        List {
                            ForEach(pins) { pin in
                                ThreatHistoryRow(pin: pin)
                                    .listRowBackground(Color.black.opacity(0.5))
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    modelContext.delete(pins[index])
                                }
                                try? modelContext.save()
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ThreatHistoryRow: View {
    let pin: HazardPin

    private var relativeTime: String {
        let interval = Date.now.timeIntervalSince(pin.timestamp)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }

    private var typeIcon: String {
        pin.pinType == .danger ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var typeColor: Color {
        pin.pinType == .danger ? SurvivTheme.danger : SurvivTheme.safe
    }

    private var creatorDisplay: String {
        let name = pin.createdByUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Type, Time, Creator
            HStack(spacing: 12) {
                Image(systemName: typeIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(typeColor)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(pin.pinType == .danger ? "Danger Zone" : "Safe Route")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(SurvivTheme.textPrimary)
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        Label(creatorDisplay, systemImage: "person.fill")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(SurvivTheme.safe)
                        
                        Text(relativeTime)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(SurvivTheme.textSecondary)
                    }
                }
                
                Spacer()
            }

            // Threat Details
            if !pin.threatClassLabel.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(typeColor)
                    Text(pin.threatClassLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(typeColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(typeColor.opacity(0.15))
                .cornerRadius(6)
            }

            // Metadata Row
            HStack(spacing: 16) {
                Label("\(Int(pin.radiusMeters))m radius", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SurvivTheme.textSecondary)

                if !pin.reasonMessage.isEmpty {
                    Label(pin.reasonMessage, systemImage: "note.text")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SurvivTheme.textSecondary)
                        .lineLimit(1)
                }
                else if !pin.label.isEmpty {
                    Label(pin.label, systemImage: "tag.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SurvivTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }

            // Coordinates
            HStack(spacing: 6) {
                Image(systemName: "mappin")
                    .font(.system(size: 10, weight: .semibold))
                Text(String(format: "%.4f, %.4f", pin.latitude, pin.longitude))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                Spacer()
            }
            .foregroundStyle(SurvivTheme.textSecondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
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

private extension HazardPin {
    // HazardPin already has coordinate property defined in the model
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
