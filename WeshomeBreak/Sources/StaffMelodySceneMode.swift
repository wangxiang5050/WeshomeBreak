import AppKit
import GrillBreakCore
import SwiftUI
import WebKit

/// Staff Melody Scene: engraves the User Melody chosen for this rest
/// (Staff Melody Page HTML → SVG inside WKWebView). An empty choice shows
/// the actionable empty state; countdown remains the overlay's responsibility.
extension StaffMelodyPage {
    /// Melody Preview engraves the manual current melody at the current
    /// Staff Notation Scale and Duration Proportion. The rest overlay does
    /// not use this path: it engraves the melody chosen for that rest.
    @MainActor
    static func prepare(from library: MelodyLibrary, settingsStore: BreakSettingsStore) -> StaffMelodyPage {
        prepare(
            from: library,
            scalePercent: settingsStore.staffNotationScalePercent,
            durationProportionPercent: settingsStore.durationProportionPercent
        )
    }
}

struct StaffMelodySceneMode: BreakSceneMode {
    let identifier = StaffMelodySceneSession.sceneModeIdentifier
    let displayName = "五线谱旋律"

    let library: MelodyLibrary
    let melodyLibraryStore: MelodyLibraryStore
    let settingsStore: BreakSettingsStore
    let breakCycle: BreakCycle
    let selectionState: MelodySelectionState

    @MainActor
    func makeSession() -> BreakSceneSession {
        let session = StaffMelodySceneSession()
        session.beginRest(
            in: library,
            using: MelodySelection.strategy(
                randomMelodyEnabled: settingsStore.randomMelodyEnabled,
                sceneModeSelectionRaw: settingsStore.sceneModeSelectionRaw,
                staffMelodySceneIdentifier: identifier,
                manualMelodyID: library.selectedMelodyID
            ),
            continuingSameRest: breakCycle.continuesSameRest,
            selection: selectionState,
            scalePercent: settingsStore.staffNotationScalePercent,
            durationProportionPercent: settingsStore.durationProportionPercent,
            tempo: settingsStore.playbackTempo
        )
        return session
    }

    @MainActor
    func makeView() -> AnyView {
        makeView(session: makeSession())
    }

    @MainActor
    func makeView(session: BreakSceneSession) -> AnyView {
        // `BreakOverlayView` calls this once per screen, when its window is
        // created. The melody and Staff Melody Page were chosen once in
        // `makeSession()`, so every screen shows the same page. A delay
        // presents again and reads the current scale while keeping that melody.
        guard let staffSession = session as? StaffMelodySceneSession else {
            return AnyView(EmptyView())
        }
        return AnyView(StaffMelodySceneView(
            melodyLibraryStore: melodyLibraryStore,
            session: staffSession,
            onLibraryChanged: { [self] session in
                session.libraryChanged(in: library)
            }
        ))
    }
}

struct StaffMelodySceneView: View {
    @ObservedObject var melodyLibraryStore: MelodyLibraryStore
    @ObservedObject var session: StaffMelodySceneSession
    let onLibraryChanged: (StaffMelodySceneSession) -> Void

    var body: some View {
        ZStack {
            StaffMelodyEngravingBackground()

            if session.showsContent {
                // Bottom inset keeps the score clear of the skip/delay
                // control bar; the Melody Preview window has no such bar.
                StaffMelodyPageContent(page: session.page, playbackLine: session.playbackLine)
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea()
        .onChange(of: melodyLibraryStore.revision) { _, _ in
            onLibraryChanged(session)
        }
    }
}

/// Dark gradient behind every Staff Melody Page presentation: the Staff
/// Melody Scene during a break, and the Melody Preview window in Settings.
struct StaffMelodyEngravingBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.05, blue: 0.08),
                Color(red: 0.08, green: 0.09, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Renders a Staff Melody Page's empty / failed / ready state. Shared by the
/// Staff Melody Scene and the Melody Preview window so both engrave
/// identically — no light "print card", white ink on the dark background.
struct StaffMelodyPageContent: View {
    let page: StaffMelodyPage
    var playbackLine: PlaybackLine? = nil

    var body: some View {
        switch page {
        case .empty:
            emptyState
        case .ready(let html):
            VerovioScoreView(html: html, playbackLine: playbackLine)
        case .failed(let message):
            messageState(message)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("还没有可哼唱的旋律")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("请先在设置中导入旋律")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }

    private func messageState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(40)
    }
}

/// Score Rendering adapter: hosts bundled Verovio and loads a Staff Melody Page.
private struct VerovioScoreView: NSViewRepresentable {
    let html: String
    var playbackLine: PlaybackLine?

    func makeNSView(context: Context) -> WKWebView {
        // drawsBackground must be set on the configuration *before* init;
        // setting it only on the instance leaves macOS WKWebView opaque white.
        let configuration = WKWebViewConfiguration()
        configuration.setValue(false, forKey: "drawsBackground")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.playbackLine = playbackLine
        if context.coordinator.lastHTML == html {
            context.coordinator.pushLine(on: webView)
            return
        }
        context.coordinator.lastHTML = html

        do {
            let pageURL = try Self.preparePage(html: html)
            context.coordinator.replacePageDirectory(pageURL.deletingLastPathComponent())
            webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        } catch {
            webView.loadHTMLString(
                "<html><body style='font-family:-apple-system;text-align:center;padding:40px;color:rgba(255,255,255,0.55);background:transparent'>谱面渲染资源缺失</body></html>",
                baseURL: nil
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var playbackLine: PlaybackLine?
        private var pageDirectory: URL?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pushLine(on: webView)
        }

        func pushLine(on webView: WKWebView) {
            let script: String
            if let playbackLine {
                script = """
                if (window.placePlaybackLine) {
                  window.placePlaybackLine(\(playbackLine.eventIndex), \(playbackLine.fractionThroughEvent));
                } else {
                  window.pendingPlaybackLine = [\(playbackLine.eventIndex), \(playbackLine.fractionThroughEvent)];
                }
                """
            } else {
                script = """
                if (window.placePlaybackLine) { window.placePlaybackLine(-1, 0); }
                window.pendingPlaybackLine = [-1, 0];
                """
            }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func replacePageDirectory(_ directory: URL) {
            if let pageDirectory {
                try? FileManager.default.removeItem(at: pageDirectory)
            }
            pageDirectory = directory
        }

        deinit {
            if let pageDirectory {
                try? FileManager.default.removeItem(at: pageDirectory)
            }
        }
    }

    private static func preparePage(html: String) throws -> URL {
        guard let scriptURL = Bundle.main.url(forResource: "verovio-toolkit-wasm", withExtension: "js") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-melody-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: scriptURL,
            to: directory.appendingPathComponent("verovio-toolkit-wasm.js")
        )

        let pageURL = directory.appendingPathComponent("score.html")
        try html.write(to: pageURL, atomically: true, encoding: .utf8)
        return pageURL
    }
}
