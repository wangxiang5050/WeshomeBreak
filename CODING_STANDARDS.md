# Coding standards

`/code-review` Standards axis: apply **every** architecture rule below to the diff. Vocabulary is **module**, **interface**, **depth**, **seam**, **adapter** (same meanings as the codebase-design skill). Domain names live in `CONTEXT.md`.

A documented rule here overrides the Fowler smell baseline.

## The interface is the test surface

Callers and tests cross the same seam. Tests assert observable outcomes through the module's **interface**, not internals. A module that fails the deletion test (delete it and the same wiring just moves) is shallow — don't add tests that lock that shape in.

**Flag**

- Tests that reach past the interface, or a helper that exists only so the real module stays untested
- Call sites that bypass a deep module and reassemble its pieces beside it
- Splitting **Staff Melody Page**, **Rest Overlay**, **Staff Melody Scene** chrome, or **Break Cycle** observation back into coordinator / pass-through wiring

**This repo**

- **Staff Melody Page** (`GrillBreakCore`): tests hit that interface. Score Rendering (Verovio / `WKWebView`) stays an App adapter and is not a Core test.
- **Staff Melody Scene** chrome (`GrillBreakCore`): tests hit `StaffMelodySceneSession` (toggle, session reset, hover extra). They do not drive SwiftUI views or `EnvironmentKey`s.
- **Rest Overlay** (`WeshomeBreak`): tests hit `RestOverlay.sync(phase:)` through a recording `RestOverlayWindows` adapter. They do not open `NSWindow`s or drive SwiftUI views.
- **Break Cycle** (`WeshomeBreak`): tests hit phase (event rate), remaining (per second), and `statusLine` through `BreakCycle.tick()` with a fake clock. They do not start the production `Timer` or poke `NSMenu`.

`GrillBreakCore` is the default test seam for domain logic. An App-layer test target is justified only for a deep module whose seam cannot live in Core (true AppKit / SwiftUI dependency) and that already has two adapters — or, for in-process App observation like **Break Cycle**, a fake-clock `tick()` seam that callers and tests share.

## Two adapters make a seam real

A port / protocol is a **seam** only when at least two **adapters** are justified (typically production + test). One adapter is a hypothetical seam — inline it. Internal seams stay inside the module; don't put them on the external interface just because tests use them.

**Flag**

- A new protocol with a single implementer
- Injecting a dependency "for testability" without a second real adapter
- Promoting an internal seam onto the module's external interface

**This repo**

- `RestOverlayWindows` is a real seam: `BreakOverlayManager` (production) + recording adapter (tests)
- `BreakSceneSession` is a real seam: `StaffMelodySceneSession` (Staff Melody chrome) + inert `BreakSceneSession` (scenes with no extra chrome)
- Staff Melody Page needs no port in Core (in-process). Score Rendering is the App adapter, not a second Core adapter
- `BreakCycle.Remaining` is an internal two-rate surface of **Break Cycle**, not a second module and not a port

## Scene chrome stays behind the Scene Mode seam

A **Break Scene Mode** owns its session chrome. Rest Overlay presents the scene plus **cycle** chrome (countdown, skip/delay, hover timing). Overlay does not switch on scene identifiers or hold scene-specific state.

**Flag**

- Rest Overlay `@State` / `EnvironmentKey` for **Staff Melody Visibility**
- Control-bar policy keyed by scene identifier
- Overlay reconstructing Staff Melody toggle / visibility beside the scene view

**This repo**

- Overlay renders `BreakSceneSession.hoverBarExtraTitle` without interpreting it. Staff Melody Visibility lives on `StaffMelodySceneSession`. A new overlay presentation makes a new session, so the next break starts visible.

## Observe a Break Cycle at two rates through one module

A running **Break Cycle** is observed through one module. Phase and pause publish when they change; remaining publishes every second. Menu live-title, overlay countdown, and Rest Overlay present/dismiss are adapters of that interface. `BreakScheduler` stays the Core state machine.

**Flag**

- A peer `ObservableObject` for remaining that callers must learn as a second module
- Rest Overlay or the menu reassembling status from scheduler bits beside **Break Cycle**
- Publishing remaining through the same `objectWillChange` as phase (rebuilds an open menu)

**This repo**

- `BreakCycle` is the observation module. `MenuBarLiveStatusTitleUpdater` is the AppKit adapter for remaining ticks while the menu is open. Overlay countdown observes `BreakCycle.remaining`. Rest Overlay observes `$phase`.
