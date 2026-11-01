#!/bin/zsh
# Builds the macOS app without installing dependencies or modifying the system.
set -euo pipefail
cd "$(dirname "$0")/.."

if (( $# != 0 )); then
  echo "Usage: $0" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Tvo's build script only supports macOS." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift must already be installed to build Tvo. This script does not install developer tools." >&2
  exit 1
fi

mkdir -p build
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

swift build -c release --product GooglyMac

# Assemble and sign outside the project: iCloud-synced folders can attach Finder
# info to the bundle, which codesign rejects.
FINAL="build/Tvo.app"
APP="$STAGE/Tvo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/GooglyMac" "$APP/Contents/MacOS/GooglyMac"
cp Mac/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${TVO_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TVO_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${TVO_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TVO_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
cp Shared/Fonts/*.ttf "$APP/Contents/Resources/"

IDENTITY=$(security find-identity -v -p codesigning | grep '"Apple Development' | grep -v REVOKED | head -1 | awk '{print $2}' || true)
codesign --force --sign "${IDENTITY:--}" "$APP"
if [[ "$(spctl -a -vv "$APP" 2>&1 || true)" == *REVOKED* ]]; then
  echo "Signing certificate is revoked; signing ad hoc instead"
  codesign --force --sign - "$APP"
fi

rm -rf "$FINAL"
ditto --norsrc --noextattr "$APP" "$FINAL"
echo "Built Mac app: $FINAL"
echo "To build and install the iPhone app, open GooglyEyes.xcodeproj in Xcode."
