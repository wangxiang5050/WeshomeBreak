import Foundation
import Testing
@testable import GrillBreakCore

@Suite("StaffMelodyPage")
struct StaffMelodyPageTests {

    @Test
    func emptyWhenNoCurrentMelody() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-melody-page-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = MelodyLibrary(rootDirectory: root)
        let page = StaffMelodyPage.prepare(from: library, scalePercent: 60)

        #expect(page == .empty)
    }

    @Test
    func readyWhenCurrentMelodyExists() throws {
        let (library, root) = try makeLibrary(importing: MusicXMLFixtures.simpleFourMeasures)
        defer { try? FileManager.default.removeItem(at: root) }

        let page = StaffMelodyPage.prepare(from: library, scalePercent: 60)

        guard case .ready(let html) = page else {
            Issue.record("expected ready page, got \(page)")
            return
        }
        let laidOut = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: MusicXMLSystemBreakLayout.measuresPerSystem,
            to: MusicXMLFixtures.simpleFourMeasures
        )
        let payload = Data(laidOut.utf8).base64EncodedString()
        #expect(html.contains(payload))
    }

    @Test
    func failedWhenScoreFileMissing() throws {
        let (library, root) = try makeLibrary(importing: MusicXMLFixtures.simpleFourMeasures)
        defer { try? FileManager.default.removeItem(at: root) }

        guard let melody = library.currentMelody() else {
            Issue.record("expected a current melody after import")
            return
        }
        let scoreURL = root.appendingPathComponent("scores/\(melody.id.uuidString).musicxml")
        try FileManager.default.removeItem(at: scoreURL)

        let page = StaffMelodyPage.prepare(from: library, scalePercent: 60)

        guard case .failed(let message) = page else {
            Issue.record("expected failed page, got \(page)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test
    func readyUsesTransparentPageBackground() throws {
        let html = try readyHTML(from: MusicXMLFixtures.simpleFourMeasures)

        #expect(html.contains("background: transparent"))
        #expect(!html.contains("background: white"))
        #expect(!html.contains("background:#fff"))
        #expect(!html.contains("background: #fff"))
    }

    @Test
    func readyForcesWhiteNotationInk() throws {
        let html = try readyHTML(from: MusicXMLFixtures.simpleFourMeasures)

        #expect(html.contains("#notation svg *"))
        #expect(html.contains("fill: #ffffff !important"))
        #expect(html.contains("[stroke]:not([stroke=\"none\"])"))
        #expect(html.contains("applyWhiteInk"))
        #expect(!html.contains("filter: brightness(0) invert(1)"))
    }

    @Test
    func readyUsesFourMeasuresPerSystemAtAFixedVerovioScale() throws {
        let html = try readyHTML(from: MusicXMLFixtures.nineMeasures, scalePercent: 60)

        // Verovio's own `scale` only changes the exported SVG's pixel
        // dimensions, not glyph size relative to it, so it has no visible
        // effect once `#notation svg` is stretched to fill its container —
        // it stays fixed regardless of the requested Staff Notation Scale.
        // (See `readySizesNotationContainerByRequestedScalePercent` below
        // for what actually makes the score look bigger or smaller.)
        #expect(html.contains("scale: 100"))
        #expect(html.contains("breaks: \"encoded\""))
        #expect(html.contains("pageWidth: 1200"))
    }

    @Test
    func readySizesNotationContainerByRequestedScalePercent() throws {
        let atMax = try readyHTML(from: MusicXMLFixtures.nineMeasures, scalePercent: 100)
        #expect(atMax.contains("width: 96.0%;"))
        #expect(atMax.contains("max-height: 92.0%;"))

        let atDefault = try readyHTML(from: MusicXMLFixtures.nineMeasures, scalePercent: 60)
        #expect(atDefault.contains("width: 57.6%;"))
        #expect(atDefault.contains("max-height: 55.2%;"))

        let atMin = try readyHTML(from: MusicXMLFixtures.nineMeasures, scalePercent: 40)
        #expect(atMin.contains("width: 38.4%;"))
        #expect(atMin.contains("max-height: 36.8%;"))
    }

    @Test
    func readyScalesNotationToFillSceneWidth() throws {
        let html = try readyHTML(from: MusicXMLFixtures.simpleFourMeasures)

        let svgRuleStart = html.range(of: "#notation svg {")
        #expect(svgRuleStart != nil)
        guard let svgRuleStart else { return }
        let afterRule = html[svgRuleStart.lowerBound...]
        let nextRule = afterRule.range(of: "\n            /*") ?? afterRule.range(of: "#notation svg *")
        let rule = nextRule.map { String(afterRule[..<$0.lowerBound]) } ?? String(afterRule.prefix(200))
        #expect(rule.contains("width: 100%;"))
    }

    @Test
    func readyEmbedsLaidOutMusicXMLPayload() throws {
        let xml = MusicXMLFixtures.nineMeasures
        let html = try readyHTML(from: xml)
        let laidOut = try MusicXMLSystemBreakLayout.applying(measuresPerSystem: 4, to: xml)
        let payload = Data(laidOut.utf8).base64EncodedString()

        #expect(html.contains(payload))
    }

    // MARK: - Helpers

    private func readyHTML(from musicXML: String, scalePercent: Int = 60) throws -> String {
        let (library, root) = try makeLibrary(importing: musicXML)
        defer { try? FileManager.default.removeItem(at: root) }

        let page = StaffMelodyPage.prepare(from: library, scalePercent: scalePercent)
        guard case .ready(let html) = page else {
            Issue.record("expected ready page, got \(page)")
            return ""
        }
        return html
    }

    private func makeLibrary(importing musicXML: String) throws -> (MelodyLibrary, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("staff-melody-page-\(UUID().uuidString)", isDirectory: true)
        let library = MelodyLibrary(rootDirectory: root)
        let outcome = library.importMusicXML(musicXML)
        guard case .imported = outcome else {
            Issue.record("expected import to succeed, got \(outcome)")
            throw CocoaError(.fileWriteUnknown)
        }
        return (library, root)
    }
}
