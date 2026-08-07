import AppKit
import GrillBreakCore
import SwiftUI

/// A borderless `NSWindow` normally can't become key window, which would
/// silently swallow clicks on the overlay's skip/delay buttons. Overriding
/// `canBecomeKey` is what lets `makeKeyAndOrderFront` actually work.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Manages one full-screen `NSWindow` per connected display, each hosting
/// `BreakOverlayView`. AppKit (not SwiftUI's `Window`/`WindowGroup`) is used
/// here deliberately: SwiftUI has no API to precisely target "all current
/// screens" with a window level above regular apps, which is required to
/// reliably cover the Dock and menu bar during a break.
@MainActor
final class BreakOverlayManager {
    private var windows: [NSWindow] = []

    var isPresenting: Bool { !windows.isEmpty }

    /// Creates and shows one overlay window per screen currently connected.
    /// Calling this while overlays are already presented has no effect —
    /// call `dismiss()` first if you need to re-present.
    func present(schedulerController: BreakSchedulerController, sceneMode: BreakSceneMode) {
        guard windows.isEmpty else { return }

        windows = NSScreen.screens.map { screen in
            makeWindow(for: screen, schedulerController: schedulerController, sceneMode: sceneMode)
        }
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    /// Closes and releases every overlay window currently shown.
    func dismiss() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func makeWindow(
        for screen: NSScreen,
        schedulerController: BreakSchedulerController,
        sceneMode: BreakSceneMode
    ) -> NSWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        // NSWindow defaults to `isReleasedWhenClosed = true`, which makes
        // AppKit autorelease the window itself on `close()` — on top of the
        // strong ARC reference we keep in `windows`, this double-releases
        // the window and crashes (SIGSEGV during autorelease pool drain) on
        // the very next present/dismiss cycle. We own this window's
        // lifetime exclusively through `windows`, so opt out.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: BreakOverlayView(schedulerController: schedulerController, sceneMode: sceneMode)
        )
        return window
    }
}
