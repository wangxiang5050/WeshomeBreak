# MusicXML + Verovio for Staff Melody

Staff Melody Scene must show a readable, hummable User Melody—not decorative random notes. We store melodies as MusicXML (`.musicxml` / `.mxl`) and engrave accepted files with Verovio (SVG). Offline authoring/OMR uses Audiveris (image→MusicXML) and MuseScore (proof/edit/export); the app imports the result into a Melody Library with manual Melody Selection.

## Considered Options

- **ABC or custom JSON** for storage — lighter, but weak OMR path and poorer interchange with MuseScore/Audiveris.
- **Custom Canvas renderer** — full visual control (e.g. dark theme), but high risk of incorrect beams/ties/spacing versus “correct enough to hum.”
- **Let Verovio accept arbitrary MusicXML** — rejected for v1; import still enforces the monophonic subset gate so the app never silently drops musical meaning.

## Consequences

- Phase 1 is static engraving (no fly-in animation; dark theme is follow-up polish).
- Empty Melody Library shows an actionable empty state; countdown still runs.
- Later Melody Selection strategies (e.g. random) and in-app image capture are extensions, not Phase 1.
- Phase 1 embeds the official Verovio JavaScript/WASM toolkit in a `WKWebView` (MusicXML → SVG in-page) rather than the native Swift SPM binding: the C++ package fetch/build was too heavy for this app target, while the JS toolkit is the same engraver and keeps the ADR’s Verovio→SVG contract.
