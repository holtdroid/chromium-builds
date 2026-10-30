#!/usr/bin/env bash
# Usage: notes.sh <version>
set -euo pipefail

version=${1:?version}
released=$(curl -fsS 'https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Android&num=1000' \
  | jq -r --arg v "$version" 'map(select(.version == $v)) | .[0].time // empty | ./1000 | todate')

cat <<NOTES
Released to Android Stable: ${released:-unknown}


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
