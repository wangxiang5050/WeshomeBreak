import Foundation

/// Internal HTML builder for Staff Melody Page (transparent page + white ink).
/// Callers use `StaffMelodyPage.prepare`; Verovio still runs in the app adapter.
enum StaffMelodyEngravingPage {
    /// The footprint at `scalePercent == 100`: Verovio's own `scale` option
    /// only changes the exported SVG's pixel dimensions, not the size of
    /// glyphs relative to that SVG — so once `#notation svg` is stretched to
    /// fill its container (below), varying Verovio's `scale` has no visible
    /// effect at all. The Staff Notation Scale setting therefore sizes
    /// `#notation` itself, as a fraction of this baseline footprint.
    private static let maxNotationWidthPercent = 96.0
    private static let maxNotationMaxHeightPercent = 92.0

    static func html(musicXML: String, scalePercent: Int) -> String {
        let laidOut =
            (try? MusicXMLSystemBreakLayout.applying(
                measuresPerSystem: MusicXMLSystemBreakLayout.measuresPerSystem,
                to: musicXML
            )) ?? musicXML
        let payload = Data(laidOut.utf8).base64EncodedString()
        let fraction = Double(scalePercent) / 100
        let notationWidthPercent = Self.formatted(maxNotationWidthPercent * fraction)
        let notationMaxHeightPercent = Self.formatted(maxNotationMaxHeightPercent * fraction)
        let pageWidth = MusicXMLSystemBreakLayout.pageWidth
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
              width: \(notationWidthPercent)%;
              max-height: \(notationMaxHeightPercent)%;
              background: transparent;
            }
            #notation svg {
              width: 100%;
              max-width: 100%;
              height: auto;
              background: transparent;
              color: #ffffff;
            }
            /* Verovio noteheads/clefs/beams are often bare <use> with no fill
               attribute (SVG default black). Force every glyph to white ink. */
            #notation svg * {
              fill: #ffffff !important;
              color: #ffffff !important;
            }
            #notation svg [fill="none"] {
              fill: none !important;
            }
            #notation svg [stroke]:not([stroke="none"]) {
              stroke: #ffffff !important;
            }
            #status {
              font: 18px -apple-system, sans-serif;
              color: rgba(255, 255, 255, 0.55);
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

              function applyWhiteInk(container) {
                const svg = container.querySelector("svg");
                if (!svg) return;
                svg.style.color = "#ffffff";
                // Also set attributes: CSS covers most cases; this catches
                // bare <use> glyphs that otherwise inherit SVG default black.
                svg.querySelectorAll("*").forEach((el) => {
                  const fill = el.getAttribute("fill");
                  if (fill !== "none" && fill !== "transparent") {
                    el.setAttribute("fill", "#ffffff");
                  }
                  const stroke = el.getAttribute("stroke");
                  if (stroke && stroke !== "none" && stroke !== "transparent") {
                    el.setAttribute("stroke", "#ffffff");
                  }
                  if (el.style) {
                    if (el.style.fill && el.style.fill !== "none") {
                      el.style.fill = "#ffffff";
                    }
                    if (el.style.stroke && el.style.stroke !== "none") {
                      el.style.stroke = "#ffffff";
                    }
                  }
                });
              }

              function render() {
                try {
                  const tk = new verovio.toolkit();
                  tk.setOptions({
                    scale: 100,
                    breaks: "encoded",
                    pageWidth: \(pageWidth),
                    adjustPageHeight: true,
                    footer: "none",
                    header: "none"
                  });
                  if (!tk.loadData(musicXML)) {
                    document.getElementById("notation").innerHTML =
                      "<div id='status'>谱面加载失败</div>";
                    return;
                  }
                  const notation = document.getElementById("notation");
                  notation.innerHTML = tk.renderToSVG(1);
                  applyWhiteInk(notation);
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

    /// One decimal place, e.g. `81.6` — steady formatting regardless of
    /// floating-point rounding noise from the `fraction` multiplication.
    private static func formatted(_ percent: Double) -> String {
        String(format: "%.1f", percent)
    }
}
