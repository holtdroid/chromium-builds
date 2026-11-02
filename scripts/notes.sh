#!/usr/bin/env bash
# Usage: notes.sh <version>
set -euo pipefail

version=${1:?version}
release=$(for channel in Stable Beta; do
  curl -fsS "https://chromiumdash.appspot.com/fetch_releases?channel=$channel&platform=Android&num=1000"
done | jq -s --arg v "$version" 'add | map(select(.version == $v)) | sort_by(.channel != "Stable") | .[0] // {}')
channel=$(jq -r '.channel // "Stable"' <<<"$release")
released=$(jq -r '.time // empty | ./1000 | todate' <<<"$release")

cat <<NOTES
Released to Android $channel: ${released:-unknown}


Chromium $version for Android, built from the
[\`$version\`](https://chromium.googlesource.com/chromium/src/+/refs/tags/$version) tag
with proprietary codecs (H.264, AAC, HEVC parsing) enabled.

| File | What |
| --- | --- |
| \`chromium-$version-<arch>.apk\` | the browser, \`org.chromium.chrome\` |
| \`webview-$version-<arch>.apk\` | the WebView provider, \`com.android.webview\` |

Signed with Chromium's public debug key. Not Google Chrome: no Google
services, no Widevine.
NOTES
