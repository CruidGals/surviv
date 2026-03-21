//
//  survivApp.swift
//  surviv
//
//  Created by Khai Ta on 3/21/26.
//

import SwiftUI
import SwiftData

@main
struct survivApp: App {
    let modelContainer: ModelContainer
    @StateObject private var coordinator: Coordinator

    init() {
        let container = try! ModelContainer(for: HazardPin.self, AudioRecording.self)
        self.modelContainer = container
        self._coordinator = StateObject(wrappedValue: Coordinator(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .onAppear { coordinator.start() }
        }
        .modelContainer(modelContainer)
    }
}
