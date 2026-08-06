import SwiftUI

@main
struct WeshomeBreakApp: App {
    var body: some Scene {
        MenuBarExtra("Weshome Break", systemImage: "cup.and.saucer.fill") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}
