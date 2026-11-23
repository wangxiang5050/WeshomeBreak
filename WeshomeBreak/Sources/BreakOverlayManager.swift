import AppKit
import Combine
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
    private var playbackTimer: Timer?
    private var playbackWatch: AnyCancellable?
    private var lastOutput: PlaybackOutput?
    private let piano = PianoOutput()

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
        session.notePianoLoading()
        watchPlayback(of: session)
        startPlaybackClock()
        piano.prepare { [weak session] ready in
            session?.notePianoReady(ready)
        }
        windows = NSScreen.screens.map { screen in
            makeWindow(for: screen, sceneMode: sceneMode, sceneSession: session)
        }
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        if RestOverlayWitness.isEnabled, session.hoverBarSymbolName != nil {
            session.performHoverBarSymbol()
        }
    }

    /// Closes and releases every overlay window currently shown.
    func dismiss() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        sceneSession?.dismissPlayback()
        windows.forEach { $0.close() }
        windows.removeAll()
        playbackWatch = nil
        lastOutput = nil
        piano.stop()
        sceneSession = nil
    }

    private func watchPlayback(of session: BreakSceneSession) {
        playbackWatch = session.$playbackSound.sink { [piano] moment in
            piano.render(moment)
        }
    }

    private func startPlaybackClock() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickPlayback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func tickPlayback() {
        let output = PlaybackOutputSense.current()
        if output != lastOutput {
            lastOutput = output
            sceneSession?.notePlaybackOutput(output)
        }
        if let seconds = piano.musicalSeconds(now: Date().timeIntervalSinceReferenceDate) {
            sceneSession?.placePlayback(at: seconds)
        }
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
