import SwiftUI
import MapKit

enum CivilianTab {
    case map
    case scanner
    case settings
}

struct CivilianTabView: View {
    @ObservedObject var viewModel: SurvivViewModel
    @State private var selectedTab: CivilianTab = .map

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .map:
                    CivilianMapView(viewModel: viewModel)
                case .scanner:
                    ScannerView()
                case .settings:
                    CivilianSettingsView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CivilianBottomBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
    }
}

private struct CivilianMapView: View {
    @ObservedObject var viewModel: SurvivViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.zones) { zone in
                MapAnnotation(coordinate: zone.center) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(zone.kind == .danger ? SurvivTheme.danger : SurvivTheme.safe)
                            .frame(width: 14, height: 14)
                        Text(zone.kind == .danger ? "Danger" : "Safe")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.60)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                Text("SURVIV")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Offline Mesh Lifeline")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurvivTheme.textSecondary)
                HStack(spacing: 8) {
                    MeshChip(icon: "dot.radiowaves.left.and.right", text: "\(viewModel.peerCount) Peers", color: SurvivTheme.safe)
                    MeshChip(icon: "arrow.triangle.branch", text: "Q\(viewModel.queueCount)", color: SurvivTheme.danger)
                    MeshChip(icon: "clock", text: viewModel.lastSyncText, color: .white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .frame(maxHeight: .infinity, alignment: .top)

            Button {
                Haptics.impact(.rigid)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    viewModel.showReportSheet = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(SurvivTheme.danger.opacity(0.24))
                        .frame(width: 94, height: 94)
                    Circle()
                        .fill(SurvivTheme.danger)
                        .frame(width: 70, height: 70)
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 110)
            .sheet(isPresented: $viewModel.showReportSheet) {
                ReportHazardSheet(viewModel: viewModel)
                    .presentationDetents([.medium])
                    .presentationCornerRadius(26)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
        .background(Color.black)
    }
}

private struct ReportHazardSheet: View {
    @ObservedObject var viewModel: SurvivViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Report Hazard")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            ForEach(HazardCategory.allCases) { category in
                Button {
                    viewModel.report(category: category)
                    viewModel.showReportSheet = false
                } label: {
                    Text(category.rawValue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .background(SurvivTheme.danger.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color.black.opacity(0.72))
    }
}

private struct ScannerView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.gray.opacity(0.22))
                .padding(24)

            VStack {
                Text("Scan Base Station to Sync")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 40)
                Spacer()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 220, height: 220)

                Circle()
                    .stroke(SurvivTheme.safe.opacity(0.9), lineWidth: 3)
                    .frame(width: pulse ? 140 : 60, height: pulse ? 140 : 60)
                    .opacity(pulse ? 0.15 : 0.9)
                    .animation(.easeOut(duration: 1.25).repeatForever(autoreverses: false), value: pulse)
            }
        }
        .onAppear { pulse = true }
    }
}

private struct CivilianSettingsView: View {
    @ObservedObject var viewModel: SurvivViewModel
    @AppStorage("isAdmin") private var isAdmin = false
    @State private var showPasscodeEntry = false
    @State private var passcodeInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Toggle(isOn: $viewModel.crisisMode) {
                Text("CRISIS MODE")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(SurvivTheme.danger)
            }
            .toggleStyle(.switch)
            .tint(SurvivTheme.danger)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()

            Text("Version 1.0.0")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SurvivTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .onTapGesture(count: 5) {
                    passcodeInput = ""
                    showPasscodeEntry = true
                }
                .padding(.bottom, 120)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .sheet(isPresented: $showPasscodeEntry) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Admin unlock")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(SurvivTheme.textPrimary)
                    Text("Enter the operations passcode.")
                        .font(.subheadline)
                        .foregroundStyle(SurvivTheme.textSecondary)
                    SecureField("Passcode", text: $passcodeInput)
                        .textContentType(.password)
                        .foregroundStyle(SurvivTheme.textPrimary)
                        .padding(12)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    Button("Unlock") {
                        if passcodeInput == "1111" {
                            isAdmin = true
                            showPasscodeEntry = false
                        }
                    }
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        SurvivTheme.safe.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    Spacer()
                }
                .padding(20)
                .background(SurvivTheme.background)
                .navigationTitle("Unlock")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showPasscodeEntry = false }
                            .foregroundStyle(SurvivTheme.safe)
                    }
                }
            }
        }
    }
}

private struct CivilianBottomBar: View {
    @Binding var selectedTab: CivilianTab

    var body: some View {
        HStack(spacing: 10) {
            CivilianTabButton(
                title: "Map",
                icon: "map",
                isSelected: selectedTab == .map
            ) {
                Haptics.impact(.light)
                selectedTab = .map
            }

            CivilianTabButton(
                title: "Scanner",
                icon: "viewfinder",
                isSelected: selectedTab == .scanner
            ) {
                Haptics.impact(.light)
                selectedTab = .scanner
            }

            CivilianTabButton(
                title: "Settings",
                icon: "gearshape",
                isSelected: selectedTab == .settings
            ) {
                Haptics.impact(.light)
                selectedTab = .settings
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct CivilianTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? SurvivTheme.danger.opacity(0.85) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MeshChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.85), in: Capsule())
    }
}
