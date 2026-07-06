#!/usr/bin/env bash
# 从 CHANGELOG.md 提取指定版本段落（如 1.1、1.0.10），供 GitHub Release 正文使用。
set -euo pipefail

VERSION="${1:-}"
CHANGELOG="${2:-CHANGELOG.md}"

if [ -z "$VERSION" ]; then
  echo "usage: extract-changelog-section.sh <version> [changelog-path]" >&2
  exit 1
fi

if [ ! -f "$CHANGELOG" ]; then
  echo "changelog not found: $CHANGELOG" >&2
  exit 1
fi

awk -v ver="$VERSION" '
  BEGIN { found = 0 }
  /^## \[/ {
    if (found) { exit }
    if (index($0, "## [" ver "]") == 1) {
      found = 1
      print
      next
    }
    next
  }
  found { print }
' "$CHANGELOG"
