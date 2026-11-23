#!/usr/bin/env bash
# Link this clone's .git/hooks/pre-commit at the committed hook.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$(git -C "$ROOT" rev-parse --git-path hooks)"
mkdir -p "$HOOKS_DIR"
ln -sfn "$ROOT/.githooks/pre-commit" "$HOOKS_DIR/pre-commit"
echo "pre-commit -> $ROOT/.githooks/pre-commit"
