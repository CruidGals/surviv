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
    @StateObject private var appController: AppController

    init() {
        let container = try! ModelContainer(for: HazardPin.self, AudioRecording.self)
        self.modelContainer = container
        self._appController = StateObject(wrappedValue: AppController(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            RootSurvivView()
                .environmentObject(appController.coordinator)
                .environmentObject(appController.networker)
                .onAppear { appController.coordinator.start() }
        }
        .modelContainer(modelContainer)
    }
}
