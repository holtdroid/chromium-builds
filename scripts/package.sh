#!/usr/bin/env bash
# Usage: package.sh <version> <arch> <dest>
# Copies the built APKs to <dest> as chromium-<version>-<arch>.apk and
# webview-<version>-<arch>.apk.
set -euo pipefail

version=${1:?version}
arch=${2:?arch}
dest=${3:?dest}
root=${CHROMIUM_ROOT:-$PWD/chromium}
apks=$root/src/out/$arch/apks

mkdir -p "$dest"
cp "$apks/ChromePublic.apk" "$dest/chromium-$version-$arch.apk"
webview=$(find "$apks" -maxdepth 1 -name 'SystemWebView*.apk' ! -name '*Shell*' | head -1)
cp "$webview" "$dest/webview-$version-$arch.apk"
ls -l "$dest"
