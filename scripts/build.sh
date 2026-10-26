#!/bin/zsh
# Builds the Mac app and a signed iPhone IPA; installs to one connected iPhone when available.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo "Xcode is required to build Tvo for iPhone. Install Xcode and try again." >&2
    exit 1
  fi
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "The selected developer directory is not a full Xcode installation: $DEVELOPER_DIR" >&2
  exit 1
fi

mkdir -p build
STAGE=$(mktemp -d)
IOS_DERIVED=$(mktemp -d "${TMPDIR:-/tmp}/tvo-ios-derived.XXXXXX")
trap 'rm -rf "$STAGE" "$IOS_DERIVED"' EXIT

swift build -c release --product GooglyMac

# Assemble and sign outside the project: iCloud-synced folders (like Documents) attach Finder
# info to the bundle, which codesign rejects. The signed app is then copied into build/.
FINAL="build/Tvo.app"
APP="$STAGE/Tvo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/GooglyMac" "$APP/Contents/MacOS/GooglyMac"
cp Mac/Info.plist "$APP/Contents/Info.plist"
cp Shared/Fonts/*.ttf "$APP/Contents/Resources/"

# Sign with your Apple Development certificate when there is one, so macOS remembers the
# Screen Recording and Microphone permissions across rebuilds. Otherwise sign ad hoc.
# Use the certificate's hash, since the same name can appear twice in the keychain.
IDENTITY=$(security find-identity -v -p codesigning | grep '"Apple Development' | grep -v REVOKED | head -1 | awk '{print $2}' || true)
codesign --force --sign "${IDENTITY:--}" "$APP"
# macOS refuses to launch an app whose certificate Apple has revoked, even when the keychain
# still lists it as valid. Fall back to ad hoc signing then (permissions reset on each rebuild).
if [[ "$(spctl -a -vv "$APP" 2>&1 || true)" == *REVOKED* ]]; then
  echo "Signing certificate is revoked; signing ad hoc instead"
  codesign --force --sign - "$APP"
fi

rm -rf "$FINAL"
ditto --norsrc --noextattr "$APP" "$FINAL"

echo "Built Mac app: $FINAL"

xcodebuild \
  -project GooglyEyes.xcodeproj \
  -scheme GooglyEyes \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$IOS_DERIVED" \
  -allowProvisioningUpdates \
  build

IOS_APP="$IOS_DERIVED/Build/Products/Release-iphoneos/Tvo.app"
if [[ ! -d "$IOS_APP" ]]; then
  echo "Xcode finished without producing the iPhone app at $IOS_APP" >&2
  exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$IOS_APP/Info.plist")

IPA_STAGE="$STAGE/ipa"
mkdir -p "$IPA_STAGE/Payload"
ditto "$IOS_APP" "$IPA_STAGE/Payload/Tvo.app"
(cd "$IPA_STAGE" && /usr/bin/zip -qry "$ROOT/build/Tvo.ipa" Payload)
echo "Built iPhone IPA: build/Tvo.ipa"

DEVICE_ID="${IOS_DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_IDS=$(xcrun devicectl list devices --json-output - | python3 -c '
import json, sys
devices = json.load(sys.stdin)["result"]["devices"]
for device in devices:
    hardware = device.get("hardwareProperties", {})
    if hardware.get("platform") == "iOS" and hardware.get("reality") == "physical":
        print(hardware.get("udid", ""))
')
  DEVICE_COUNT=$(printf '%s\n' "$DEVICE_IDS" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ "$DEVICE_COUNT" == "1" ]]; then
    DEVICE_ID=$(printf '%s\n' "$DEVICE_IDS" | sed -n '1p')
  elif [[ "$DEVICE_COUNT" -gt "1" ]]; then
    echo "More than one iPhone is paired. Set IOS_DEVICE_ID to choose one; IPA is ready at build/Tvo.ipa."
  fi
fi

if [[ -n "$DEVICE_ID" ]]; then
  if ! xcrun devicectl device install app --device "$DEVICE_ID" "$IOS_APP"; then
    echo "iPhone installation failed. The signed IPA is ready at build/Tvo.ipa; reconnect the phone and retry with IOS_DEVICE_ID=$DEVICE_ID." >&2
    exit 1
  fi
  echo "Installed Tvo ($BUNDLE_ID) on iPhone $DEVICE_ID. Unlock the iPhone and open Tvo."
else
  echo "No iPhone selected; install build/Tvo.ipa with AltStore or run again with IOS_DEVICE_ID=<device-UDID>."
fi
