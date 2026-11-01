#!/bin/zsh
# Builds the macOS app without installing dependencies or modifying the system.
set -euo pipefail
cd "$(dirname "$0")/.."

if (( $# > 1 )); then
  echo "Usage: $0 [prebuilt-Tvo.ipa]" >&2
  exit 2
fi

IPA_PATH="${1:-${TVO_IPA:-}}"

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

if [[ -n "$IPA_PATH" ]]; then
  scripts/install-iphone.sh "$IPA_PATH"
else
  echo "iPhone install skipped: no prebuilt IPA was supplied."
  echo "To hand off an IPA to Sideloadly, run: $0 path/to/Tvo.ipa"
fi
