#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This SideServer handoff only supports macOS." >&2
  exit 1
fi

if (( $# > 0 )); then
  echo "Usage: $0" >&2
  exit 2
fi

SIDESERVER_VERSION="v1.0.6"
SIDESERVER_TEAM_ID="A72ZC8AJ5X"
SIDESERVER_DMG_URL="https://github.com/SideStore/SideServer-macOS/releases/download/${SIDESERVER_VERSION}/SideServer.dmg"
TVO_IPA_URL="https://github.com/TvogInc/Tvo/releases/latest/download/Tvo.ipa"

verify_sideserver() {
  local app_path="$1"
  local signature_info
  local team_id
  local bundle_id

  if ! /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
    echo "SideServer's code signature could not be verified; it was not launched." >&2
    return 1
  fi

  if ! signature_info=$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1); then
    echo "Could not read SideServer's signing identity; it was not launched." >&2
    return 1
  fi

  team_id=$(printf '%s\n' "$signature_info" | /usr/bin/sed -n 's/^TeamIdentifier=//p')
  if [[ "$team_id" != "$SIDESERVER_TEAM_ID" ]]; then
    echo "SideServer was not signed by its expected developer; it was not launched." >&2
    return 1
  fi

  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
  if [[ "$bundle_id" != "io.SideStore.SideServer" ]]; then
    echo "The app does not have SideServer's expected bundle identifier." >&2
    return 1
  fi

  if ! /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path" >/dev/null 2>&1; then
    echo "macOS Gatekeeper did not accept SideServer; it was not launched." >&2
    echo "This script will not override Gatekeeper or change macOS security settings." >&2
    return 1
  fi
}

TEMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/tvo-sideserver.XXXXXX")
MOUNT_POINT="$TEMP_DIR/mount"
MOUNTED=0
cleanup() {
  if (( MOUNTED )); then
    /usr/sbin/diskutil eject "$MOUNT_POINT" >/dev/null
  fi
  /bin/rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
/bin/mkdir "$MOUNT_POINT"

INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/SideServer-${SIDESERVER_VERSION}.app"

if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
  verify_sideserver "$APP_PATH"
else
  DMG_PATH="$TEMP_DIR/SideServer.dmg"
  /usr/bin/curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --proto '=https' \
    --tlsv1.2 \
    "$SIDESERVER_DMG_URL" \
    --output "$DMG_PATH"

  /usr/sbin/diskutil image attach \
    --readOnly \
    --mountOptions nobrowse \
    --mountPoint "$MOUNT_POINT" \
    "$DMG_PATH" >/dev/null
  MOUNTED=1

  SOURCE_APP="$MOUNT_POINT/SideServer.app"
  if [[ ! -d "$SOURCE_APP" ]]; then
    echo "The official SideServer disk image did not contain SideServer.app." >&2
    exit 1
  fi
  verify_sideserver "$SOURCE_APP"

  /bin/mkdir -p "$INSTALL_DIR"
  /usr/bin/ditto "$SOURCE_APP" "$APP_PATH"
  verify_sideserver "$APP_PATH"
fi

IPA_PATH="$TEMP_DIR/Tvo.ipa"
/usr/bin/curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --proto '=https' \
  --tlsv1.2 \
  "$TVO_IPA_URL" \
  --output "$IPA_PATH"

if ! /usr/bin/unzip -tq "$IPA_PATH" >/dev/null 2>&1; then
  echo "The latest GitHub release did not provide a valid Tvo.ipa file." >&2
  exit 1
fi

APP_INFO=$(/usr/bin/unzip -Z1 "$IPA_PATH" | /usr/bin/grep -E '^Payload/[^/]+\.app/Info\.plist$' | /usr/bin/head -1 || true)
if [[ -z "$APP_INFO" ]]; then
  echo "The downloaded IPA does not contain an iPhone app." >&2
  exit 1
fi

if ! /usr/bin/unzip -p "$IPA_PATH" "$APP_INFO" > "$TEMP_DIR/Info.plist"; then
  echo "Could not read the app metadata from the downloaded IPA." >&2
  exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TEMP_DIR/Info.plist")" != "co.tvog.tvo.phone" ]]; then
  echo "The downloaded IPA does not have Tvo's expected bundle identifier." >&2
  exit 1
fi

DOWNLOAD_DIR="${TVO_DOWNLOAD_DIR:-$HOME/Downloads}"
/bin/mkdir -p "$DOWNLOAD_DIR"
FINAL_IPA="$DOWNLOAD_DIR/Tvo-$(/bin/date +%Y%m%d-%H%M%S).ipa"
if [[ -e "$FINAL_IPA" ]]; then
  echo "Refusing to overwrite an existing IPA: $FINAL_IPA" >&2
  exit 1
fi
/bin/cp "$IPA_PATH" "$FINAL_IPA"

/usr/bin/open -a "$APP_PATH"
/usr/bin/open -R "$FINAL_IPA"

echo "The latest Tvo IPA is saved at: $FINAL_IPA"
echo "In SideServer, hold Option while opening its menu-bar menu and choose the IPA-sideload command."
echo "Connect and select your iPhone, then follow SideServer's signing steps."
echo "Enter Apple Account credentials only into software you trust. Tvo never receives them."
echo "SideServer v1.0.6 is a 2023 release; macOS 27 and its anisette machineID behavior are unverified."
echo "Free signing expires; reinstall or refresh as required by Apple and your sideloader."
