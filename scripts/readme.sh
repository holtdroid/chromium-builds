#!/usr/bin/env bash
# Usage: readme.sh [README.md] [icons dir]
# Rewrites the release table between the releases markers of the README from
# the repository's GitHub releases, with the icons from icons.sh, served from
# the icons branch, and the builds that running build workflows have queued or
# are building. The download badges are fixed-width SVGs written to
# <icons dir>/badges and served from the icons branch too. Needs gh, jq and curl.
set -euo pipefail

readme=${1:-README.md}
here=$(cd "$(dirname "$0")" && pwd)
icons=${2:-}
repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

releases=$(gh api "repos/$repo/releases?per_page=100" --paginate | jq -s 'add | map(select(.draft | not))')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

planned='[]'
for run in $(gh api "repos/$repo/actions/workflows/build.yml/runs?per_page=30" \
  --jq '.workflow_runs[] | select(.status != "completed") | .id'); do
  gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" --paginate \
    | jq -s 'map(.jobs[] | {id, name, status, conclusion})' >"$tmp/jobs.json"
  jobs=$(cat "$tmp/jobs.json")
  resolve=$(jq -r '.[] | select(.name == "resolve" and .conclusion == "success") | .id' <<<"$jobs")
  [[ -n $resolve ]] || continue
  plan=$(curl -fsSL -H "Authorization: Bearer ${GH_TOKEN:-$(gh auth token)}" \
    "https://api.github.com/repos/$repo/actions/jobs/$resolve/logs" | sed -E 's/^[0-9]{4}-[0-9-]+T[0-9:.]+Z //' \
    | awk '!d && /^\[$/ { f = 1 } f { print } f && /^\]$/ { f = 0; d = 1 }')
  echo "${plan:-[]}" >"$tmp/plan.json"
  planned=$(jq -c --slurpfile plan "$tmp/plan.json" --slurpfile jobs "$tmp/jobs.json" '$plan[0] as $plan | $jobs[0] as $jobs | . + [
    $plan[] | . as $b
    | [$jobs[] | select(.name | startswith("\($b.version) \($b.arch) / "))] as $own
    | if $own == [] then "queued" elif any($own[]; .status != "completed") then "building" else empty end
    | {version: $b.version, arch: $b.arch, state: .} ]' <<<"$planned")
done

for channel in Beta Stable; do
  curl -fsS "https://chromiumdash.appspot.com/fetch_releases?channel=$channel&platform=Android&num=1000"
done | jq -s 'add | map({key: .version, value: {channel, time}}) | from_entries' >"$tmp/dash.json"
echo "$planned" >"$tmp/planned.json"

index='{}'
[[ -n $icons && -f $icons/index.json ]] && index=$(cat "$icons/index.json")

table=$(jq -r --arg repo "$repo" --argjson icons "$index" --slurpfile planned "$tmp/planned.json" --slurpfile dash "$tmp/dash.json" '
  $planned[0] as $planned | $dash[0] as $dash |
  def icon($v; $kind):
    ($icons[$v][$kind] // "") as $f
    | if $f == "" then "" else "<img src=\"https://raw.githubusercontent.com/\($repo)/icons/\($f)\" width=\"32\" height=\"32\" alt=\"\($kind)\">" end;
  def mb: (. / 1048576 | round | tostring) + " MB";
  def state($version; $arch):
    [$planned[] | select(.version == $version and .arch == $arch) | .state]
    | if index("building") then "building" elif index("queued") then "queued" else "not built" end;
  def download($assets; $kind; $version; $arch):
    ($assets | map(select(.name == "\($kind)-\($version)-\($arch).apk")) | first) as $a
    | state($version; $arch) as $state
    | "https://raw.githubusercontent.com/\($repo)/icons/badges/\($kind)-\($arch)-\(if $a then $a.size | mb else $state end | ascii_downcase | gsub(" "; "-")).svg" as $svg
    | "[![\($arch)](\($svg))](\(if $a then $a.browser_download_url else "https://github.com/\($repo)/actions/workflows/build.yml" end))";

  (map(.tag_name)) as $released
  | . + ([$planned[].version] | unique | map(select(. as $v | $released | index($v) | not))
      | map(. as $v | ($dash[$v] // {channel: "Stable"}) as $d
        | {tag_name: $v, assets: [], pending: true, prerelease: ($d.channel != "Stable"),
           body: "Released to Android \($d.channel): \($d.time // 0 | ./1000 | todate)"}))

  | sort_by(.tag_name | split(".") | map(tonumber)) | reverse
  | (map(select((.prerelease or .pending) | not) | .tag_name) | first) as $newest
  | [ "| | Version | Released | | Chromium | | WebView |",
      "| --- | --- | --- | :---: | --- | :---: | --- |" ]
    + map(
        .tag_name as $v
        | (.body // "" | capture("Released to Android (?<c>[A-Za-z]+): (?<d>[0-9-]{10})") // {c: "Stable", d: ""}) as $released
        | $released.d as $date
        | (if $v == $newest then "latest" else $released.c | ascii_downcase end) as $status
        | ([.assets[].download_count] | add // 0) as $downloads
        | (if .pending then "**\($v)**<br><sub>\(if any($planned[]; .version == $v and .state == "building") then "building" else "queued" end)</sub>"
           else "[**\($v)**](https://github.com/\($repo)/releases/tag/\($v))<br><sub>\($downloads) downloads</sub>" end) as $title
        | ($v | split(".")[0]) as $m
        | "| [![M\($m) \($status)](https://raw.githubusercontent.com/\($repo)/icons/badges/m-\($m)-\($status).svg)](\(if .pending then "https://github.com/\($repo)/actions/workflows/build.yml" else "https://github.com/\($repo)/releases/tag/\($v)" end))"
          + " | \($title)"
          + " | \(if $date == "" then "—" else $date | gsub("-"; "\u2011") end)"
          + " | \(icon($v; "chromium"))"
          + " | \(download(.assets; "chromium"; $v; "x86_64"))<br>\(download(.assets; "chromium"; $v; "arm64"))"
          + " | \(icon($v; "webview"))"
          + " | \(download(.assets; "webview"; $v; "x86_64"))<br>\(download(.assets; "webview"; $v; "arm64")) |")
  | join("\n")' <<<"$releases")

pending=$(jq --slurpfile planned "$tmp/planned.json" '(map(.tag_name)) as $released
  | [$planned[0][].version] | unique | map(select(. as $v | $released | index($v) | not)) | length' <<<"$releases")
summary="$(jq length <<<"$releases") versions published, $pending more queued or building, newest first. x86_64 is for emulators and redroid, arm64 for phones."

badge_svg() {
  local label=$1 message=$2 color=$3 logo
  logo=$(sed -nE 's/.* d="([^"]+)".*/\1/p' "$here/logos/$4.svg")
  cat <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="136" height="20" role="img" aria-label="$label: $message">
<rect width="66" height="20" fill="#555"/><rect x="66" width="70" height="20" fill="#$color"/>
<svg x="5" y="3" width="14" height="14" viewBox="0 0 24 24"><path fill="#fff" d="$logo"/></svg>
<g fill="#fff" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11" text-anchor="middle">
<text x="43" y="14">$label</text><text x="101" y="14">$message</text>
</g>
</svg>
SVG
}

if [[ -n $icons ]]; then
  mkdir -p "$icons/badges"
  grep -oE 'icons/badges/[a-z]+-[a-z0-9_]+-[a-z0-9-]+\.svg' <<<"$table" | sort -u | while read -r path; do
    name=${path#icons/badges/}
    name=${name%.svg}
    kind=${name%%-*}
    if [[ $kind == m ]]; then
      milestone=${name#m-}
      status=${milestone#*-}
      case $status in latest) color=2EA44F ;; stable) color=4285F4 ;; *) color=F9AB00 ;; esac
      badge_svg "M${milestone%%-*}" "$status" "$color" googlechrome >"$icons/badges/$name.svg"
      continue
    fi
    rest=${name#*-}
    arch=${rest%%-*}
    message=${rest#*-}
    case $kind in chromium) color=1A73E8 logo=googlechrome ;; *) color=3DDC84 logo=android ;; esac
    case $message in
      *-mb) message="${message%-mb} MB" ;;
      building) color=DFB317 ;;
      *) message=${message//-/ } color=9F9F9F ;;
    esac
    badge_svg "$arch" "$message" "$color" "$logo" >"$icons/badges/$name.svg"
  done
fi

printf '%s\n\n%s\n' "$summary" "$table" >"$tmp/table.md"
TABLE=$tmp/table.md awk '
  /<!-- releases:start -->/ { print; print ""; while ((getline line <ENVIRON["TABLE"]) > 0) print line; print ""; skip = 1; next }
  /<!-- releases:end -->/ { skip = 0 }
  !skip' "$readme" >"$readme.tmp"
mv "$readme.tmp" "$readme"
