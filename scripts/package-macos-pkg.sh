#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 <Keylume.app> <output-directory>" >&2
  exit 2
fi
app=$1
out=$2
plist="$app/Contents/Info.plist"
version=$(plutil -extract CFBundleShortVersionString raw -o - "$plist")
bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$plist")
[[ $bundle_id == app.keylume.desktop && ${app##*/} == Keylume.app ]]
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
binary=Contents/MacOS/keylume
architectures=$(lipo -archs "$app/$binary")
for arch in arm64 x86_64; do
  [[ " $architectures " == *" $arch "* ]]
done
codesign --verify --deep --strict "$app"

mkdir -p "$out"
work=$(mktemp -d "$out/.pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
name="Keylume_${version}_universal.pkg"
productbuild --identifier "$bundle_id" --version "$version" \
  --component "$app" /Applications "$work/$name"

# Verify the deliverable without installing over the developer's application.
pkgutil --expand-full "$work/$name" "$work/expanded"
payloads=("$work"/expanded/*.pkg/Payload/Keylume.app)
[[ ${#payloads[@]} == 1 ]]
codesign --verify --deep --strict "${payloads[0]}"
diff -qr "$app" "${payloads[0]}"
mv "$work/$name" "$out/$name"
