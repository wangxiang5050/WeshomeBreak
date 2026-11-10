# Melody Library lives in iCloud Drive

The owner's Melody Library is shared across their Macs by storing it as files in the iCloud Drive folder `Weshome Break`, not in an app iCloud container. The app is distributed without notarization and without an iCloud entitlement, so a ubiquity container would not sync. Each Mac writes only its own device log; the app merges those logs locally. One shared `manifest.json` would let iCloud's last-writer-wins copies drop the other Mac's imports.

## Considered Options

- **iCloud ubiquity container** — the usual Apple API, but it needs an entitlement and a provisioning profile, which fights unnotarized acquaintance distribution.
- **One shared manifest both Macs overwrite** — simpler files, but an offline import on one Mac disappears when the other Mac saves the file.

## Consequences

- Manual Melody Selection stays in Application Support, not in the iCloud folder.
- When iCloud Drive is absent, the Mac uses a private library and folds it in the next time the drive is there. A delete recorded in any device log stays deleted across that fold.
- Score files are kept even when they are not downloaded yet; a missing file is not a deletion.
