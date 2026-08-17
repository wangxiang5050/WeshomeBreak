# Coding standards

`/code-review` Standards axis: apply **every** architecture rule below to the diff. Vocabulary is **module**, **interface**, **depth**, **seam**, **adapter** (same meanings as the codebase-design skill). Domain names live in `CONTEXT.md`.

A documented rule here overrides the Fowler smell baseline.

## The interface is the test surface

Callers and tests cross the same seam. Tests assert observable outcomes through the module's **interface**, not internals. A module that fails the deletion test (delete it and the same wiring just moves) is shallow — don't add tests that lock that shape in.

**Flag**

- Tests that reach past the interface, or a helper that exists only so the real module stays untested
- Call sites that bypass a deep module and reassemble its pieces beside it
- Splitting **Staff Melody Page** or **Rest Overlay** back into coordinator / pass-through wiring

**This repo**

- **Staff Melody Page** (`GrillBreakCore`): tests hit that interface. Score Rendering (Verovio / `WKWebView`) stays an App adapter and is not a Core test.
- **Rest Overlay** (`WeshomeBreak`): tests hit `RestOverlay.sync(phase:)` through a recording `RestOverlayWindows` adapter. They do not open `NSWindow`s or drive SwiftUI views.

`GrillBreakCore` is the default test seam for domain logic. An App-layer test target is justified only for a deep module whose seam cannot live in Core (true AppKit / SwiftUI dependency) and that already has two adapters.

## Two adapters make a seam real

A port / protocol is a **seam** only when at least two **adapters** are justified (typically production + test). One adapter is a hypothetical seam — inline it. Internal seams stay inside the module; don't put them on the external interface just because tests use them.

**Flag**

- A new protocol with a single implementer
- Injecting a dependency "for testability" without a second real adapter
- Promoting an internal seam onto the module's external interface

**This repo**

- `RestOverlayWindows` is a real seam: `BreakOverlayManager` (production) + recording adapter (tests)
- Staff Melody Page needs no port in Core (in-process). Score Rendering is the App adapter, not a second Core adapter
