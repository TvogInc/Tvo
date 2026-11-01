#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Tvo's iPhone installer handoff only supports macOS." >&2
  exit 1
fi

if (( $# != 1 )); then
  echo "Usage: $0 path/to/Tvo.ipa" >&2
  exit 2
fi

IPA_PATH="$1"
if [[ ! -f "$IPA_PATH" ]]; then
  echo "IPA not found: $IPA_PATH" >&2
  exit 1
fi

if ! /usr/bin/unzip -tq "$IPA_PATH" >/dev/null 2>&1; then
  echo "The supplied file is not a valid IPA/ZIP archive: $IPA_PATH" >&2
  exit 1
fi

if ! /usr/bin/unzip -Z1 "$IPA_PATH" | /usr/bin/grep -Eq '^Payload/[^/]+\.app/Info\.plist$'; then
  echo "The IPA does not contain an iOS app at Payload/<app>.app/Info.plist." >&2
  exit 1
fi

if ! /usr/bin/open -a AltServer >/dev/null 2>&1; then
  echo "AltServer is not installed. Download it from https://cdn.altstore.io/file/altstore/altserver.zip and try again." >&2
  exit 1
fi

/usr/bin/open -R "$IPA_PATH"
echo "AltServer is open and Finder has selected the IPA."
echo "Move the IPA to your iPhone (for example with AirDrop), then in AltStore open My Apps, tap +, and select the IPA."
echo "Keep AltServer running on your Mac to sign and refresh the app."
echo "This handoff does not collect or store Apple ID credentials in Tvo."
