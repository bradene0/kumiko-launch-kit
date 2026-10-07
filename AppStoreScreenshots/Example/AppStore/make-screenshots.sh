#!/bin/bash
# Shoji Notes (example) App Store screenshots for Mac (2880×1800) and iPhone 6.9" (1320×2868).
#   AppStore/make-screenshots.sh [mac|iphone|all]     (default: all)
# Run from a normal desktop Space (not a full-screen app). Edit captions in AppStore/screenshots-<platform>.json,
# then re-run with SKIP_CAPTURE=1 to recompose in seconds.
set -euo pipefail
cd "$(dirname "$0")/.."
run() { # platform destination
  PROJECT=ShojiNotes.xcodeproj SCHEME=ShojiNotes TEST=ShojiNotesUITests/AppStoreScreenshots \
  CONFIG="AppStore/screenshots-$1.json" OUT="AppStore/$1/Screenshots" DESTINATION="$2" \
  ../make-screenshots.sh
}
case "${1:-all}" in
  mac) run mac "platform=macOS" ;;
  iphone) run iphone "platform=iOS Simulator,name=iPhone 17 Pro Max" ;;
  all) run mac "platform=macOS"; run iphone "platform=iOS Simulator,name=iPhone 17 Pro Max" ;;
  *) echo "usage: $0 [mac|iphone|all]" >&2; exit 64 ;;
esac
