import Foundation
import Testing
@testable import GrillBreakCore

@Suite("MusicXMLSystemBreakLayout")
struct MusicXMLSystemBreakLayoutTests {

    @Test
    func insertsNewSystemEveryFourMeasures() throws {
        let laidOut = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: 4,
            to: MusicXMLFixtures.nineMeasures
        )

        let document = try XMLDocument(xmlString: laidOut, options: [])
        let measures = try document.nodes(forXPath: "//part/measure") as! [XMLElement]
        #expect(measures.count == 9)

        for (index, measure) in measures.enumerated() {
            let hasBreak = measureHasNewSystem(measure)
            if index > 0 && index % 4 == 0 {
                #expect(hasBreak, "measure index \(index) should start a new system")
            } else {
                #expect(!hasBreak, "measure index \(index) should not start a new system")
            }
        }
    }

    @Test
    func leavesShortScoresWithoutSystemBreaks() throws {
        let laidOut = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: 4,
            to: MusicXMLFixtures.simpleFourMeasures
        )

        let document = try XMLDocument(xmlString: laidOut, options: [])
        let measures = try document.nodes(forXPath: "//part/measure") as! [XMLElement]
        #expect(measures.allSatisfy { !measureHasNewSystem($0) })
    }

    @Test
    func replacesExistingEncodedSystemBreaks() throws {
        let withOddBreaks = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list>
            <score-part id="P1"><part-name>Melody</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="2">
              <print new-system="yes"/>
              <note><rest/><duration>4</duration><type>whole</type></note>
            </measure>
            <measure number="3"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="4"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="5"><note><rest/><duration>4</duration><type>whole</type></note></measure>
          </part>
        </score-partwise>
        """

        let laidOut = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: 4,
            to: withOddBreaks
        )
        let document = try XMLDocument(xmlString: laidOut, options: [])
        let measures = try document.nodes(forXPath: "//part/measure") as! [XMLElement]

        #expect(!measureHasNewSystem(measures[1]))
        #expect(measureHasNewSystem(measures[4]))
    }

    @Test
    func stripsImportedPageLayoutThatFightsFixedSystemLength() throws {
        // Audiveris / MuseScore exports embed page-width and per-measure width
        // attributes. Verovio auto-breaks then packs 5+3 instead of 4+4.
        let withLayout = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <defaults>
            <page-layout>
              <page-height>387</page-height>
              <page-width>1201</page-width>
            </page-layout>
          </defaults>
          <part-list>
            <score-part id="P1"><part-name>Voice</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1" width="286"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="2" width="226"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="3" width="242"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="4" width="264"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="5" width="272">
              <print new-system="yes"><system-layout><system-distance>91</system-distance></system-layout></print>
              <note><rest/><duration>4</duration><type>whole</type></note>
            </measure>
            <measure number="6" width="231"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="7" width="269"><note><rest/><duration>4</duration><type>whole</type></note></measure>
            <measure number="8" width="246"><note><rest/><duration>4</duration><type>whole</type></note></measure>
          </part>
        </score-partwise>
        """

        let laidOut = try MusicXMLSystemBreakLayout.applying(
            measuresPerSystem: 4,
            to: withLayout
        )
        let document = try XMLDocument(xmlString: laidOut, options: [.nodeLoadExternalEntitiesNever])
        let measures = try document.nodes(forXPath: "//part/measure") as! [XMLElement]

        #expect(measures.count == 8)
        #expect(measures.allSatisfy { $0.attribute(forName: "width") == nil })
        let pageLayouts = document.rootElement()?
            .elements(forName: "defaults").first?
            .elements(forName: "page-layout") ?? []
        #expect(pageLayouts.isEmpty)
        #expect(measureHasNewSystem(measures[4]))
        #expect(measures.enumerated().filter { measureHasNewSystem($0.element) }.map(\.offset) == [4])
    }

    private func measureHasNewSystem(_ measure: XMLElement) -> Bool {
        let prints = (try? measure.nodes(forXPath: "./print") as? [XMLElement]) ?? []
        return prints.contains { $0.attribute(forName: "new-system")?.stringValue == "yes" }
    }
}
