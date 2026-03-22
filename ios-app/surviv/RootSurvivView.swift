import SwiftUI

struct RootSurvivView: View {
    @AppStorage("isAdmin") private var isAdmin = false
    @AppStorage("profile.displayName") private var profileDisplayName = ""
    @EnvironmentObject private var coordinator: Coordinator
    @EnvironmentObject private var networker: SurvivNetworker
    @State private var showProfileOnboarding = false

    private var hasProfileName: Bool {
        !profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
            showProfileOnboarding = !hasProfileName
        }
        .onChange(of: isAdmin) { _, newValue in
            networker.applyAppAdminState(newValue)
        }
        .onChange(of: profileDisplayName) { _, newValue in
            showProfileOnboarding = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .sheet(isPresented: $showProfileOnboarding) {
            ProfileNameSheet(
                storedName: $profileDisplayName,
                title: "Set up your profile",
                subtitle: "Your name helps teammates identify your reports and messages.",
                isRequired: true,
                doneButtonTitle: "Continue"
            )
        }
    }
}
