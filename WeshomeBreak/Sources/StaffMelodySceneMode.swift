import GrillBreakCore
import SwiftUI
import WebKit

/// Staff Melody Scene: shows the current User Melody engraved by Verovio
/// (MusicXML → SVG inside WKWebView). Empty Melody Library → actionable
/// empty state; countdown remains the overlay's responsibility.
struct StaffMelodySceneMode: BreakSceneMode {
    let identifier = "staff-melody"
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

    var body: some View {
        ZStack {
            background

            switch content {
            case .empty:
                emptyState
            case .score(let musicXML):
                VerovioScoreView(musicXML: musicXML)
                    .padding(32)
                    .background(Color.white.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(40)
            case .failed(let message):
                messageState(message)
            }
        }
        .ignoresSafeArea()
    }

    private var background: some View {
        // Dark surround keeps the overlay countdown (white) readable; the
        // Verovio SVG itself stays on a light print-style surface (ADR Phase 1).
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
        let webView = WKWebView(frame: .zero)
        webView.setValue(false, forKey: "drawsBackground")
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
                "<html><body style='font-family:-apple-system;text-align:center;padding:40px;color:#666'>谱面渲染资源缺失</body></html>",
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
        try makeHTML(musicXML: musicXML).write(to: pageURL, atomically: true, encoding: .utf8)
        return pageURL
    }

    private static func makeHTML(musicXML: String) -> String {
        let payload = Data(musicXML.utf8).base64EncodedString()
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              display: flex;
              align-items: center;
              justify-content: center;
              overflow: hidden;
            }
            #notation {
              max-width: 96%;
              max-height: 92%;
            }
            #notation svg {
              max-width: 100%;
              height: auto;
            }
            #status {
              font: 18px -apple-system, sans-serif;
              color: #666;
            }
          </style>
          <script src="verovio-toolkit-wasm.js"></script>
        </head>
        <body>
          <div id="notation"><div id="status">正在镌刻谱面…</div></div>
          <script>
            (function () {
              const encoded = "\(payload)";
              const binary = atob(encoded);
              const bytes = new Uint8Array(binary.length);
              for (let i = 0; i < binary.length; i++) {
                bytes[i] = binary.charCodeAt(i);
              }
              const musicXML = new TextDecoder("utf-8").decode(bytes);

              function render() {
                try {
                  const tk = new verovio.toolkit();
                  tk.setOptions({
                    scale: 40,
                    adjustPageHeight: true,
                    footer: "none",
                    header: "none"
                  });
                  if (!tk.loadData(musicXML)) {
                    document.getElementById("notation").innerHTML =
                      "<div id='status'>谱面加载失败</div>";
                    return;
                  }
                  document.getElementById("notation").innerHTML = tk.renderToSVG(1);
                } catch (error) {
                  document.getElementById("notation").innerHTML =
                    "<div id='status'>谱面渲染失败</div>";
                }
              }

              if (typeof verovio !== "undefined" && verovio.module) {
                verovio.module.onRuntimeInitialized = render;
              } else {
                document.getElementById("notation").innerHTML =
                  "<div id='status'>Verovio 未能初始化</div>";
              }
            })();
          </script>
        </body>
        </html>
        """
    }
}
