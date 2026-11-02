#!/usr/bin/env bash
# Usage: readme.sh [README.md] [icons dir]
# Rewrites the release table between the releases markers of the README from
# the repository's GitHub releases, with the icons from icons.sh, served from
# the icons branch. Needs gh and jq.
set -euo pipefail

readme=${1:-README.md}
icons=${2:-}
repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

releases=$(gh api "repos/$repo/releases?per_page=100" --paginate | jq -s 'add | map(select(.draft | not))')

index='{}'
[[ -n $icons && -f $icons/index.json ]] && index=$(cat "$icons/index.json")

table=$(jq -r --arg repo "$repo" --argjson icons "$index" '
  def esc: tostring | gsub("-"; "--") | gsub("_"; "__") | gsub(" "; "%20");
  def badge($label; $message; $color; $logo):
    "https://img.shields.io/badge/\($label | esc)-\($message | esc)-\($color)?style=flat-square"
    + (if $logo == "" then "" else "&logo=\($logo)&logoColor=white" end);
  def icon($v; $kind):
    ($icons[$v][$kind] // "") as $f
    | if $f == "" then "" else "<img src=\"https://raw.githubusercontent.com/\($repo)/icons/\($f)\" width=\"20\" height=\"20\" alt=\"\($kind)\"> " end;
  def mb: (. / 1048576 | round | tostring) + " MB";
  def download($assets; $kind; $version; $arch; $color; $logo):
    ($assets | map(select(.name == "\($kind)-\($version)-\($arch).apk")) | first) as $a
    | if $a then "[![\($arch)](\(badge($arch; $a.size | mb; $color; $logo)))](\($a.browser_download_url))"
      else "![\($arch)](\(badge($arch; "building"; "lightgrey"; "")))" end;

  sort_by(.tag_name | split(".") | map(tonumber)) | reverse
  | (map(select(.prerelease | not) | .tag_name) | first) as $newest
  | [ "| | Version | Released | Chromium | WebView |",
      "| --- | --- | --- | --- | --- |" ]
    + map(
        .tag_name as $v
        | (.body // "" | capture("Released to Android (?<c>[A-Za-z]+): (?<d>[0-9-]{10})") // {c: "Stable", d: ""}) as $released
        | $released.d as $date
        | (if $v == $newest then ["latest", "2ea44f"]
           elif $released.c == "Stable" then ["stable", "4285F4"]
           else [$released.c | ascii_downcase, "F9AB00"] end) as [$status, $color]
        | ([.assets[].download_count] | add // 0) as $downloads
        | "| ![M\($v | split(".")[0])](\(badge("M" + ($v | split(".")[0]); $status; $color; "googlechrome")))"
          + " | [**\($v)**](https://github.com/\($repo)/releases/tag/\($v))"
          + "<br><sub>\($downloads) downloads</sub>"
          + " | \(if $date == "" then "—" else $date end)"
          + " | \(icon($v; "chromium"))\(download(.assets; "chromium"; $v; "x86_64"; "1A73E8"; "chromium")) \(download(.assets; "chromium"; $v; "arm64"; "1A73E8"; "chromium"))"
          + " | \(icon($v; "webview"))\(download(.assets; "webview"; $v; "x86_64"; "3DDC84"; "android")) \(download(.assets; "webview"; $v; "arm64"; "3DDC84"; "android")) |")
  | join("\n")' <<<"$releases")

summary="$(jq length <<<"$releases") versions, newest first. x86_64 is for emulators and redroid, arm64 for phones."

TABLE=$table SUMMARY=$summary awk '
  /<!-- releases:start -->/ { print; print ""; print ENVIRON["SUMMARY"]; print ""; print ENVIRON["TABLE"]; print ""; skip = 1; next }
  /<!-- releases:end -->/ { skip = 0 }
  !skip' "$readme" >"$readme.tmp"
mv "$readme.tmp" "$readme"
