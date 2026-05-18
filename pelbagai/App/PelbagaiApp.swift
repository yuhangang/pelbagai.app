//
//  PelbagaiApp.swift
//  Pelbagai
//
//  Created by Ang Yu Hang on 07/05/2026.
//

import SwiftUI

@main
struct PelbagaiApp: App {
    @StateObject private var environment: AppEnvironment
    @StateObject private var mainViewModel: MainViewModel
    
    init() {
        let env = AppEnvironment()
        self._environment = StateObject(wrappedValue: env)
        self._mainViewModel = StateObject(wrappedValue: MainViewModel(environment: env))
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(environment)
                .environmentObject(mainViewModel)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background:
                        environment.mlx.handleBackground()
                    case .active, .inactive:
                        environment.mlx.handleForeground()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
