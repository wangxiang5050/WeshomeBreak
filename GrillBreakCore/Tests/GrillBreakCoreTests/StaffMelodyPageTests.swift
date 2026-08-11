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
        let page = StaffMelodyPage.prepare(from: library)

        #expect(page == .empty)
    }

    @Test
    func readyWhenCurrentMelodyExists() throws {
        let (library, root) = try makeLibrary(importing: MusicXMLFixtures.simpleFourMeasures)
        defer { try? FileManager.default.removeItem(at: root) }

        let page = StaffMelodyPage.prepare(from: library)

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

        let page = StaffMelodyPage.prepare(from: library)

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
    func readyUsesFourMeasuresPerSystemAt150PercentScale() throws {
        let html = try readyHTML(from: MusicXMLFixtures.nineMeasures)

        #expect(html.contains("scale: 60"))
        #expect(html.contains("breaks: \"encoded\""))
        #expect(html.contains("pageWidth: 1200"))
        #expect(!html.contains("scale: 40"))
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

    private func readyHTML(from musicXML: String) throws -> String {
        let (library, root) = try makeLibrary(importing: musicXML)
        defer { try? FileManager.default.removeItem(at: root) }

        let page = StaffMelodyPage.prepare(from: library)
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
