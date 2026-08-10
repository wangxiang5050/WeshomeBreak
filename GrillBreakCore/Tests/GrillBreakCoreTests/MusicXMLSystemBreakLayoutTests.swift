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

    private func measureHasNewSystem(_ measure: XMLElement) -> Bool {
        let prints = (try? measure.nodes(forXPath: "./print") as? [XMLElement]) ?? []
        return prints.contains { $0.attribute(forName: "new-system")?.stringValue == "yes" }
    }
}
