#!/bin/sh
# Usage: tools/render-screenshots/render.sh [out-dir]   (default: docs)
# Compiles the widget's views into a small CLI and renders widget-{small,medium,large}.png
# from the snapshot the menu-bar app last wrote (falls back to placeholder data).
set -e
cd "$(dirname "$0")/../.."
TMP=$(mktemp -d)
# The CLI has its own entry point, so drop the widget's @main and the #Preview block.
sed -e '/^@main$/d' -e '/^#Preview/,$d' ClaudeUsageWidget/ClaudeUsageWidget.swift > "$TMP/Widget.swift"
swiftc -O -target arm64-apple-macosx14.0 \
  Shared/UsageSnapshot.swift "$TMP/Widget.swift" tools/render-screenshots/main.swift \
  -o "$TMP/render"
"$TMP/render" "${1:-docs}"
rm -rf "$TMP"
