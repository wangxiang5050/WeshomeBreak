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
        #expect(moment.sequence == PlaybackSequence(
            notes: [PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 0.5)],
            seconds: 0.5
        ))
        #expect(moment.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
    }

    @Test("the heard line leads a sequencer sample by at most one frame, minus output latency")
    func heardLineInterpolatesAndSubtractsLatency() {
        #expect(PlayheadTiming.heardSeconds(
            sampled: 1,
            sampledAt: 0,
            now: 0.25,
            latency: 0.125,
            maximumLead: 0.5
        ) == 1.125)
        #expect(PlayheadTiming.heardSeconds(
            sampled: 1,
            sampledAt: 0,
            now: 1,
            latency: 0.125,
            maximumLead: 0.5
        ) == 1.375)
        #expect(PlayheadTiming.heardSeconds(
            sampled: 0,
            sampledAt: 0,
            now: 0,
            latency: 0.125,
            maximumLead: 0.5
        ) == 0)
    }

    @Test("start schedules every note and a reported position only walks the line")
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
        let started = playback.start()
        #expect(started.sequence == PlaybackSequence(
            notes: [
                PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 1),
                PlaybackNote(midi: 64, velocity: 84, startSeconds: 1, soundingSeconds: 1)
            ],
            seconds: 2
        ))

        let moment = playback.place(seconds: 1)

        #expect(moment.phase == .playing)
        #expect(moment.sequence == nil)
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
        let paused = playback.place(seconds: 0.5)
        #expect(paused.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0.5))

        let held = playback.pause()
        #expect(held.phase == .paused)
        #expect(held.offersStart)
        #expect(held.silenced)
        #expect(held.sequence == nil)
        #expect(held.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0.5))

        let restarted = playback.start()
        #expect(restarted.phase == .playing)
        #expect(!restarted.offersStart)
        #expect(!restarted.silenced)
        #expect(restarted.sequence == PlaybackSequence(
            notes: [
                PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 1),
                PlaybackNote(midi: 64, velocity: 84, startSeconds: 1, soundingSeconds: 1)
            ],
            seconds: 2
        ))
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

        let moment = playback.place(seconds: 1)

        #expect(moment.phase == .playing)
        #expect(!moment.offersStart)
        #expect(moment.sequence == nil)
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

        let finished = playback.place(seconds: 1)

        #expect(finished.phase == .finished)
        #expect(finished.offersStart)
        #expect(!finished.silenced)
        #expect(finished.line == nil)

        let again = playback.start()
        #expect(again.silenced)
        #expect(again.sequence == PlaybackSequence(
            notes: [PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 1)],
            seconds: 1
        ))
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
        let started = playback.start()
        let second = playback.place(seconds: 1)
        let finished = playback.place(seconds: 2)

        #expect(started.sequence == PlaybackSequence(
            notes: [
                PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 1),
                PlaybackNote(midi: 60, velocity: 84, startSeconds: 1, soundingSeconds: 1)
            ],
            seconds: 2
        ))
        #expect(second.sequence == nil)
        #expect(second.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
        #expect(finished.phase == .finished)
        #expect(!finished.silenced)
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

        #expect(first.sequence == PlaybackSequence(
            notes: [
                PlaybackNote(midi: 60, velocity: 54, startSeconds: 0, soundingSeconds: 1),
                PlaybackNote(midi: 64, velocity: 68, startSeconds: 1, soundingSeconds: 1)
            ],
            seconds: 2
        ))
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
        #expect(staccato.start().sequence == PlaybackSequence(
            notes: [PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 0.5)],
            seconds: 1
        ))

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
        let still = fermata.place(seconds: 1)
        #expect(still.phase == .playing)
        #expect(still.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0.5))
        #expect(fermata.place(seconds: 2).phase == .finished)
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
        let second = playback.place(seconds: 1)

        #expect(first.sequence == PlaybackSequence(
            notes: [PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 2)],
            seconds: 2
        ))
        #expect(second.sequence == nil)
        #expect(second.phase == .playing)
        #expect(second.line == PlaybackLine(eventIndex: 1, fractionThroughEvent: 0))

        let held = playback.pause()
        #expect(held.line == PlaybackLine(eventIndex: 1, fractionThroughEvent: 0))
        let replayed = playback.start()
        #expect(replayed.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
        #expect(replayed.sequence == PlaybackSequence(
            notes: [PlaybackNote(midi: 60, velocity: 84, startSeconds: 0, soundingSeconds: 2)],
            seconds: 2
        ))
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

        #expect(playback.start().sequence?.notes.first?.midi == 72)
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

        let notes = playback.start().sequence?.notes ?? []
        #expect(notes.map(\.velocity) == [112, 84, 100, 54])
        #expect(notes.map(\.startSeconds) == [0, 1, 2, 3])
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
        _ = playback.place(seconds: 0.5)

        let dismissed = playback.dismiss()
        #expect(dismissed.phase == .idle)
        #expect(dismissed.silenced)
        #expect(dismissed.line == nil)
        #expect(playback.start().line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))

        _ = playback.place(seconds: 0.25)
        let replaced = playback.replace(musicXML: score([
            measure([note(step: "G", octave: 4, duration: 1, type: "quarter")])
        ]))
        #expect(replaced.phase == .idle)
        #expect(replaced.silenced)
        #expect(playback.start().sequence?.notes.first?.midi == 67)
    }

    @Test("a finished release is cut when the melody is replaced or the rest ends")
    func finishedReleaseIsCutOnReplaceOrDismiss() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([note(step: "C", octave: 4, duration: 1, type: "quarter")])
            ]),
            tempo: .lento
        )
        _ = playback.start()
        #expect(!playback.place(seconds: 1).silenced)

        let replaced = playback.replace(musicXML: score([
            measure([note(step: "G", octave: 4, duration: 1, type: "quarter")])
        ]))
        #expect(replaced.phase == .idle)
        #expect(replaced.silenced)
        #expect(replaced.line == nil)

        _ = playback.start()
        _ = playback.place(seconds: 1)
        let dismissed = playback.dismiss()
        #expect(dismissed.phase == .idle)
        #expect(dismissed.silenced)
        #expect(dismissed.line == nil)
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

        let notes = playback.start().sequence?.notes ?? []
        #expect(notes.map(\.midi) == [60, 62, 60])
        #expect(playback.place(seconds: 3).phase == .finished)
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
        #expect(playback.place(seconds: 1).phase == .finished)
    }

    @Test("arming waits without a line and a second pause cancels")
    func armWaitsAndPauseCancels() {
        let playback = MelodyPlayback(
            musicXML: score([
                measure([note(step: "C", octave: 4, duration: 1, type: "quarter")])
            ]),
            tempo: .lento
        )

        let armed = playback.arm()
        #expect(armed.phase == .preparing)
        #expect(!armed.offersStart)
        #expect(armed.line == nil)
        #expect(armed.sequence == nil)
        #expect(!armed.silenced)

        let cancelled = playback.pause()
        #expect(cancelled.phase == .idle)
        #expect(cancelled.offersStart)
        #expect(!cancelled.silenced)

        _ = playback.arm()
        let begun = playback.beginSounding()
        #expect(begun.phase == .playing)
        #expect(begun.line == PlaybackLine(eventIndex: 0, fractionThroughEvent: 0))
        #expect(begun.sequence?.notes.first?.midi == 60)
        #expect(!begun.silenced)
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
