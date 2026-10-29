#!/usr/bin/env bash
# Usage: resolve.sh <milestones> <arches>
#   milestones: "latest", "150", "130-156", "148,150-152" or full versions "156.0.8078.73"
#   arches:     "x86_64,arm64"
# Prints a JSON array of {version, commit, milestone, arch} for the newest
# Android Stable release of each milestone.
set -euo pipefail

milestones=${1:?milestones}
arches=${2:-x86_64,arm64}

releases=$(curl -fsS 'https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Android&num=1000')

wanted=()
IFS=',' read -ra parts <<<"$milestones"
for part in "${parts[@]}"; do
  part=${part// /}
  case $part in
    latest) wanted+=("$(jq -r 'map(.milestone) | max' <<<"$releases")") ;;
    *.*.*.*) wanted+=("$part") ;;
    *-*) for ((m = ${part%-*}; m <= ${part#*-}; m++)); do wanted+=("$m"); done ;;
    *) wanted+=("$part") ;;
  esac
done

for w in "${wanted[@]}"; do
  if [[ $w == *.*.*.* ]]; then
    jq -c --arg v "$w" 'map(select(.version == $v)) | .[0] // error("no Android Stable release \($v)")' <<<"$releases"
  else
    jq -c --argjson m "$w" '
      map(select(.milestone == $m))
      | sort_by(.version | split(".") | map(tonumber)) | last
      // error("no Android Stable release for milestone \($m)")' <<<"$releases"
  fi
done | jq -sc --arg arches "$arches" '
  [ .[] as $r | ($arches | split(",") | .[] | select(. != "")) as $a
    | {version: $r.version, commit: $r.hashes.chromium, milestone: $r.milestone, arch: $a} ]'
