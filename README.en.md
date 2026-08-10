# Weshome Break

A macOS menu-bar app that enforces configurable work/break cycles with a full-screen rest overlay and a hummable staff notation scene (Staff Melody Scene).

[中文](README.md)

## Features

- Menu-bar only (no Dock icon, no standalone main window)
- Simple work/break cycle scheduling with configurable durations (defaults: 20 / 5 minutes)
- Full-screen break overlay on every connected display when a break is due
- **Staff Melody Scene**: import MusicXML and engrave a readable monophonic staff with Verovio for humming while resting (visual only, no audio)
- Skip or snooze the current break from the overlay; pause/resume, trigger a break, and open Settings from the menu bar
- Optional launch at login; settings persist (timer state is not restored across process restarts)

## Requirements

- macOS **14.0+** (per `WeshomeBreak/project.yml` and `GrillBreakCore/Package.swift`)
- [Xcode](https://developer.apple.com/xcode/) (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (generates `xcodeproj` from `project.yml`; project files are not committed)

Optional (melody entry only — not build dependencies):

- [Audiveris](https://github.com/Audiveris/audiveris) (image → MusicXML) and/or [MuseScore](https://musescore.org/) (proof / manual entry / export)

## Build & run

```bash
# Generate the Xcode project and run the app
cd WeshomeBreak
xcodegen generate
open WeshomeBreak.xcodeproj
# In Xcode, select the Weshome Break target → Run
```

Signing: App Sandbox is off; sign with your personal Apple ID via Xcode automatic signing. Intended for personal direct distribution (not App Store / no notarization). Confirm the Signing Team in Xcode before the first Run.

```bash
# Run GrillBreakCore unit tests
cd GrillBreakCore
swift test
```

## Usage

1. After launch, use the menu-bar icon for Settings, Start break now, Pause/Resume, and Quit.
2. When work time ends, a full-screen overlay covers all displays; Staff Melody is centered, with the break countdown in a corner.
3. Move the mouse over the overlay to reveal controls: skip or snooze the current break.
4. In Settings, import MusicXML (`.musicxml` / `.mxl`) into the Melody Library and manually select the active melody.

External melody-entry steps: [`docs/melody-entry.md`](docs/melody-entry.md).

## Documentation

| Doc | Description |
|-----|-------------|
| [`spec.md`](spec.md) | Product spec and implementation decisions |
| [`CONTEXT.md`](CONTEXT.md) | Domain glossary (Staff Melody, MusicXML, etc.) |
| [`docs/melody-entry.md`](docs/melody-entry.md) | Offline melody entry path |
| [`docs/adr/0001-musicxml-verovio-for-staff-melody.md`](docs/adr/0001-musicxml-verovio-for-staff-melody.md) | MusicXML + Verovio decision |

## License

[Apache License 2.0](LICENSE)

## Note

This repository also demonstrates agent workflow skills such as [grill-me](.agents/skills/grill-me/) (see [`.agents/skills/`](.agents/skills/)): grilling → `spec.md` → tickets → implementation. Product code and docs follow the sections above; the skills are not required to run the app.
