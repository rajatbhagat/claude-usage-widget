#!/bin/sh
# Builds the app (Release) and installs it to ~/Applications, then launches it.
set -e -o pipefail
cd "$(dirname "$0")"
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release \
  -derivedDataPath build build | grep -E "error:|warning:|BUILD"
APP="build/Build/Products/Release/ClaudeUsage.app"
mkdir -p ~/Applications
pkill -x ClaudeUsage 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/ClaudeUsage.app
cp -R "$APP" ~/Applications/ClaudeUsage.app
open ~/Applications/ClaudeUsage.app
echo "Installed ~/Applications/ClaudeUsage.app — now add the widget: right-click the desktop → Edit Widgets → Claude Code Usage"
