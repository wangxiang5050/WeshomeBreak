import Foundation
import Testing
@testable import GrillBreakCore

@Suite("Melody Playback")
struct MelodyPlaybackTests {
    @Test("start sounds the first note at the chosen tempo and offers pause")
    func startSoundsTheFirstNote() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    note(step: "C", octave: 4, duration: 1, type: "quarter")
                ])
            ]),
            tempo: .allegro
        )

        let moment = playback.start()

        #expect(moment.phase == .playing)
        #expect(!moment.offersStart)
        #expect(!moment.silenced)
        #expect(moment.attacks == [
            PlaybackAttack(midi: 60, velocity: 84, soundingSeconds: 0.5)
        ])
        #expect(moment.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
    }

    @Test("advance sounds the next note and walks the line")
    func advanceSoundsTheNextNote() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    note(step: "E", octave: 4, duration: 1, type: "quarter")
                ])
            ]),
            tempo: .lento
        )
        _ = playback.start()

        let moment = playback.advance(seconds: 1)

        #expect(moment.phase == .playing)
        #expect(moment.attacks == [
            PlaybackAttack(midi: 64, velocity: 84, soundingSeconds: 1)
        ])
        #expect(moment.line == PlaybackLine(eventIndex: 1, fractionThroughEvent: 0))
    }

    @Test("pause holds the line and the next start replays that note")
    func pauseThenStartReplaysTheCurrentNote() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    note(step: "E", octave: 4, duration: 1, type: "quarter")
                ])
            ]),
            tempo: .lento
        )
        _ = playback.start()
        let paused = playback.advance(seconds: 0.5)
        #expect(paused.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0.5))

        let held = playback.pause()
        #expect(held.phase == .paused)
        #expect(held.offersStart)
        #expect(held.silenced)
        #expect(held.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0.5))

        let restarted = playback.start()
        #expect(restarted.phase == .playing)
        #expect(!restarted.offersStart)
        #expect(restarted.attacks == [
            PlaybackAttack(midi: 60, velocity: 84, soundingSeconds: 1)
        ])
        #expect(restarted.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
    }

    @Test("a rest keeps playback going and stays silent")
    func restKeepsPlaybackGoing() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    "<note><rest/><duration>1</duration><type>quarter</type></note>"
                ])
            ]),
            tempo: .lento
        )
        _ = playback.start()

        let moment = playback.advance(seconds: 1)

        #expect(moment.phase == .playing)
        #expect(!moment.offersStart)
        #expect(moment.attacks.isEmpty)
        #expect(moment.line == PlaybackLine(eventIndex: 1, fractionThroughEvent: 0))
    }

    @Test("the melody finishes without looping and start begins again")
    func finishThenStartFromTheBeginning() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([note(step: "C", octave: 4, duration: 1, type: "quarter")])
            ]),
            tempo: .lento
        )
        _ = playback.start()

        let finished = playback.advance(seconds: 1)

        #expect(finished.phase == .finished)
        #expect(finished.offersStart)
        #expect(finished.silenced)
        #expect(finished.line == nil)

        let again = playback.start()
        #expect(again.attacks == [
            PlaybackAttack(midi: 60, velocity: 84, soundingSeconds: 1)
        ])
        #expect(again.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
    }

    @Test("a repeat bar plays the section twice")
    func repeatBarPlaysTwice() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    #"<barline location="right"><repeat direction="backward"/></barline>"#
                ])
            ]),
            tempo: .lento
        )
        _ = playback.start()
        let second = playback.advance(seconds: 1)
        let finished = playback.advance(seconds: 1)

        #expect(second.attacks == [
            PlaybackAttack(midi: 60, velocity: 84, soundingSeconds: 1)
        ])
        #expect(second.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
        #expect(finished.phase == .finished)
    }

    @Test("a dynamic mark holds until the next one, and a hairpin steps one level")
    func dynamicsAndHairpin() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    #"<direction><direction-type><dynamics><p/></dynamics></direction-type></direction>"#,
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    #"<direction><direction-type><wedge type="crescendo"/></direction-type></direction>"#,
                    #"<direction><direction-type><wedge type="stop"/></direction-type></direction>"#,
                    note(step: "E", octave: 4, duration: 1, type: "quarter")
                ])
            ]),
            tempo: .lento
        )

        let first = playback.start()
        let second = playback.advance(seconds: 1)

        #expect(first.attacks == [
            PlaybackAttack(midi: 60, velocity: 54, soundingSeconds: 1)
        ])
        #expect(second.attacks == [
            PlaybackAttack(midi: 64, velocity: 68, soundingSeconds: 1)
        ])
    }

    @Test("staccato shortens the sound and a fermata stretches the note")
    func staccatoAndFermata() {
        let staccato = MelodyPlayback(
            musicXML: score([
                measure([
                    """
                    <note>
                      <pitch><step>C</step><octave>4</octave></pitch>
                      <duration>1</duration>
                      <type>quarter</type>
                      <notations><articulations><staccato/></articulations></notations>
                    </note>
                    """
                ])
            ]),
            tempo: .lento
        )
        #expect(staccato.start().attacks == [
            PlaybackAttack(midi: 60, velocity: 84, soundingSeconds: 0.5)
        ])

        let fermata = MelodyPlayback(
            musicXML: score([
                measure([
                    """
                    <note>
                      <pitch><step>C</step><octave>4</octave></pitch>
                      <duration>1</duration>
                      <type>quarter</type>
                      <notations><fermata>normal</fermata></notations>
                    </note>
                    """
                ])
            ]),
            tempo: .lento
        )
        _ = fermata.start()
        let still = fermata.advance(seconds: 1)
        #expect(still.phase == .playing)
        #expect(still.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0.5))
        #expect(fermata.advance(seconds: 1).phase == .finished)
    }

    @Test("a tie sounds once and the line walks into the second note")
    func tieSoundsOnce() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    """
                    <note>
                      <pitch><step>C</step><octave>4</octave></pitch>
                      <duration>1</duration>
                      <type>quarter</type>
                      <tie type="start"/>
                    </note>
                    <note>
                      <pitch><step>C</step><octave>4</octave></pitch>
                      <duration>1</duration>
                      <type>quarter</type>
                      <tie type="stop"/>
                    </note>
                    """
                ])
            ]),
            tempo: .lento
        )

        let first = playback.start()
        let second = playback.advance(seconds: 1)

        #expect(first.attacks == [
            PlaybackAttack(midi: 60, velocity: 84, soundingSeconds: 2)
        ])
        #expect(second.attacks.isEmpty)
        #expect(second.phase == .playing)
        #expect(second.line == PlaybackLine(eventIndex: 1, fractionThroughEvent: 0))
    }

    @Test("an octave mark changes the sounding pitch")
    func octaveMarkRaisesThePitch() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    #"<direction><direction-type><octave-shift type="up" size="8"/></direction-type></direction>"#,
                    note(step: "C", octave: 4, duration: 1, type: "quarter")
                ])
            ]),
            tempo: .lento
        )

        #expect(playback.start().attacks.first?.midi == 72)
    }

    @Test("sfz and fp affect only the attack they mark")
    func suddenDynamics() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    #"<direction><direction-type><dynamics><sfz/></dynamics></direction-type></direction>"#,
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    note(step: "D", octave: 4, duration: 1, type: "quarter"),
                    #"<direction><direction-type><dynamics><fp/></dynamics></direction-type></direction>"#,
                    note(step: "E", octave: 4, duration: 1, type: "quarter"),
                    note(step: "F", octave: 4, duration: 1, type: "quarter")
                ])
            ]),
            tempo: .lento
        )

        #expect(playback.start().attacks.first?.velocity == 112)
        #expect(playback.advance(seconds: 1).attacks.first?.velocity == 84)
        #expect(playback.advance(seconds: 1).attacks.first?.velocity == 100)
        #expect(playback.advance(seconds: 1).attacks.first?.velocity == 54)
    }

    @Test("leaving headphones for speakers pauses; moving onto headphones does not")
    func headphoneRoutePausesOnlyWhenLeaving() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([note(step: "C", octave: 4, duration: 4, type: "whole")])
            ]),
            tempo: .lento
        )
        _ = playback.noteOutput(.headphones)
        _ = playback.start()

        let ontoSpeakers = playback.noteOutput(.speakers)
        #expect(ontoSpeakers.phase == .paused)
        #expect(ontoSpeakers.silenced)
        #expect(ontoSpeakers.offersStart)

        let resumed = playback.start()
        #expect(resumed.phase == .playing)
        let ontoHeadphones = playback.noteOutput(.headphones)
        #expect(ontoHeadphones.phase == .playing)
        #expect(!ontoHeadphones.silenced)
    }

    @Test("dismiss and a replaced melody drop the position")
    func dismissAndReplaceDropThePosition() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([note(step: "C", octave: 4, duration: 1, type: "quarter")])
            ]),
            tempo: .lento
        )
        _ = playback.start()
        _ = playback.advance(seconds: 0.5)

        let dismissed = playback.dismiss()
        #expect(dismissed.phase == .idle)
        #expect(dismissed.silenced)
        #expect(dismissed.line == nil)
        #expect(playback.start().line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))

        _ = playback.advance(seconds: 0.25)
        let replaced = playback.replace(musicXML: score([
            measure([note(step: "G", octave: 4, duration: 1, type: "quarter")])
        ]))
        #expect(replaced.phase == .idle)
        #expect(replaced.silenced)
        #expect(playback.start().attacks.first?.midi == 67)
    }

    @Test("D.C. al Fine jumps once and stops at Fine")
    func daCapoAlFine() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    #"<direction><direction-type><words>Fine</words></direction-type></direction>"#,
                    note(step: "C", octave: 4, duration: 1, type: "quarter")
                ]),
                measure([
                    note(step: "D", octave: 4, duration: 1, type: "quarter"),
                    #"<direction><direction-type><words>D.C. al Fine</words></direction-type></direction>"#
                ])
            ]),
            tempo: .lento
        )

        #expect(playback.start().attacks.first?.midi == 60)
        #expect(playback.advance(seconds: 1).attacks.first?.midi == 62)
        #expect(playback.advance(seconds: 1).attacks.first?.midi == 60)
        #expect(playback.advance(seconds: 1).phase == .finished)
    }

    @Test("a dal segno with no segno is ignored")
    func missingSegnoIsIgnored() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([
                    note(step: "C", octave: 4, duration: 1, type: "quarter"),
                    #"<direction><direction-type><words>D.S. al Fine</words></direction-type></direction>"#
                ])
            ]),
            tempo: .lento
        )
        _ = playback.start()
        #expect(playback.advance(seconds: 1).phase == .finished)
    }
}

private func score(_ measures: [String]) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="3.1">
      <part-list>
        <score-part id="P1"><part-name>Melody</part-name></score-part>
      </part-list>
      <part id="P1">
        \(measures.enumerated().map { index, body in
            """
            <measure number="\(index + 1)">
              \(index == 0 ? """
              <attributes>
                <divisions>1</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
              </attributes>
              """ : "")
              \(body)
            </measure>
            """
        }.joined(separator: "\n"))
      </part>
    </score-partwise>
    """
}

private func measure(_ bodies: [String]) -> String {
    bodies.joined(separator: "\n")
}

private func note(step: String, octave: Int, duration: Int, type: String) -> String {
    """
    <note>
      <pitch><step>\(step)</step><octave>\(octave)</octave></pitch>
      <duration>\(duration)</duration>
      <type>\(type)</type>
    </note>
    """
}
