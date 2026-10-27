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
    let settingsStore: BreakSettingsStore
    let breakCycle: BreakCycle
    let selectionState: MelodySelectionState

    @MainActor
    func makeSession() -> BreakSceneSession {
        let melody = selectionState.beginPresentation(
            melodies: library.melodies(),
            using: melodyStrategy(),
            continuingSameRest: breakCycle.continuesSameRest
        )
        if settingsStore.lastShownMelodyID != selectionState.lastShownMelodyID {
            settingsStore.lastShownMelodyID = selectionState.lastShownMelodyID
        }
        return StaffMelodySceneSession(melodyID: melody?.id)
    }

    @MainActor
    func makeView() -> AnyView {
        makeView(session: makeSession())
    }

    @MainActor
    func makeView(session: BreakSceneSession) -> AnyView {
        // `BreakOverlayView` calls this once per screen, when its window is
        // created. The melody was chosen once in `makeSession()`, so every
        // screen engraves the same User Melody. Scale and Duration Proportion
        // are read here, so a delay that presents again picks up the current
        // values while keeping that melody.
        let melodyID = (session as? StaffMelodySceneSession)?.melodyID
        let page = StaffMelodyPage.prepare(
            from: library,
            melodyID: melodyID,
            scalePercent: settingsStore.staffNotationScalePercent,
            durationProportionPercent: settingsStore.durationProportionPercent
        )
        return AnyView(StaffMelodySceneView(page: page, session: session))
    }

    /// Random only while Scene Mode Selection is fixed to this scene and the
    /// user has turned 「随机旋律」 on. Otherwise the manual current melody.
    @MainActor
    private func melodyStrategy() -> MelodySelectionStrategy {
        let fixedToStaffMelody = settingsStore.sceneModeSelectionRaw == identifier
        if settingsStore.randomMelodyEnabled && fixedToStaffMelody {
            return .randomNoRepeat
        }
        return .manual(melodyID: library.selectedMelodyID)
    }
}

struct StaffMelodySceneView: View {
    let page: StaffMelodyPage
    @ObservedObject var session: BreakSceneSession

    var body: some View {
        ZStack {
            StaffMelodyEngravingBackground()

            if session.showsContent {
                // Bottom inset keeps the score clear of the skip/delay
                // control bar; the Melody Preview window has no such bar.
                StaffMelodyPageContent(page: page)
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 110)
            }
        }
        .ignoresSafeArea()
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

    var body: some View {
        switch page {
        case .empty:
            emptyState
        case .ready(let html):
            VerovioScoreView(html: html)
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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
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

    final class Coordinator {
        var lastHTML: String?
        private var pageDirectory: URL?

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
