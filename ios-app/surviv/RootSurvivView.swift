import SwiftUI

struct RootSurvivView: View {
    @AppStorage("isAdmin") private var isAdmin = false
    @EnvironmentObject private var coordinator: Coordinator
    @EnvironmentObject private var networker: SurvivNetworker
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if isAdmin {
                    AdminTabView(isAdmin: $isAdmin)
                } else {
                    ContentView()
                }
            }
            .onAppear {
                networker.applyAppAdminState(isAdmin)
            }
            .onChange(of: isAdmin) { _, newValue in
                networker.applyAppAdminState(newValue)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 1.4)) {
                    showSplash = false
                }
            }
        }
    }
}

private struct SplashView: View {
    @State private var logoScale: CGFloat = 0.82
    @State private var logoOpacity: Double = 0
    @State private var sloganOffset: CGFloat = 10
    @State private var sloganOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image("SurvivLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Text("Stay connected when the world goes dark.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .offset(y: sloganOffset)
                    .opacity(sloganOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.6)) {
                sloganOpacity = 1.0
                sloganOffset = 0
            }
        }
    }
}
