//
//  SinRutinaApp.swift
//  SinRutina
//
//  Created by Rork on August 12, 2026.
//

import AppIntents
import SwiftUI
import SwiftData

@main
struct SinRutinaApp: App {
    @State private var session = AppSession()

    init() {
        // Siri and Spotlight can only find the shortcuts if they are registered
        // at launch.
        SinRutinaShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .modelContainer(SRIntentRuntime.container)
    }
}
