# Staff Melody Visibility on rest overlay

## Goal

During a Staff Melody Scene break, let the user temporarily hide or show the scene content (engraved score, empty state, or failure copy) via a hover control-bar button.

## Acceptance

- [ ] Control bar button labels: 「隐藏旋律」 when content is visible, 「显示旋律」 when hidden
- [ ] Button appears only for Staff Melody Scene (`staff-melody`), on the same hover control bar as skip/delay (mouse move reveals, ~2.5s auto-hide)
- [ ] Button still available when skip and delay are both disabled (control bar may contain only this button)
- [ ] No new settings toggle
- [ ] Hiding clears content area only; background, countdown, break phase, Break Scene Mode, and Melody Library/Selection unchanged
- [ ] Empty and failure states are also hideable
- [ ] Visibility is session-scoped to the current break presentation; next break starts visible
- [ ] No placeholder “已隐藏” copy when content is hidden

## Domain

See `CONTEXT.md` → **Staff Melody Visibility**.
