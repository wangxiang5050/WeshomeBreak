# Melody Playback follows the notation, except tempo

Staff Melody Scene was visual only, so the user could hum. Melody Playback now sounds that same User Melody on a piano during the rest. Repeats, dynamics, hairpins, articulations that change the attack or the hold, and octave marks are performed in their usual sense. Playback Tempo is not. It is one Settings choice for the whole library (慢板 60, 行板 72, 中板 96, 快板 120, 急板 144; default 行板 72). Score metronome marks, tempo words, ritardando, and accelerando do not change it.

Leaving headphone output pauses. Playback may still run on speakers. If the current output is headphones and that headphone disconnects, or the output is switched to speakers, that is one pause: the position is kept. Starting again plays through whatever the output is then, including speakers. No headphones is allowed from the start. Another headphone, or moving from speakers onto headphones, does not pause.

## Considered Options

- **Pitch and duration only, tempo taken from the score** — less interpreter, but the engraved repeats and dynamics would be silent lies, and a mark buried in the file would override the tempo the user just chose.
- **Headphones required, and unplugging rewinds to the start** — avoids sound from the speakers, but blocks playing aloud on purpose and throws away the place the user paused.

## Consequences

- One playback for the rest, started and paused from a single icon on each screen's hover bar. It does not start by itself, and closing the Rest Overlay discards the position.
- The sequencer is the sounding clock. Decided notes are scheduled once; pause, resume, and stop rebuild or drop that sequence instead of seeking it. The line follows the sequencer position. The bundled piano file is `WeshomeBreak/Resources/UprightPianoKW.sf2` (FreePats Upright Piano KW), loaded as program 0 on bank MSB 0 / LSB 0. When that file does not load, the system DLS piano is the fallback, loaded on the melodic bank (`kAUSampler_DefaultMelodicBankMSB` / `kAUSampler_DefaultBankLSB`). Those two bank pairs stay distinct.
- Pause stops the sound immediately. Starting again replays the current note from its attack. A vertical line tracks the moment on the current system and jumps back to that attack.
- The break-reminder path stays visual. Melody Playback is not an alarm sound, a system notification, or a metronome.
