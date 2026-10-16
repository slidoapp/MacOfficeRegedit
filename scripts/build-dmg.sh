#!/bin/bash
# Builds a Release archive of MacOfficeRegedit and packages it as a DMG.
#
# Usage: scripts/build-dmg.sh [output-dir]        (default: build/)
#
# Environment (all optional):
#   BUILD_NUMBER                 CFBundleVersion; defaults to the number of commits on HEAD.
#   DEVELOPER_ID_APPLICATION     Signing identity, e.g. "Developer ID Application: Name (TEAMID)".
#                                Without it the app is signed ad hoc (fine for local use, but
#                                Gatekeeper blocks it when downloaded).
#   DEVELOPMENT_TEAM             Team ID for the identity above.
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
#                                Apple ID, team and app-specific password for notarization;
#                                only used together with DEVELOPER_ID_APPLICATION.
#
# Writes dmg_path, version and build_number to $GITHUB_OUTPUT when running in GitHub Actions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/src/MacOfficeRegedit.xcodeproj"
SCHEME="MacOfficeRegedit"
APP_NAME="MacOfficeRegedit"
OUTPUT_DIR="${1:-$ROOT/build}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"
VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ *MARKETING_VERSION = / { print $2; exit }')"
if [[ -z "$VERSION" ]]; then
    echo "error: could not read MARKETING_VERSION" >&2
    exit 1
fi
echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) with $(xcodebuild -version | head -1)"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    SIGNING=(
        CODE_SIGN_STYLE=Manual
        "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION"
        "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-}"
        ENABLE_HARDENED_RUNTIME=YES
        "OTHER_CODE_SIGN_FLAGS=--timestamp"
    )
else
    echo "warning: DEVELOPER_ID_APPLICATION is not set; signing ad hoc (the DMG won't be notarized)" >&2
    SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ARCHIVE="$WORK_DIR/$APP_NAME.xcarchive"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    "${SIGNING[@]}" \
    | grep -E "error:|warning:|\*\* ARCHIVE" || true
APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
    echo "error: archive failed, $APP not found" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

# The DMG holds the app and a link to /Applications for drag-and-drop installation.
STAGING="$WORK_DIR/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

DMG="$OUTPUT_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER.dmg"
rm -f "$DMG"
# `hdiutil create` is deprecated on macOS 27 in favour of `diskutil image create`, which older systems lack.
if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName "$APP_NAME $VERSION" "$STAGING" "$DMG" >/dev/null
else
    hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -format UDZO -ov "$DMG" >/dev/null
fi

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
    if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
        xcrun notarytool submit "$DMG" --wait \
            --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
        xcrun stapler staple "$DMG"
    else
        echo "warning: notarization credentials are not set; the DMG is signed but not notarized" >&2
    fi
fi

hdiutil verify "$DMG" >/dev/null
echo "Created $DMG"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "dmg_path=$DMG"
        echo "version=$VERSION"
        echo "build_number=$BUILD_NUMBER"
    } >> "$GITHUB_OUTPUT"
fi
