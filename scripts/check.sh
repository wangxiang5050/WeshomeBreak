#!/usr/bin/env bash
# Commit and CI gate: GrillBreakCore tests, then one Debug app build.
# Signing is off here so the build does not need a development team.
# Signed distribution stays in scripts/package-dmg.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

need swift
need xcodegen
need xcodebuild

echo "==> swift test (GrillBreakCore)"
(
  cd "$ROOT/GrillBreakCore"
  swift test
)

echo "==> xcodegen generate (WeshomeBreak)"
(
  cd "$ROOT/WeshomeBreak"
  xcodegen generate
)

echo "==> xcodebuild Debug (WeshomeBreak)"
xcodebuild \
  -project "$ROOT/WeshomeBreak/WeshomeBreak.xcodeproj" \
  -scheme WeshomeBreak \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> bundled piano is in the app"
settings="$(
  xcodebuild \
    -project "$ROOT/WeshomeBreak/WeshomeBreak.xcodeproj" \
    -scheme WeshomeBreak \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings
)"
app="$(
  printf '%s\n' "$settings" | awk '
    $0 ~ /target WeshomeBreak:/ { in_app = 1; next }
    $0 ~ /Build settings for action/ { in_app = 0 }
    in_app && $0 ~ /^    BUILT_PRODUCTS_DIR = / { dir = substr($0, index($0, "= ") + 2) }
    in_app && $0 ~ /^    FULL_PRODUCT_NAME = / { name = substr($0, index($0, "= ") + 2) }
    END { print dir "/" name }
  '
)"
bank="$app/Contents/Resources/UprightPianoKW.sf2"
if [[ ! -f "$bank" ]]; then
  echo "error: bundled piano missing: $bank" >&2
  exit 1
fi
