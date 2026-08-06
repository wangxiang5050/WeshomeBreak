import SwiftUI

struct MenuBarContentView: View {
    var body: some View {
        Button("退出 App") {
            NSApplication.shared.terminate(nil)
        }
    }
}
