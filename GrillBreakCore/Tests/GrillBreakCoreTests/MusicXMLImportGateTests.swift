import Foundation
import Testing
@testable import GrillBreakCore

@Suite("MusicXMLImportGate")
struct MusicXMLImportGateTests {

    private let gate = MusicXMLImportGate()

    @Test("accepts a monophonic melody within the v1 subset")
    func acceptsMonophonicSubset() throws {
        let xml = MusicXMLFixtures.simpleFourMeasures
        let result = gate.evaluate(xml)
        guard case .accepted(let draft) = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
        #expect(draft.measureCount == 4)
        #expect(draft.warnings.isEmpty)
        #expect(draft.musicXML == xml)
    }

    @Test("allows fewer than 4 measures without warning")
    func allowsFewerThanFourMeasures() {
        let result = gate.evaluate(MusicXMLFixtures.twoMeasures)
        guard case .accepted(let draft) = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
        #expect(draft.measureCount == 2)
        #expect(draft.warnings.isEmpty)
    }

    @Test("warns but still accepts when there are more than 8 measures")
    func warnsWhenMoreThanEightMeasures() {
        let result = gate.evaluate(MusicXMLFixtures.nineMeasures)
        guard case .accepted(let draft) = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
        #expect(draft.measureCount == 9)
        #expect(draft.warnings.contains { $0.contains("8") })
    }

    @Test("rejects multiple parts with a clear reason")
    func rejectsMultipleParts() {
        let result = gate.evaluate(MusicXMLFixtures.twoParts)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("part"))
    }

    @Test("rejects chords")
    func rejectsChords() {
        let result = gate.evaluate(MusicXMLFixtures.withChord)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("chord") || reason.contains("和弦"))
    }

    @Test("rejects lyrics")
    func rejectsLyrics() {
        let result = gate.evaluate(MusicXMLFixtures.withLyric)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("lyric") || reason.contains("歌词"))
    }

    @Test("rejects slurs")
    func rejectsSlurs() {
        let result = gate.evaluate(MusicXMLFixtures.withSlur)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("slur") || reason.contains("圆滑"))
    }

    @Test("rejects multiple voices")
    func rejectsMultipleVoices() {
        let result = gate.evaluate(MusicXMLFixtures.twoVoices)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("voice") || reason.contains("声部"))
    }

    @Test("accepts a common triplet")
    func acceptsCommonTriplet() {
        let result = gate.evaluate(MusicXMLFixtures.withTriplet)
        guard case .accepted = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
    }

    @Test("rejects a non-triplet tuplet")
    func rejectsNonTripletTuplet() {
        let result = gate.evaluate(MusicXMLFixtures.withQuintuplet)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("tuplet") || reason.contains("连音"))
    }

    @Test("rejects nested tuplets")
    func rejectsNestedTuplets() {
        let result = gate.evaluate(MusicXMLFixtures.withNestedTuplet)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("tuplet") || reason.contains("连音") || reason.contains("嵌套"))
    }

    @Test("rejects invalid XML with a clear reason")
    func rejectsInvalidXML() {
        let result = gate.evaluate("<not-musicxml>")
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("rejects ornaments as outside the v1 subset")
    func rejectsOrnaments() {
        let result = gate.evaluate(MusicXMLFixtures.withOrnament)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("ornament") || reason.contains("装饰"))
    }

    @Test("rejects harmony as outside the v1 subset")
    func rejectsHarmony() {
        let result = gate.evaluate(MusicXMLFixtures.withHarmony)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejected, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("harmony") || reason.contains("和声"))
    }

    @Test("accepts beams, ties, rests, and dotted values")
    func acceptsBeamsTiesRestsAndDots() {
        let result = gate.evaluate(MusicXMLFixtures.withBeamTieRestDot)
        guard case .accepted = result else {
            Issue.record("expected accepted, got \(result)")
            return
        }
    }
}

/// Inline MusicXML snippets for gate tests — kept small and explicit so
/// failures point at musical structure, not fixture plumbing.
enum MusicXMLFixtures {
    static let simpleFourMeasures = scoreXML(measureBodies: [
        measureWithNotes([note(pitch: "C", octave: 4, duration: 4, type: "whole")]),
        measureWithNotes([note(pitch: "D", octave: 4, duration: 4, type: "whole")]),
        measureWithNotes([note(pitch: "E", octave: 4, duration: 4, type: "whole")]),
        measureWithNotes([note(pitch: "F", octave: 4, duration: 4, type: "whole")])
    ])

    static let twoMeasures = scoreXML(measureBodies: [
        measureWithNotes([note(pitch: "C", octave: 4, duration: 4, type: "whole")]),
        measureWithNotes([note(pitch: "D", octave: 4, duration: 4, type: "whole")])
    ])

    static let nineMeasures = scoreXML(measureBodies: (1...9).map { i in
        measureWithNotes([note(pitch: "C", octave: 4, duration: 4, type: "whole")], number: i)
    })

    static let twoParts = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Melody</part-name></score-part>
        <score-part id="P2"><part-name>Bass</part-name></score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <key><fifths>0</fifths></key>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <clef><sign>G</sign><line>2</line></clef>
          </attributes>
          \(note(pitch: "C", octave: 4, duration: 4, type: "whole"))
        </measure>
      </part>
      <part id="P2">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <clef><sign>F</sign><line>4</line></clef>
          </attributes>
          \(note(pitch: "C", octave: 3, duration: 4, type: "whole"))
        </measure>
      </part>
    </score-partwise>
    """

    static let withChord = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>1</voice>
          <type>whole</type>
        </note>
        <note>
          <chord/>
          <pitch><step>E</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>1</voice>
          <type>whole</type>
        </note>
        """
    ])

    static let withLyric = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>1</voice>
          <type>whole</type>
          <lyric number="1"><text>la</text></lyric>
        </note>
        """
    ])

    static let withSlur = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>2</duration>
          <voice>1</voice>
          <type>half</type>
          <notations><slur type="start" number="1"/></notations>
        </note>
        <note>
          <pitch><step>D</step><octave>4</octave></pitch>
          <duration>2</duration>
          <voice>1</voice>
          <type>half</type>
          <notations><slur type="stop" number="1"/></notations>
        </note>
        """
    ])

    static let twoVoices = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>1</voice>
          <type>whole</type>
        </note>
        <backup><duration>4</duration></backup>
        <note>
          <pitch><step>E</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>2</voice>
          <type>whole</type>
        </note>
        """
    ])

    static let withTriplet = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
          <time-modification>
            <actual-notes>3</actual-notes>
            <normal-notes>2</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="start" number="1"/>
          </notations>
        </note>
        <note>
          <pitch><step>D</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
          <time-modification>
            <actual-notes>3</actual-notes>
            <normal-notes>2</normal-notes>
          </time-modification>
        </note>
        <note>
          <pitch><step>E</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
          <time-modification>
            <actual-notes>3</actual-notes>
            <normal-notes>2</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="stop" number="1"/>
          </notations>
        </note>
        <note>
          <pitch><step>F</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>quarter</type>
        </note>
        """
    ], divisions: 2)

    static let withQuintuplet = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>16th</type>
          <time-modification>
            <actual-notes>5</actual-notes>
            <normal-notes>4</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="start" number="1"/>
          </notations>
        </note>
        <note>
          <pitch><step>D</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>16th</type>
          <time-modification>
            <actual-notes>5</actual-notes>
            <normal-notes>4</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="stop" number="1"/>
          </notations>
        </note>
        """
    ], divisions: 4)

    static let withOrnament = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>1</voice>
          <type>whole</type>
          <notations><ornaments><trill-mark/></ornaments></notations>
        </note>
        """
    ])

    static let withHarmony = scoreXML(measureBodies: [
        """
        <harmony>
          <root><root-step>C</root-step></root>
          <kind>major</kind>
        </harmony>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>4</duration>
          <voice>1</voice>
          <type>whole</type>
        </note>
        """
    ])

    static let withBeamTieRestDot = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
          <beam number="1">begin</beam>
        </note>
        <note>
          <pitch><step>D</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
          <beam number="1">end</beam>
          <notations><tied type="start"/></notations>
        </note>
        <note>
          <pitch><step>D</step><octave>4</octave></pitch>
          <duration>1</duration>
          <tie type="stop"/>
          <voice>1</voice>
          <type>eighth</type>
          <notations><tied type="stop"/></notations>
        </note>
        <note>
          <rest/>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
        </note>
        <note>
          <pitch><step>E</step><octave>4</octave></pitch>
          <duration>3</duration>
          <voice>1</voice>
          <type>quarter</type>
          <dot/>
        </note>
        """
    ], divisions: 2)

    /// A triplet that starts another tuplet before the outer one stops.
    static let withNestedTuplet = scoreXML(measureBodies: [
        """
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>eighth</type>
          <time-modification>
            <actual-notes>3</actual-notes>
            <normal-notes>2</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="start" number="1"/>
          </notations>
        </note>
        <note>
          <pitch><step>D</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>16th</type>
          <time-modification>
            <actual-notes>3</actual-notes>
            <normal-notes>2</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="start" number="2"/>
          </notations>
        </note>
        <note>
          <pitch><step>E</step><octave>4</octave></pitch>
          <duration>1</duration>
          <voice>1</voice>
          <type>16th</type>
          <time-modification>
            <actual-notes>3</actual-notes>
            <normal-notes>2</normal-notes>
          </time-modification>
          <notations>
            <tuplet type="stop" number="2"/>
            <tuplet type="stop" number="1"/>
          </notations>
        </note>
        """
    ], divisions: 2)

    // MARK: - Builders

    private static func scoreXML(measureBodies: [String], divisions: Int = 1) -> String {
        let measures = measureBodies.enumerated().map { index, body in
            """
            <measure number="\(index + 1)">
              \(index == 0 ? attributes(divisions: divisions) : "")
              \(body)
            </measure>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="3.1">
          <part-list>
            <score-part id="P1"><part-name>Melody</part-name></score-part>
          </part-list>
          <part id="P1">
            \(measures)
          </part>
        </score-partwise>
        """
    }

    private static func attributes(divisions: Int) -> String {
        """
        <attributes>
          <divisions>\(divisions)</divisions>
          <key><fifths>0</fifths></key>
          <time><beats>4</beats><beat-type>4</beat-type></time>
          <clef><sign>G</sign><line>2</line></clef>
        </attributes>
        """
    }

    private static func measureWithNotes(_ notes: [String], number: Int = 1) -> String {
        notes.joined(separator: "\n")
    }

    private static func note(pitch: String, octave: Int, duration: Int, type: String) -> String {
        """
        <note>
          <pitch><step>\(pitch)</step><octave>\(octave)</octave></pitch>
          <duration>\(duration)</duration>
          <voice>1</voice>
          <type>\(type)</type>
        </note>
        """
    }
}
