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

        // Reliable white ink: recolor engraved SVG attributes after render.
        #expect(html.contains("#ffffff"))
        #expect(html.contains("applyWhiteInk"))
        #expect(html.contains("setAttribute(\"fill\", \"#ffffff\")"))
        #expect(!html.contains("filter: brightness(0) invert(1)"))
    }

    @Test
    func htmlEmbedsMusicXMLPayload() {
        let xml = "<score-partwise version=\"4.0\"/>"
        let html = StaffMelodyEngravingPage.html(musicXML: xml)
        let payload = Data(xml.utf8).base64EncodedString()

        #expect(html.contains(payload))
    }
}
