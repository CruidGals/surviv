import SwiftUI
import MapKit

enum AdminTab {
    case masterMap
    case queue
    case intel
    case node
}

struct AdminTabView: View {
    @ObservedObject var viewModel: SurvivViewModel
    @Binding var isAdmin: Bool
    @State private var selectedTab: AdminTab = .masterMap

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .masterMap:
                    MasterMapView(viewModel: viewModel)
                case .queue:
                    ThreatQueueView(viewModel: viewModel)
                case .intel:
                    GeminiIntelView(viewModel: viewModel)
                case .node:
                    NodeSetupView(isAdmin: $isAdmin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AdminBottomBar(selectedTab: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }
}

private struct MasterMapView: View {
    @ObservedObject var viewModel: SurvivViewModel

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.zones) { zone in
                MapAnnotation(coordinate: zone.center) {
                    Circle()
                        .fill(zone.kind == .danger ? SurvivTheme.danger : SurvivTheme.safe)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            HStack(spacing: 10) {
                Button {
                    viewModel.drawAtCenter(.danger)
                } label: {
                    Label("Draw Red Zone", systemImage: "pencil.and.outline")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(SurvivTheme.danger.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.drawAtCenter(.safeRoute)
                } label: {
                    Label("Draw Green Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(SurvivTheme.safe.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
    }
}

private struct ThreatQueueView: View {
    @ObservedObject var viewModel: SurvivViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.threatQueue) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.type)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        HStack {
                            Text(item.timeLabel)
                            Text("•")
                            Text(item.distanceLabel)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(SurvivTheme.textSecondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.black)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Quarantine", role: .destructive) {
                            viewModel.quarantine(item)
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Broadcast") {
                            viewModel.broadcast(item)
                        }
                        .tint(SurvivTheme.safe)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Threat Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

private struct GeminiIntelView: View {
    @ObservedObject var viewModel: SurvivViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("GEMINI INTEL")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(viewModel.sitrepText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SurvivTheme.safe)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SurvivTheme.safe.opacity(0.45), lineWidth: 1)
                    )
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct NodeSetupView: View {
    @Binding var isAdmin: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 24)
                Text("Anchor Node Active")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Ready for Civilian Sync")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SurvivTheme.textSecondary)

                ZStack {
                    Circle()
                        .stroke(SurvivTheme.safe.opacity(0.28), lineWidth: 6)
                        .frame(width: pulse ? 320 : 240, height: pulse ? 320 : 240)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 250, height: 250)
                        .overlay(
                            Image(systemName: "qrcode")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white)
                                .padding(34)
                        )
                }

                Spacer()

                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                        isAdmin = false
                    }
                } label: {
                    Text("Demote to Civilian")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .background(SurvivTheme.danger.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .onAppear { pulse = true }
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
            AdminTabButton(title: "Queue", icon: "tray.full", isSelected: selectedTab == .queue) {
                Haptics.impact(.light)
                selectedTab = .queue
            }
            AdminTabButton(title: "Intel", icon: "terminal", isSelected: selectedTab == .intel) {
                Haptics.impact(.light)
                selectedTab = .intel
            }
            AdminTabButton(title: "Node", icon: "qrcode", isSelected: selectedTab == .node) {
                Haptics.impact(.light)
                selectedTab = .node
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
