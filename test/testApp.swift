//
//  testApp.swift
//  test
//
//  Created by Samy 📍 on 17/06/2025.
//

import SwiftUI

@main
struct VizAiApp: App {
    var body: some Scene {
        WindowGroup {
            MainAppView() // Utilise MainAppView au lieu de ContentView
                .preferredColorScheme(.dark)
        }
    }
}
