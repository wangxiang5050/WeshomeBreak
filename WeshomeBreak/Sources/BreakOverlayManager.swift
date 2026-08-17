import AppKit
import GrillBreakCore
import SwiftUI

/// A borderless `NSWindow` normally can't become key window, which would
/// silently swallow clicks on the overlay's skip/delay buttons. Overriding
/// `canBecomeKey` is what lets `makeKeyAndOrderFront` actually work.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// AppKit adapter for Rest Overlay: one full-screen `NSWindow` per connected
/// display, each hosting `BreakOverlayView`. SwiftUI has no API to precisely
/// target "all current screens" with a window level above regular apps.
@MainActor
final class BreakOverlayManager: RestOverlayWindows {
    private let breakCycle: BreakCycle
    private let settingsStore: BreakSettingsStore
    private var windows: [NSWindow] = []

    private var sceneSession: BreakSceneSession?

    init(breakCycle: BreakCycle, settingsStore: BreakSettingsStore) {
        self.breakCycle = breakCycle
        self.settingsStore = settingsStore
    }

    var isPresenting: Bool { !windows.isEmpty }

    /// Creates and shows one overlay window per screen currently connected.
    /// Calling this while overlays are already presented has no effect —
    /// call `dismiss()` first if you need to re-present.
    func present(sceneMode: BreakSceneMode) {
        guard windows.isEmpty else { return }

        let session = sceneMode.makeSession()
        sceneSession = session
        windows = NSScreen.screens.map { screen in
            makeWindow(for: screen, sceneMode: sceneMode, sceneSession: session)
        }
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }

    /// Closes and releases every overlay window currently shown.
    func dismiss() {
        windows.forEach { $0.close() }
        windows.removeAll()
        sceneSession = nil
    }

    private func makeWindow(
        for screen: NSScreen,
        sceneMode: BreakSceneMode,
        sceneSession: BreakSceneSession
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
            rootView: BreakOverlayView(
                breakCycle: breakCycle,
                sceneMode: sceneMode,
                settingsStore: settingsStore,
                sceneSession: sceneSession
            )
        )
        return window
    }
}
