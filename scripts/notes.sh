#!/usr/bin/env bash
# Usage: notes.sh <version>
set -euo pipefail

version=${1:?version}
cat <<NOTES
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
