import AppKit
import GrillBreakCore
import SwiftUI
import WebKit

/// Staff Melody Scene: shows the current User Melody engraved by Verovio
/// (MusicXML → SVG inside WKWebView). Empty Melody Library → actionable
/// empty state; countdown remains the overlay's responsibility.
struct StaffMelodySceneMode: BreakSceneMode {
    let identifier = StaffMelodyVisibility.sceneModeIdentifier
    let displayName = "五线谱旋律"

    let library: MelodyLibrary

    @MainActor
    func makeView() -> AnyView {
        let content = StaffMelodyResolver().resolve(library: library)
        return AnyView(StaffMelodySceneView(content: content))
    }
}

struct StaffMelodySceneView: View {
    let content: StaffMelodyContent
    @Environment(\.staffMelodyContentVisible) private var isContentVisible

    var body: some View {
        ZStack {
            background

            if isContentVisible {
                switch content {
                case .empty:
                    emptyState
                case .score(let musicXML):
                    // No light “print card”: engrave on the dark scene. Bottom
                    // inset keeps the score clear of the skip/delay control bar.
                    VerovioScoreView(musicXML: musicXML)
                        .padding(.horizontal, 40)
                        .padding(.top, 40)
                        .padding(.bottom, 110)
                case .failed(let message):
                    messageState(message)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.05, blue: 0.08),
                Color(red: 0.08, green: 0.09, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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

/// Hosts the bundled Verovio toolkit and engraves MusicXML to SVG in-page.
private struct VerovioScoreView: NSViewRepresentable {
    let musicXML: String

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
        guard context.coordinator.lastMusicXML != musicXML else { return }
        context.coordinator.lastMusicXML = musicXML

        do {
            let pageURL = try Self.preparePage(musicXML: musicXML)
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
        var lastMusicXML: String?
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

    private static func preparePage(musicXML: String) throws -> URL {
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
        try StaffMelodyEngravingPage.html(musicXML: musicXML)
            .write(to: pageURL, atomically: true, encoding: .utf8)
        return pageURL
    }
}
