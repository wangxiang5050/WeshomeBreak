import Foundation
import Testing
@testable import GrillBreakCore

@Suite("StaffMelodyEngravingPage")
struct StaffMelodyEngravingPageTests {

    @Test
    func htmlUsesTransparentPageBackground() {
        let html = StaffMelodyEngravingPage.html(musicXML: "<score-partwise/>")

        #expect(html.contains("background: transparent"))
        #expect(!html.contains("background: white"))
        #expect(!html.contains("background:#fff"))
        #expect(!html.contains("background: #fff"))
    }

    @Test
    func htmlForcesWhiteNotationInk() {
        let html = StaffMelodyEngravingPage.html(musicXML: "<score-partwise/>")

        // Verovio noteheads/clefs are bare <use> with no fill attr (SVG default
        // black). Force fill/stroke/color via CSS so every glyph is white.
        #expect(html.contains("#notation svg *"))
        #expect(html.contains("fill: #ffffff !important"))
        #expect(html.contains("[stroke]:not([stroke=\"none\"])"))
        #expect(html.contains("applyWhiteInk"))
        #expect(!html.contains("filter: brightness(0) invert(1)"))
    }

    @Test
    func htmlEmbedsMusicXMLPayload() throws {
        let xml = MusicXMLFixtures.nineMeasures
        let laidOut = try MusicXMLSystemBreakLayout.applying(measuresPerSystem: 4, to: xml)
        let html = StaffMelodyEngravingPage.html(musicXML: xml)
        let payload = Data(laidOut.utf8).base64EncodedString()

        #expect(html.contains(payload))
    }

    @Test
    func htmlUsesFourMeasuresPerSystemAt150PercentScale() {
        let html = StaffMelodyEngravingPage.html(musicXML: MusicXMLFixtures.nineMeasures)

        #expect(html.contains("scale: 60"))
        #expect(html.contains("breaks: \"encoded\""))
        #expect(html.contains("pageWidth: 1200"))
        #expect(!html.contains("scale: 40"))
    }

    @Test
    func htmlScalesNotationToFillSceneWidth() {
        let html = StaffMelodyEngravingPage.html(musicXML: "<score-partwise/>")

        // max-width alone never scales UP — small Verovio SVGs stay tiny and
        // four-bar systems look unchanged. Force full-width display on the SVG.
        let svgRuleStart = html.range(of: "#notation svg {")
        #expect(svgRuleStart != nil)
        guard let svgRuleStart else { return }
        let afterRule = html[svgRuleStart.lowerBound...]
        let nextRule = afterRule.range(of: "\n            /*") ?? afterRule.range(of: "#notation svg *")
        let rule = nextRule.map { String(afterRule[..<$0.lowerBound]) } ?? String(afterRule.prefix(200))
        #expect(rule.contains("width: 100%;"))
    }
}
