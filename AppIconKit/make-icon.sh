#!/bin/bash
# Builds an app icon from an appicon.json, then validates every output with Apple's tools:
#   - actool compiles AppIcon.appiconset (macOS), AppIcon-iOS.appiconset (iOS) and AppIcon.icon (macOS and iOS)
#     in a scratch asset catalog, with no errors or warnings allowed;
#   - sips checks every PNG's pixel size against Contents.json, and that the iOS icon has no alpha channel.
#
#   AppIconKit/make-icon.sh path/to/appicon.json [--strict]
#
# --strict also fails on design warnings (thin strokes, low contrast, glyph outside the safe area…).
# SKIP_VALIDATE=1 only builds. SKIP_BUILD=1 only validates the existing output (e.g. after editing AppIcon.icon in
# Icon Composer).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:?Usage: make-icon.sh path/to/appicon.json [--strict]}"
shift
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building icon from $CONFIG…"
  # xcrun swift uses Xcode's toolchain even when another swift (e.g. swiftly) comes first on PATH.
  xcrun swift -O "$HERE/build-icon.swift" "$CONFIG" --house-style "$HERE/house-style.json" "$@" 2> >(grep -v -e NoUsage -e 'docs.swift.org' >&2)
fi

[[ "${SKIP_VALIDATE:-0}" == "1" ]] && exit 0

CONFIG_DIR="$(cd "$(dirname "$CONFIG")" && pwd)"
OUT_REL="$(plutil -extract output raw -o - "$CONFIG" 2>/dev/null || echo Output)"
OUT="$(cd "$CONFIG_DIR" && cd "$OUT_REL" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# actool prints "/* com.apple.actool.errors */" etc. sections; any error, warning or notice section fails validation.
compile() { # name platform min-os input...
  local name="$1" platform="$2" min="$3"; shift 3
  mkdir -p "$WORK/$name"
  local log="$WORK/$name/actool.txt"
  if ! xcrun actool "$@" --compile "$WORK/$name" --platform "$platform" --minimum-deployment-target "$min" \
        --app-icon AppIcon --output-partial-info-plist "$WORK/$name/partial.plist" \
        --errors --warnings --notices --output-format human-readable-text > "$log" 2>&1 \
     || grep -qE 'com\.apple\.actool\.(errors|warnings|notices|document\.(errors|warnings|notices))' "$log"; then
    echo "  FAIL actool $name"; sed 's/^/       /' "$log"; FAILED=1
  else
    echo "  ok   actool $name → $(cd "$WORK/$name" && ls | grep -v -e partial.plist -e actool.txt | tr '\n' ' ')"
  fi
}

catalog() { # catalog-dir appiconset
  mkdir -p "$1"
  printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$1/Contents.json"
  cp -R "$2" "$1/AppIcon.appiconset"
}

echo "Validating…"
catalog "$WORK/mac.xcassets" "$OUT/AppIcon.appiconset"
compile appiconset-macos macosx 11.0 "$WORK/mac.xcassets"
if [[ -d "$OUT/AppIcon-iOS.appiconset" ]]; then
  catalog "$WORK/ios.xcassets" "$OUT/AppIcon-iOS.appiconset"
  compile appiconset-ios iphoneos 17.0 "$WORK/ios.xcassets"
fi
if [[ -d "$OUT/AppIcon.icon" ]]; then
  compile icon-macos macosx 11.0 "$OUT/AppIcon.icon"
  compile icon-ios iphoneos 17.0 "$OUT/AppIcon.icon"
  if [[ -f "$WORK/icon-macos/AppIcon.icns" ]]; then
    # actool's pre-macOS 26 fallback, rendered by Apple from the .icon; kept for comparison.
    cp "$WORK/icon-macos/AppIcon.icns" "$OUT/Renders/actool-fallback-AppIcon.icns"
  fi
fi

# Pixel sizes: each Contents.json entry's size × scale must match the PNG exactly.
check_set() { # appiconset
  local set="$1" i=0
  while plutil -extract "images.$i" json -o /dev/null "$set/Contents.json" 2>/dev/null; do
    local file size scale expected w h
    file="$(plutil -extract "images.$i.filename" raw -o - "$set/Contents.json")"
    size="$(plutil -extract "images.$i.size" raw -o - "$set/Contents.json")"
    scale="$(plutil -extract "images.$i.scale" raw -o - "$set/Contents.json" 2>/dev/null || echo 1x)"
    expected=$(( ${size%%x*} * ${scale%x} ))
    w="$(sips -g pixelWidth "$set/$file" | awk '/pixelWidth/ {print $2}')"
    h="$(sips -g pixelHeight "$set/$file" | awk '/pixelHeight/ {print $2}')"
    if [[ "$w" == "$expected" && "$h" == "$expected" ]]; then
      echo "  ok   $(basename "$set")/$file ${w}×${h}"
    else
      echo "  FAIL $(basename "$set")/$file is ${w}×${h}, expected ${expected}×${expected}"; FAILED=1
    fi
    i=$((i + 1))
  done
  [[ $i -gt 0 ]] || { echo "  FAIL $(basename "$set") has no images"; FAILED=1; }
}
check_set "$OUT/AppIcon.appiconset"
if [[ -d "$OUT/AppIcon-iOS.appiconset" ]]; then
  check_set "$OUT/AppIcon-iOS.appiconset"
  if [[ "$(sips -g hasAlpha "$OUT/AppIcon-iOS.appiconset/AppIcon-1024.png" | awk '/hasAlpha/ {print $2}')" == "no" ]]; then
    echo "  ok   AppIcon-iOS.appiconset/AppIcon-1024.png is opaque"
  else
    echo "  FAIL AppIcon-iOS.appiconset/AppIcon-1024.png has an alpha channel (App Store rejects it)"; FAILED=1
  fi
fi

if [[ $FAILED -ne 0 ]]; then echo "Validation failed."; exit 1; fi
echo "Validation passed. Review $OUT/preview.png"
