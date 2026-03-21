import SwiftUI
import SwiftData

@MainActor
final class AppController: ObservableObject {
    let networker: SurvivNetworker
    let coordinator: Coordinator

    init(modelContainer: ModelContainer) {
        let networker = SurvivNetworker()
        self.networker = networker
        self.coordinator = Coordinator(modelContainer: modelContainer, networker: networker)
    }
}
