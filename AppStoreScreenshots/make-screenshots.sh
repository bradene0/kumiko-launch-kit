#!/bin/bash
# Captures raw app screenshots with an XCUITest, exports them from the result bundle by name, composes App Store
# images, and checks them. Reusable across apps: everything app-specific comes from the variables below.
#
#   PROJECT=MyApp.xcodeproj SCHEME=MyApp TEST=MyAppUITests/AppStoreScreenshots \
#   CONFIG=AppStore/screenshots.json OUT=AppStore/Screenshots \
#   path/to/AppStoreScreenshots/make-screenshots.sh
#
# Optional:
#   DESTINATION   default 'platform=macOS'; for iOS e.g. 'platform=iOS Simulator,name=iPhone 17 Pro Max'
#   WORKSPACE     instead of PROJECT
#   CAPTURES      where raw captures are kept (default "$OUT/../Captures")
#   SKIP_CAPTURE=1  recompose from existing captures after editing captions or style
#   STATUS_BAR=0  iOS Simulator: don't override the status bar (default: 9:41, full battery and signal, cleared after)
#   STRICT=1      fail on compose warnings (wrapped headlines, text over windows, blurry or wrong-size output)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
: "${SCHEME:?Set SCHEME}" "${TEST:?Set TEST (UITestTarget/TestClass)}" "${CONFIG:?Set CONFIG (screenshots.json)}"
OUT="${OUT:-AppStore/Screenshots}"
CAPTURES="${CAPTURES:-$(dirname "$OUT")/Captures}"
DESTINATION="${DESTINATION:-platform=macOS}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
# xcrun swift uses Xcode's toolchain even when another swift (e.g. swiftly) comes first on PATH.
swift_run() { xcrun swift "$@" 2> >(grep -v -e NoUsage -e 'docs.swift.org' >&2); }

if [[ "${SKIP_CAPTURE:-0}" != "1" ]]; then
  if [[ -n "${WORKSPACE:-}" ]]; then CONTAINER=(-workspace "$WORKSPACE"); else CONTAINER=(-project "${PROJECT:?Set PROJECT or WORKSPACE}"); fi
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT

  if [[ "$DESTINATION" == *"iOS Simulator"* && "$DESTINATION" =~ name=([^,]+) ]]; then
    SIMULATOR="${BASH_REMATCH[1]}"
    xcrun simctl boot "$SIMULATOR" 2>/dev/null || true          # already booted is fine
    if [[ "${STATUS_BAR:-1}" == "1" ]]; then
      xcrun simctl status_bar "$SIMULATOR" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
    fi
  fi

  echo "Capturing screenshots ($TEST on $DESTINATION)…"
  # TEST_RUNNER_ variables reach the test process without the prefix; the capture test skips unless it is set.
  if ! TEST_RUNNER_APPSTORE_SCREENSHOTS=1 xcodebuild test "${CONTAINER[@]}" -scheme "$SCHEME" -configuration Debug \
        -destination "$DESTINATION" -only-testing:"$TEST" -resultBundlePath "$WORK/shots.xcresult" -allowProvisioningUpdates \
        > "$WORK/xcodebuild.log" 2>&1; then
    grep -E "error:|failed|Failing|XCTAssert" "$WORK/xcodebuild.log" | head -20 >&2
    [[ -n "${SIMULATOR:-}" && "${STATUS_BAR:-1}" == "1" ]] && xcrun simctl status_bar "$SIMULATOR" clear
    echo "Capture failed. Full log: $WORK/xcodebuild.log (kept)" >&2; trap - EXIT; exit 1
  fi
  [[ -n "${SIMULATOR:-}" && "${STATUS_BAR:-1}" == "1" ]] && xcrun simctl status_bar "$SIMULATOR" clear
  xcrun xcresulttool export attachments --path "$WORK/shots.xcresult" --output-path "$WORK/attachments" > /dev/null
  rm -rf "$CAPTURES"
  swift_run "$HERE/export-captures.swift" "$WORK/attachments" "$CAPTURES"
fi

echo "Composing…"
COMPOSE_FLAGS=(--overview "$(dirname "$OUT")/Screenshots-overview.png")
[[ "${STRICT:-0}" == "1" ]] && COMPOSE_FLAGS+=(--strict)
swift_run -O "$HERE/compose.swift" "$CONFIG" "$CAPTURES" "$OUT" "${COMPOSE_FLAGS[@]}"

# Every image must be one of the configured sizes and opaque: App Store Connect rejects PNGs with alpha.
echo "Checking…"
SIZES=" "; i=0
while plutil -extract "sizes.$i" json -o /dev/null "$CONFIG" 2>/dev/null; do
  SIZES+="$(plutil -extract "sizes.$i.width" raw -o - "$CONFIG")x$(plutil -extract "sizes.$i.height" raw -o - "$CONFIG") "; i=$((i + 1))
done
FAILED=0
for png in "$OUT"/*.png; do
  info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$png")"
  w="$(awk '/pixelWidth/ {print $2}' <<< "$info")"; h="$(awk '/pixelHeight/ {print $2}' <<< "$info")"; alpha="$(awk '/hasAlpha/ {print $2}' <<< "$info")"
  if [[ "$SIZES" == *" ${w}x${h} "* && "$alpha" == "no" ]]; then
    echo "  ok   $(basename "$png") ${w}×${h}, opaque"
  else
    echo "  FAIL $(basename "$png") ${w}×${h}, alpha: $alpha (expected one of:$SIZES opaque)"; FAILED=1
  fi
done
[[ $FAILED -eq 0 ]] || { echo "Check failed."; exit 1; }
echo "Done. Upload the PNGs in $OUT; review $(dirname "$OUT")/Screenshots-overview.png first."
