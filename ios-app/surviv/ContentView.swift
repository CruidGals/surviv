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
import CoreLocation

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: Coordinator
    @EnvironmentObject private var networker: SurvivNetworker
    @Query(sort: \HazardPin.timestamp, order: .reverse) private var pins: [HazardPin]
    @StateObject private var model = MapViewModel()
    @State private var showSettings = false
    @State private var showBroadcastMessages = false
    @State private var leftToolbarExpanded: LeftToolbarExpandedItem? = nil
    @State private var bottomHazardExpanded = false

    var body: some View {
        ZStack(alignment: .top) {
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

            VStack {
                Spacer(minLength: 0)

                statusToastStack
                    .padding(.horizontal, 16)

                BottomHazardChrome(
                    isExpanded: $bottomHazardExpanded,
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            LeftToolbarChrome(
                expandedItem: $leftToolbarExpanded,
                isOnline: model.isOnline,
                hasOfflineArea: model.hasOfflineArea,
                meshPeerCount: networker.connectedPeers.count,
                onSettings: {
                    leftToolbarExpanded = nil
                    showSettings = true
                },
                onBroadcastMessages: {
                    leftToolbarExpanded = nil
                    showBroadcastMessages = true
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            model.loadOfflineMetadata()
        }
        .onAppear {
            if let c = coordinator.locationManager.lastKnownMapCoordinate() {
                model.centerOnUserIfNeeded(c)
            }
        }
        .onChange(of: coordinator.locationRevision) { _, _ in
            if let c = coordinator.locationManager.lastKnownMapCoordinate() {
                model.centerOnUserIfNeeded(c)
            }
        }
        .sheet(isPresented: $showSettings) {
            CivilianSettingsSheet()
                .presentationDetents([.medium])
                .presentationCornerRadius(22)
        }
        .sheet(isPresented: $showBroadcastMessages) {
            BroadcastMessagesSheet()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(22)
        }
    }

    @ViewBuilder
    private var statusToastStack: some View {
        VStack(spacing: 10) {
            if let ann = networker.latestAdminAnnouncement {
                StatusCard(
                    title: "COMMAND ALERT",
                    subtitle: "\(ann.senderName): \(ann.message)"
                )
                .onTapGesture { networker.dismissAnnouncementBanner() }
            }

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
                    .onTapGesture { model.dismissDownloadStatus() }
            }
        }
        .padding(.bottom, 10)
    }
}

private enum LeftToolbarExpandedItem: Equatable {
    case internet
    case mesh
    case cache
}

private struct LeftToolbarChrome: View {
    @Binding var expandedItem: LeftToolbarExpandedItem?
    let isOnline: Bool
    let hasOfflineArea: Bool
    let meshPeerCount: Int
    let onSettings: () -> Void
    let onBroadcastMessages: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ProjectTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(leftToolbarIconCircleFill(selectedAccent: nil), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Button(action: onBroadcastMessages) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProjectTheme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(leftToolbarIconCircleFill(selectedAccent: nil), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Broadcast messages")
                toolbarIconButton(
                    item: .internet,
                    systemImage: isOnline ? "wifi" : "wifi.slash",
                    accent: isOnline ? ProjectTheme.signal : ProjectTheme.warning
                )
                toolbarIconButton(
                    item: .mesh,
                    systemImage: "dot.radiowaves.left.and.right",
                    accent: meshPeerCount > 0 ? ProjectTheme.signal : ProjectTheme.caution
                )
                toolbarIconButton(
                    item: .cache,
                    systemImage: hasOfflineArea ? "internaldrive.fill" : "internaldrive",
                    accent: hasOfflineArea ? ProjectTheme.signal : ProjectTheme.caution
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)

            if let item = expandedItem {
                leftToolbarDetailCard(item: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: expandedItem)
        .safeAreaPadding(.top, 10)
        .safeAreaPadding(.leading, 12)
    }

    /// Nearly-opaque disk behind toolbar glyphs so they stay readable on the map.
    private func leftToolbarIconCircleFill(selectedAccent: Color?) -> Color {
        if let accent = selectedAccent {
            accent.opacity(0.94)
        } else {
            Color(red: 0.07, green: 0.11, blue: 0.14).opacity(0.94)
        }
    }

    private func toolbarIconButton(item: LeftToolbarExpandedItem, systemImage: String, accent: Color) -> some View {
        let isSelected = expandedItem == item
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                if expandedItem == item {
                    expandedItem = nil
                } else {
                    expandedItem = item
                }
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? ProjectTheme.textPrimary : accent)
                .frame(width: 40, height: 40)
                .background(leftToolbarIconCircleFill(selectedAccent: isSelected ? accent : nil), in: Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? accent.opacity(0.95) : Color.white.opacity(0.22),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    private func accessibilityLabel(for item: LeftToolbarExpandedItem) -> String {
        switch item {
        case .internet: return "Internet status"
        case .mesh: return "Mesh status"
        case .cache: return "Offline cache status"
        }
    }

    @ViewBuilder
    private func leftToolbarDetailCard(item: LeftToolbarExpandedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item {
            case .internet:
                Text("Internet")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)
                Text(isOnline ? "On" : "Off")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isOnline ? ProjectTheme.signal : ProjectTheme.warning)
                Text(isOnline ? "Connected — you can reach the wider network." : "No connection — maps and mesh may be limited until you reconnect.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(ProjectTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .mesh:
                Text("Mesh")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)
                Text(meshPeerCount > 0 ? "Active" : "Inactive")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(meshPeerCount > 0 ? ProjectTheme.signal : ProjectTheme.caution)
                if meshPeerCount > 0 {
                    Text("Enabled — linked with \(meshPeerCount) peer\(meshPeerCount == 1 ? "" : "s") nearby.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ProjectTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No peers in range. Mesh stays on and will connect when another device is nearby.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ProjectTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .cache:
                Text("Map cache")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)
                Text(hasOfflineArea ? "Ready" : "Not ready")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(hasOfflineArea ? ProjectTheme.signal : ProjectTheme.caution)
                Text(
                    hasOfflineArea
                        ? "Enabled — an offline area is saved for when internet is unavailable."
                        : "Disabled — preload an area from Hazard map while online to use cached tiles offline."
                )
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(ProjectTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 240, alignment: .leading)
        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
        )
    }
}

private struct BottomHazardChrome: View {
    @Binding var isExpanded: Bool
    let selectedPinType: PinType
    @Binding var zoneRadiusMeters: Double
    let pinCount: Int
    let isDownloading: Bool
    let onSelectType: (PinType) -> Void
    let onApplyRadiusToLast: () -> Void
    let onDownloadArea: () -> Void
    let onClearPins: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sheetGrabber
                .padding(.top, 10)
                .gesture(bottomDragGesture)

            if isExpanded {
                ControlPanel(
                    selectedPinType: selectedPinType,
                    zoneRadiusMeters: $zoneRadiusMeters,
                    pinCount: pinCount,
                    isDownloading: isDownloading,
                    onSelectType: onSelectType,
                    onApplyRadiusToLast: onApplyRadiusToLast,
                    onDownloadArea: onDownloadArea,
                    onClearPins: onClearPins
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                collapsedBottomTab
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isExpanded)
        .safeAreaPadding(.bottom, 6)
    }

    private var sheetGrabber: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white.opacity(0.38))
            .frame(width: 40, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private var collapsedBottomTab: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ProjectTheme.caution)
                Text("Hazard map")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)
                Spacer()
                Text("\(pinCount) zones")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ProjectTheme.textSecondary)
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ProjectTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ProjectTheme.panelBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var bottomDragGesture: some Gesture {
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

private struct CivilianSettingsSheet: View {
    @AppStorage("isAdmin") private var isAdmin = false
    @Environment(\.dismiss) private var dismiss
    @State private var showPasscodeEntry = false
    @State private var passcodeInput = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)

                Toggle("Crisis mode (UI emphasis)", isOn: .constant(false))
                    .disabled(true)
                    .tint(ProjectTheme.warning)

                Spacer()

                Text("Version 1.0.0")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProjectTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onTapGesture(count: 5) {
                        passcodeInput = ""
                        showPasscodeEntry = true
                    }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.07, blue: 0.09).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPasscodeEntry) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Admin unlock")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text("Enter the operations passcode.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SecureField("Passcode", text: $passcodeInput)
                            .textContentType(.password)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        Button("Unlock") {
                            if passcodeInput == "1111" {
                                isAdmin = true
                                showPasscodeEntry = false
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(20)
                    .navigationTitle("Unlock")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showPasscodeEntry = false }
                        }
                    }
                }
            }
        }
    }
}

private struct BroadcastMessagesSheet: View {
    @EnvironmentObject private var networker: SurvivNetworker
    @Environment(\.dismiss) private var dismiss

    private var orderedPackets: [SurvivPacket] {
        networker.incomingMessages.reversed()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Broadcasts")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)

                if orderedPackets.isEmpty {
                    Text("No broadcast messages yet. Admin alerts from the mesh will appear here.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(ProjectTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(orderedPackets, id: \.id) { packet in
                                broadcastMessageRow(packet)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text("Mesh relay · newest first")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProjectTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.07, blue: 0.09).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func broadcastMessageRow(_ packet: SurvivPacket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(packet.senderName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ProjectTheme.textPrimary)
                Spacer(minLength: 8)
                Text(packet.timestamp, style: .time)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ProjectTheme.textSecondary)
            }
            Text(packet.message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(ProjectTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if packet.hopCount > 0 {
                Text("Hops: \(packet.hopCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ProjectTheme.textSecondary.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ProjectTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProjectTheme.panelBorder, lineWidth: 1)
        )
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
    /// Placeholder until the first real GPS fix (via `centerOnUserIfNeeded`).
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.336, longitude: -122.009),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @Published var selectedPinType: PinType = .danger

    private var didApplyUserLaunchLocation = false
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

    /// Centers the map on the user once at launch when a valid coordinate is available.
    func centerOnUserIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard !didApplyUserLaunchLocation else { return }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        didApplyUserLaunchLocation = true
        region = MKCoordinateRegion(center: coordinate, span: region.span)
    }

    func loadOfflineMetadata() {
        hasOfflineArea = OfflineMapCacheManager.shared.hasAnyOfflineArea
        if let area = OfflineMapCacheManager.shared.latestOfflineArea {
            downloadStatusMessage = "Area cached on \(area.createdAt.formatted(date: .abbreviated, time: .shortened))."
        }
    }

    func dismissDownloadStatus() {
        downloadStatusMessage = nil
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
    let networker = SurvivNetworker()
    ContentView()
        .environmentObject(Coordinator(modelContainer: container, networker: networker))
        .environmentObject(networker)
        .modelContainer(container)
}
