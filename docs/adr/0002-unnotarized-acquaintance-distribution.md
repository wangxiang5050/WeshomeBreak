# Unnotarized Acquaintance Distribution

Weshome Break is handed out as a locally built DMG (Release `.app` via XcodeGen + `xcodebuild`, wrapped with stock `hdiutil`) to the owner and occasional acquaintances—not the App Store, and not Apple notarization. Gatekeeper friction (right-click Open once) is an expected install step. Spec language that said “personal-only” is too narrow; the glossary term is **Unnotarized Acquaintance Distribution**.

## Considered Options

- **Notarized public / Developer ID pipeline** — smoother installs, but out of scope for this personal tool and heavier signing ops.
- **Keep “personal-only” wording** — understates occasional acquaintance sharing and invites “fix the docs” churn.
- **Ad-hoc unsigned DMGs by default** — easier to script, much worse Gatekeeper experience for acquaintances.

## Consequences

- Packaging docs and the DMG’s on-disk `README.txt` must describe the right-click Open path.
- A `scripts/package-dmg.sh` path may refuse unsigned builds unless `--allow-unsigned` is passed; notarization remains explicitly out of scope.
