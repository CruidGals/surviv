import SwiftUI

struct RootSurvivView: View {
    @AppStorage("isAdmin") private var isAdmin = false
    @EnvironmentObject private var coordinator: Coordinator
    @EnvironmentObject private var networker: SurvivNetworker

    var body: some View {
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
    }
}
