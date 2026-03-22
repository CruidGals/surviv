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
        let container = Self.makeModelContainer()
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

    private static func makeModelContainer() -> ModelContainer {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let primaryConfiguration = ModelConfiguration(isStoredInMemoryOnly: isPreview)

        do {
            return try ModelContainer(
                for: HazardPin.self,
                AudioRecording.self,
                configurations: primaryConfiguration
            )
        } catch {
            // If persistent store creation fails (e.g. sqlite permissions), keep app functional.
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(
                    for: HazardPin.self,
                    AudioRecording.self,
                    configurations: fallback
                )
            } catch {
                fatalError("Failed to create SwiftData ModelContainer: \(error)")
            }
        }
    }
}
