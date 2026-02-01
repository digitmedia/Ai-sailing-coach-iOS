//
//  AISailingCoachApp.swift
//  AISailingCoach
//
//  AI Sailing Coach - Tactical sailing instrument & coaching app
//  Based on Spatial Sail design system
//

import SwiftUI

@main
struct AISailingCoachApp: App {
    @StateObject private var viewModel = SailingViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
