#!/usr/bin/env bash
# Usage: build.sh <arch> [seconds]
#   arch: x86_64 | arm64
# Builds ChromePublic and SystemWebView into src/out/<arch>. With a time limit
# the build is interrupted cleanly and exits 124; running it again resumes.
set -euo pipefail

arch=${1:?arch}
limit=${2:-0}
root=${CHROMIUM_ROOT:-$PWD/chromium}
export PATH="$root/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0

case $arch in
  x86_64) cpu=x64 ;;
  arm64) cpu=arm64 ;;
  *) echo "unknown arch $arch" >&2; exit 2 ;;
esac

cd "$root/src"
out=out/$arch

if [[ ! -f $out/build.ninja ]]; then
  mkdir -p "$out"
  cat >"$out/args.gn" <<EOF
target_os = "android"
target_cpu = "$cpu"
is_debug = false
is_component_build = false
is_official_build = false
dcheck_always_on = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
treat_warnings_as_errors = false
use_remoteexec = false
android_static_analysis = "off"
skip_secondary_abi_for_cq = true
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_hevc_parser_and_hw_decoder = true
EOF
  if [[ -n ${SCCACHE_BUCKET:-} ]] && command -v sccache >/dev/null; then
    echo 'cc_wrapper = "sccache"' >>"$out/args.gn"
  fi
  gn gen "$out"
fi

targets=(chrome_public_apk system_webview_apk)
if ((limit > 0)); then
  timeout --signal=INT --kill-after=10m "$limit" autoninja -C "$out" "${targets[@]}"
else
  autoninja -C "$out" "${targets[@]}"
fi
