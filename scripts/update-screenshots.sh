#!/bin/bash
# Regenerates the README screenshots in docs/screenshots by running ScreenshotTests (a UI test against a demo
# registry) and exporting its attachments. Needs UI automation access, like the other UI tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/docs/screenshots"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TEST_RUNNER_REGEDIT_SCREENSHOTS=1 xcodebuild test \
    -project "$ROOT/src/MacOfficeRegedit.xcodeproj" \
    -scheme MacOfficeRegedit \
    -destination 'platform=macOS' \
    -only-testing:MacOfficeRegeditUITests/ScreenshotTests \
    -resultBundlePath "$WORK_DIR/Screenshots.xcresult" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= 2>&1 \
    | grep -E "error:|\*\* TEST" || true

xcrun xcresulttool export attachments --path "$WORK_DIR/Screenshots.xcresult" --output-path "$WORK_DIR/attachments" > /dev/null
mkdir -p "$OUTPUT"
# Attachment names look like "main-window_0_<UUID>.png"; keep the part before the first "_".
python3 - "$WORK_DIR/attachments" "$OUTPUT" <<'PYTHON'
import json, shutil, sys
source, output = sys.argv[1], sys.argv[2]
for test in json.load(open(f"{source}/manifest.json")):
    for attachment in test["attachments"]:
        name = attachment["suggestedHumanReadableName"].split("_")[0]
        if attachment["exportedFileName"].endswith(".png"):
            shutil.copy(f"{source}/{attachment['exportedFileName']}", f"{output}/{name}.png")
            print(f"Saved {output}/{name}.png")
PYTHON
