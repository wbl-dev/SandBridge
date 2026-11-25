import SwiftUI

@main
struct SandBridgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 720)
    }
}
