#!/usr/bin/env bash
# Build a Release .app and wrap it in a UDZO DMG for Unnotarized Acquaintance Distribution.
# Usage: scripts/package-dmg.sh [--universal] [--allow-unsigned]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/WeshomeBreak"
DIST_DIR="$ROOT/dist"
DERIVED="$DIST_DIR/DerivedData"
STAGE="$DIST_DIR/dmg-stage"
SCHEME="WeshomeBreak"
CONFIG="Release"
PRODUCT_APP_NAME="Weshome Break.app"
VOL_NAME="Weshome Break"

UNIVERSAL=0
ALLOW_UNSIGNED=0

usage() {
  cat <<'EOF'
Usage: scripts/package-dmg.sh [--universal] [--allow-unsigned]

  --universal       Build arm64 + x86_64 (default: host architecture only)
  --allow-unsigned  Allow ad-hoc / unsigned .app (default: require Apple Development or Developer ID)

Environment:
  DEVELOPMENT_TEAM  Optional team ID passed to xcodebuild (needed for non-ad-hoc CLI signing)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal) UNIVERSAL=1 ;;
    --allow-unsigned) ALLOW_UNSIGNED=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command not found: $1" >&2
    exit 1
  }
}

need xcodegen
need xcodebuild
need hdiutil
need codesign
need plutil

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64|x86_64) ;;
  *)
    echo "error: unsupported host architecture: $HOST_ARCH" >&2
    exit 1
    ;;
esac

if [[ "$UNIVERSAL" -eq 1 ]]; then
  ARCH_LABEL="universal"
  ARCHS_VALUE="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
else
  ARCH_LABEL="$HOST_ARCH"
  ARCHS_VALUE="$HOST_ARCH"
  ONLY_ACTIVE_ARCH=YES
fi

mkdir -p "$DIST_DIR"
rm -rf "$DERIVED" "$STAGE"

echo "==> Generating Xcode project"
(
  cd "$APP_DIR"
  xcodegen generate
)

BUILD_SETTINGS=(
  ARCHS="$ARCHS_VALUE"
  ONLY_ACTIVE_ARCH="$ONLY_ACTIVE_ARCH"
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  BUILD_SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  echo "==> Building $CONFIG ($ARCH_LABEL) with DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
else
  echo "==> Building $CONFIG ($ARCH_LABEL)"
  echo "    tip: export DEVELOPMENT_TEAM=<your team id> for Apple Development signing from CLI"
fi

xcodebuild \
  -project "$APP_DIR/WeshomeBreak.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  "${BUILD_SETTINGS[@]}" \
  build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$PRODUCT_APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
case "$VERSION" in
  ''|*'$('*)
    VERSION="$(grep -E '^\s*MARKETING_VERSION:' "$APP_DIR/project.yml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
    ;;
esac
if [[ -z "$VERSION" ]]; then
  echo "error: could not determine marketing version" >&2
  exit 1
fi

echo "==> Checking code signature"
CODESIGN_OUT="$(mktemp)"
cleanup_tmp() { rm -f "$CODESIGN_OUT"; }
trap cleanup_tmp EXIT
set +e
codesign --display --verbose=2 "$APP_PATH" >"$CODESIGN_OUT" 2>&1
CODESIGN_STATUS=$?
set -e

AUTHORITY="$(grep -E '^Authority=' "$CODESIGN_OUT" | head -1 | sed 's/^Authority=//' || true)"
TEAM_ID="$(grep -E '^TeamIdentifier=' "$CODESIGN_OUT" | head -1 | sed 's/^TeamIdentifier=//' || true)"
SIGNED_OK=0
if [[ "$CODESIGN_STATUS" -eq 0 ]]; then
  case "$AUTHORITY" in
    "Apple Development"*|"Developer ID Application"*)
      if [[ -n "$TEAM_ID" && "$TEAM_ID" != "not set" ]]; then
        SIGNED_OK=1
      fi
      ;;
  esac
fi

if [[ "$SIGNED_OK" -ne 1 ]]; then
  if [[ "$ALLOW_UNSIGNED" -eq 1 ]]; then
    echo "warning: app is unsigned or ad-hoc ($AUTHORITY / TeamIdentifier=$TEAM_ID); continuing due to --allow-unsigned"
  else
    echo "error: app is not signed with Apple Development / Developer ID (got Authority=${AUTHORITY:-none}, TeamIdentifier=${TEAM_ID:-none})." >&2
    echo "Configure a Signing Team in Xcode, or re-run with --allow-unsigned." >&2
    exit 1
  fi
fi

DMG_NAME="WeshomeBreak-${VERSION}-${ARCH_LABEL}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Staging DMG contents"
mkdir -p "$STAGE"
ditto "$APP_PATH" "$STAGE/$PRODUCT_APP_NAME"
ln -s /Applications "$STAGE/Applications"

cat >"$STAGE/README.txt" <<EOF
Weshome Break ${VERSION}

安装
1. 将「Weshome Break」拖到「Applications」快捷方式（或复制到 /Applications）。
2. 从「应用程序」启动。

若 macOS 提示无法验证开发者（未公证的熟人分发，属预期）
1. 在 Finder 中选中「Weshome Break」。
2. 按住 Control 点击（或右键）→ 选择「打开」。
3. 在对话框中再次确认「打开」。之后即可正常双击启动。

要求：macOS 14.0+
架构：${ARCH_LABEL}
EOF

echo "==> Creating $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE"
echo "Done: $DMG_PATH"
