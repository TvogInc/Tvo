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

if ! /usr/bin/open -a Sideloadly >/dev/null 2>&1; then
  echo "Sideloadly is not installed. Download it from https://sideloadly.io/SideloadlySetup.dmg and try again." >&2
  exit 1
fi

/usr/bin/open -R "$IPA_PATH"
echo "Sideloadly is open and Finder has selected the IPA."
echo "Drag the IPA into Sideloadly, choose your iPhone, and follow its signing prompts."
echo "Tvo does not handle your Apple ID credentials."
