#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 <Keylume.app> <output-directory>" >&2
  exit 2
fi
: "${MACOS_APP_IDENTITY:?Set the full Developer ID Application certificate name}"
: "${MACOS_INSTALLER_IDENTITY:?Set the full Developer ID Installer certificate name}"
team_pattern=' \(([A-Z0-9]{10})\)$'
if [[ $MACOS_APP_IDENTITY != "Developer ID Application: "* || ! $MACOS_APP_IDENTITY =~ $team_pattern ]]; then
  echo "Expected a Developer ID Application identity with a team ID." >&2
  exit 2
fi
team=${BASH_REMATCH[1]}
if [[ $MACOS_INSTALLER_IDENTITY != "Developer ID Installer: "*" ($team)" ]]; then
  echo "Expected a Developer ID Installer identity from the application signing team." >&2
  exit 2
fi
if [[ -n ${MACOS_NOTARY_PROFILE:-} ]]; then
  notary=(--keychain-profile "$MACOS_NOTARY_PROFILE")
else
  : "${MACOS_NOTARY_KEY_PATH:?Set MACOS_NOTARY_PROFILE or supply an App Store Connect team API key}"
  : "${MACOS_NOTARY_KEY_ID:?Missing App Store Connect key ID}"
  : "${MACOS_NOTARY_ISSUER_ID:?Missing App Store Connect issuer ID}"
  [[ -s $MACOS_NOTARY_KEY_PATH ]]
  notary=(--key "$MACOS_NOTARY_KEY_PATH" --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID")
fi

source_app=$1
out=$2
plist="$source_app/Contents/Info.plist"
version=$(plutil -extract CFBundleShortVersionString raw -o - "$plist")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ $(plutil -extract CFBundleIdentifier raw -o - "$plist") == app.keylume.desktop ]]
scripts=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/keylume-release.XXXXXXXX")
mount="$work/mounted"
mounted=false
cleanup() {
  if [[ $mounted == true ]]; then
    hdiutil detach "$mount" || return
  fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir "$work/disk" "$mount"
chmod 755 "$work/disk"
app="$work/disk/Keylume.app"
base="Keylume_${version}_universal"
dmg="$work/$base.dmg"
pkg="$work/$base.pkg"
ditto "$source_app" "$app"

sign=(codesign --force --timestamp --sign "$MACOS_APP_IDENTITY")
if [[ -n ${MACOS_SIGNING_KEYCHAIN:-} ]]; then
  sign+=(--keychain "$MACOS_SIGNING_KEYCHAIN")
fi
"${sign[@]}" --options runtime "$app"
requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$team\""
codesign --verify --deep --strict -R="$requirement" "$app"

notarize() {
  local archive=$1 status submission
  xcrun notarytool submit "$archive" "${notary[@]}" --wait --output-format json > "$work/notary.json"
  status=$(plutil -extract status raw -o - "$work/notary.json")
  submission=$(plutil -extract id raw -o - "$work/notary.json")
  echo "Apple notarization of ${archive##*/}: $status ($submission)"
  [[ $status == Accepted ]]
}
staple() {
  xcrun stapler staple "$1"
  xcrun stapler validate "$1"
}

# Include the app's ticket in both installers so it travels with the app after installation.
ditto -c -k --keepParent "$app" "$work/Keylume.zip"
notarize "$work/Keylume.zip"
staple "$app"
spctl --assess --type execute --verbose=2 "$app"
"$app/Contents/MacOS/keylume" --self-test "$work/self-test.json"
[[ $(plutil -extract passed raw -o - "$work/self-test.json") == true ]]

bash "$scripts/package-macos-pkg.sh" "$app" "$work" "$MACOS_INSTALLER_IDENTITY"
ln -s /Applications "$work/disk/Applications"
hdiutil create -volname Keylume -fs HFS+ -format UDZO -srcfolder "$work/disk" "$dmg"
"${sign[@]}" --identifier app.keylume.desktop.dmg "$dmg"
codesign --verify --strict -R="$requirement" "$dmg"

notarize "$pkg"
staple "$pkg"
pkgutil --check-signature "$pkg"
spctl --assess --type install --verbose=2 "$pkg"
notarize "$dmg"
staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dmg"
mounted=true
[[ $(readlink "$mount/Applications") == /Applications ]]
installed="$work/drag-install/Keylume.app"
mkdir "$work/drag-install"
ditto "$mount/Keylume.app" "$installed"
codesign --verify --deep --strict -R="$requirement" "$installed"
xcrun stapler validate "$installed"
diff -qr "$app" "$installed"
hdiutil detach "$mount"
mounted=false

mkdir -p "$out"
mv "$pkg" "$dmg" "$out/"
