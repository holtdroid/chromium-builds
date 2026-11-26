#!/usr/bin/env bash
# Usage: release-json.sh <releases.json> [--dry-run]
# Uploads each version's entry of releases.json, without download counts, to
# its GitHub release as release.json, where the asset is missing or differs.
# Needs gh and jq.
set -euo pipefail

index=${1:?releases.json}
dry=${2:-}
repo=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh api "repos/$repo/releases?per_page=100" --paginate \
  | jq -s 'add | map({key: .tag_name, value: (.assets | map({key: .name, value: (.digest // "")}) | from_entries)}) | from_entries' \
    >"$tmp/digests.json"

jq -c '.versions[] | del(.latest, .downloads) | .apks |= map(del(.downloads))' "$index" | while read -r entry; do
  version=$(jq -r .version <<<"$entry")
  mkdir -p "$tmp/$version"
  file=$tmp/$version/release.json
  jq . <<<"$entry" >"$file"
  want="sha256:$(sha256sum "$file" | cut -d' ' -f1)"
  have=$(jq -r --arg v "$version" '.[$v]["release.json"] // ""' "$tmp/digests.json")
  [[ $want == "$have" ]] && continue
  echo "$version release.json ${have:+changed}${have:-new}"
  [[ $dry == --dry-run ]] && continue
  gh release upload "$version" "$file" --clobber -R "$repo" || echo "::warning::could not upload release.json to $version"
done
