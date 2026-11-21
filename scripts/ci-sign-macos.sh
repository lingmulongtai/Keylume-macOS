#!/bin/bash
set -euo pipefail

: "${MACOS_CERTIFICATES_P12_BASE64:?Missing Developer ID Application and Installer identities}"
: "${MACOS_CERTIFICATES_PASSWORD:?Missing signing certificate export password}"
: "${MACOS_NOTARY_KEY_P8_BASE64:?Missing App Store Connect team API private key}"
: "${MACOS_NOTARY_KEY_ID:?Missing App Store Connect key ID}"
: "${MACOS_NOTARY_ISSUER_ID:?Missing App Store Connect issuer ID}"

umask 077
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/keylume-credentials.XXXXXXXX")
keychain="$work/signing.keychain-db"
# codesign also consults the search list when building the certificate chain.
search_list=(-d user -s)
original_keychains=$(security list-keychains -d user)
while IFS= read -r path; do
  [[ -z $path ]] || search_list+=("$path")
done < <(sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' <<< "$original_keychains")
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  security list-keychains "${search_list[@]}" >/dev/null
  rm -rf "$work"
}
trap cleanup EXIT
printf '%s' "$MACOS_CERTIFICATES_P12_BASE64" | base64 -D > "$work/certificates.p12"
export MACOS_NOTARY_KEY_PATH="$work/AuthKey.p8"
printf '%s' "$MACOS_NOTARY_KEY_P8_BASE64" | base64 -D > "$MACOS_NOTARY_KEY_PATH"
password=$(openssl rand -hex 32)
security create-keychain -p "$password" "$keychain"
security list-keychains "${search_list[@]}" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/certificates.p12" -k "$keychain" -P "$MACOS_CERTIFICATES_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/productbuild >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
rm "$work/certificates.p12"
unset MACOS_CERTIFICATES_P12_BASE64 MACOS_CERTIFICATES_PASSWORD MACOS_NOTARY_KEY_P8_BASE64 password

# Only this run's imported identities can be selected for signing.
identities=$(security find-identity -v -p basic "$keychain")
identity() {
  local kind=$1
  awk -F '"' -v kind="$kind" '
    index($2, "Developer ID " kind ": ") == 1 { name=$2; count++ }
    END {
      if (count == 1) print name
      else {
        print "Expected exactly one valid Developer ID " kind " identity in the PKCS#12 export." > "/dev/stderr"
        exit 1
      }
    }' <<< "$identities"
}
MACOS_APP_IDENTITY=$(identity Application)
MACOS_INSTALLER_IDENTITY=$(identity Installer)
export MACOS_APP_IDENTITY MACOS_INSTALLER_IDENTITY
export MACOS_SIGNING_KEYCHAIN="$keychain"
umask 022
bash "$(dirname "$0")/sign-macos-release.sh" "$@"
