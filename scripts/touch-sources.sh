#!/usr/bin/env bash
# Sets every file in the checkout, except src/out, to one fixed mtime, so a
# build directory carried over from another machine stays up to date.
set -euo pipefail

root=${CHROMIUM_ROOT:-$PWD/chromium}
cd "$root"
find src -path src/out -prune -o -print0 | xargs -0 -P 4 touch -h -c -d '2000-01-01T00:00:00Z'
