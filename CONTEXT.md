# Weshome Break

Menu-bar macOS app that enforces work/break cycles with a full-screen rest overlay and pluggable break scene visuals.

## Language

**Rest Overlay**:
The full-screen covering on every connected display during a break: Break Scene Mode, remaining-time countdown, and hover controls (cycle skip/delay plus any chrome the current scene contributes). Does not own scene-specific chrome such as Staff Melody Visibility.
_Avoid_: overlay manager, coordinator (those were shallow pass-through names)

**Break Cycle**:
The running work/rest alternation as observed by the menu and Rest Overlay: current phase, whether the cycle is paused, and remaining time in this phase.
_Avoid_: scheduler controller, countdown (as a separate observed object)

**Break Scene Mode**:
A pluggable visual presentation shown on the Rest Overlay during a break.
_Avoid_: effect, theme, screensaver (unless clearly metaphorical)

**Staff Melody Scene**:
The break scene mode that shows a readable, musically correct staff notation of a **User Melody** so the user can hum along while resting.
_Avoid_: staff-notes decoration, random phrase, ambient notes (those describe the superseded decorative behavior)

**Staff Melody Page**:
The outcome of turning the Melody Library's current Melody Selection into what the Staff Melody Scene can show: empty, failed, or ready HTML for Score Rendering (Verovio).
_Avoid_: StaffMelodyContent, resolver output, engraving prep (those were shallow pass-through names)

**User Melody**:
A melody the user provides for display on the Staff Melody Scene. Product-bundled melodies are not a required content source.
_Avoid_: song (implies lyrics/arrangement), track, random phrase

**Melody Entry**:
The process of getting a User Melody into the app. Phase 1 is offline conversion into a stored score file, then import; later phases may add in-app image capture.
_Avoid_: OCR-only wording when the phase is still manual/tool-assisted import

**Staff Melody (v1 scope)**:
A monophonic staff excerpt intended to fit roughly 4–8 measures (more than 8 is allowed with a warning). Includes clef (treble or bass, including mid-excerpt clef/key changes), time signature, key signature, pitches with accidentals, durations (including dotted values), common triplets, rests, barlines, beams, and ties. No polyphony, chords, lyrics, slurs, nested tuplets, or non-triplet tuplet ratios. Import accepts only a single part and a single voice; files outside this subset are rejected entirely.
_Avoid_: full score, arrangement, song sheet

**Beam (连梁)**:
The horizontal stroke that joins consecutive short notes (e.g. eighth notes) into a group. Not the same as a tie or slur.
_Avoid_: 连音线 (ambiguous colloquial term)

**Tie (延音线)**:
A curved mark joining two notes of the same pitch so their durations add.
_Avoid_: slur, beam

**Slur (圆滑线)**:
A curved mark grouping different pitches for phrasing; does not change duration. Out of v1 scope.
_Avoid_: tie, beam

**Tuplet (连音符)**:
A rhythm grouping that fits a non-standard count into a duration. v1 allows common triplets only (e.g. three eighths in the time of one beat); nested tuplets and other ratios are out of scope.
_Avoid_: 连音线 (ambiguous), beam

**Stored Score (MusicXML)**:
The Phase 1 on-disk form of a User Melody: MusicXML (`.musicxml` / `.mxl`), produced offline via Audiveris (image→MusicXML) and/or MuseScore (proof/edit/export), then imported into the app.
_Avoid_: ABC, custom JSON, LilyPond as the app’s source of truth (unless a future decision replaces MusicXML)

**Score Rendering (Verovio)**:
Phase 1 displays accepted MusicXML by engraving with Verovio (SVG), not a from-scratch staff Canvas renderer.
_Avoid_: treating Verovio as a reason to skip the import subset gate

**Melody Library**:
The set of imported User Melodies available to the Staff Melody Scene. Empty library shows an actionable empty state on the Rest Overlay (countdown still runs).
_Avoid_: playlist, catalog (unless UI copy)

**Melody Selection**:
Which User Melody from the Melody Library is shown on the next Staff Melody Scene. v1 is manual pick of one melody; later strategies (e.g. random) may extend this. Distinct from **Scene Mode Selection** (which Break Scene Mode to show).
_Avoid_: mode selection, scene selection (those refer to Break Scene Mode)

**Staff Melody Visibility**:
Whether the Staff Melody Scene's content (engraved score, empty state, or failure copy) is shown during the current break. Owned by the Staff Melody Scene for one Rest Overlay presentation. Hiding clears that content area only; the break, countdown, and Break Scene Mode selection are unchanged. Each new break starts visible again.
_Avoid_: hide melody (ambiguous with deleting from the Melody Library), scene mode off, mute, overlay visibility state

**Staff Notation Scale**:
The Verovio engraving `scale` (percent) applied when turning a Melody Selection into a Staff Melody Page. Configured in Settings under Melody Library. A change takes effect for the Staff Melody Scene starting the next break; the Melody Preview window picks it up immediately.
_Avoid_: zoom, notation size (implies a physical/point size, not the Verovio percent)

**Melody Preview**:
An independent Settings window that engraves the current Melody Selection at the current Staff Notation Scale, so the user can judge the setting without waiting for a break. Tracks Melody Selection and Staff Notation Scale changes live; empty/failed states reuse the same copy as the Staff Melody Scene.
_Avoid_: score preview (ambiguous with a future multi-melody browser), thumbnail

## Distribution

**Unnotarized Acquaintance Distribution**:
Handing the app directly to the owner and occasional acquaintances without Apple notarization; Gatekeeper friction (e.g. right-click Open once) is an expected install step, not a defect.
_Avoid_: personal-only (too narrow), App Store distribution, public notarized release
