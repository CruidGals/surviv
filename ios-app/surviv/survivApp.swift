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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: HazardPin.self)
    }
}
