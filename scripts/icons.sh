#!/usr/bin/env bash
# Usage: icons.sh <dir>
# Extracts the launcher icon of the Chromium and WebView APKs of every release
# not yet in <dir>/index.json. Icons are stored once per content as
# <dir>/<sha256 prefix>.<ext>, and an icon that looks the same as a stored
# one reuses it; index.json maps version -> {chromium, webview}.
# Needs gh, jq, unzip, aapt2 (AAPT2 or the newest one in $ANDROID_HOME) and
# Python with Pillow (PYTHON, default python3).
set -euo pipefail

dir=${1:?dir}
here=$(cd "$(dirname "$0")" && pwd)
repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
aapt2=${AAPT2:-$(ls -d "${ANDROID_HOME:?}"/build-tools/*/ | sort -V | tail -1)aapt2}
mkdir -p "$dir"
index=$dir/index.json
[[ -f $index ]] || echo '{}' >"$index"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

icon_path() {
  local apk=$1 path
  path=$("$aapt2" dump badging "$apk" 2>/dev/null \
    | sed -nE "s/^application-icon-([0-9]+):'(.*)'$/\1 \2/p" \
    | awk '$1 < 65535' | sort -n | tail -1 | cut -d' ' -f2)
  if [[ $path == *.xml ]]; then
    path=$("$aapt2" dump resources "$apk" 2>/dev/null \
      | awk '/ mipmap\/app_icon$/ { f = 1; next } f && /\(file\)/ { p = $3 } f && /resource 0x/ { exit } END { print p }')
  fi
  echo "$path"
}

extract() {
  local apk=$1 path hash ext same
  path=$(icon_path "$apk")
  [[ -n $path ]] || return 0
  unzip -p "$apk" "$path" >"$tmp/icon"
  case $(head -c 12 "$tmp/icon" | od -An -c | tr -d ' \n') in
    *WEBP*) ext=webp ;;
    *PNG*) ext=png ;;
    *) return 0 ;;
  esac
  same=$(${PYTHON:-python3} "$here/same_icon.py" "$tmp/icon" "$dir")
  if [[ -n $same ]]; then
    echo "$same"
    return
  fi
  hash=$(sha256sum "$tmp/icon" | cut -c1-16)
  mv "$tmp/icon" "$dir/$hash.$ext"
  echo "$hash.$ext"
}

gh api "repos/$repo/releases?per_page=100" --paginate \
  | jq -r '.[] | select(.draft | not) | .tag_name as $v
      | [ $v,
          ([.assets[].name | select(startswith("chromium-") and endswith(".apk"))] | first // ""),
          ([.assets[].name | select(startswith("webview-") and endswith(".apk"))] | first // "") ]
      | @tsv' \
  | while IFS=$'\t' read -r version chromium webview; do
      for kind in chromium webview; do
        asset=${!kind}
        [[ -n $asset ]] || continue
        jq -e --arg v "$version" --arg k "$kind" '.[$v][$k]' "$index" >/dev/null && continue
        gh release download "$version" -R "$repo" -p "$asset" -O "$tmp/app.apk" --clobber
        icon=$(extract "$tmp/app.apk")
        rm -f "$tmp/app.apk"
        [[ -n $icon ]] || continue
        jq --arg v "$version" --arg k "$kind" --arg i "$icon" '.[$v][$k] = $i' "$index" >"$tmp/index" \
          && mv "$tmp/index" "$index"
        echo "$version $kind $icon"
      done
    done
