#!/usr/bin/env bash
# Usage: fetch.sh <version>
# Checks out Chromium <version> with Android dependencies, without history,
# into $CHROMIUM_ROOT (default ./chromium) and installs the build dependencies.
set -euo pipefail

version=${1:?version}
root=${CHROMIUM_ROOT:-$PWD/chromium}

retry() {
  local n
  for n in 1 2 3 4 5; do
    "$@" && return
    echo "attempt $n of $* failed, retrying" >&2
    sleep $((n * 30))
  done
  "$@"
}

mkdir -p "$root"
cd "$root"

if [[ ! -d depot_tools ]]; then
  retry git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$root/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0
export GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=url.https://github.com/google/perfetto.git.insteadOf \
  GIT_CONFIG_VALUE_0=https://chromium.googlesource.com/external/github.com/google/perfetto.git

"$root/depot_tools/ensure_bootstrap"

if [[ ! -d src/.git ]]; then
  git init -q src
  git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
fi
retry git -C src fetch -q --depth 1 origin "refs/tags/$version:refs/tags/$version"
git -C src -c advice.detachedHead=false checkout -q --force "refs/tags/$version"

cat >.gclient <<'EOF'
solutions = [{
  "name": "src",
  "url": "https://chromium.googlesource.com/chromium/src.git",
  "managed": False,
  "custom_deps": {},
  "custom_vars": {"checkout_pgo_profiles": False},
}]
target_os = ["android"]
EOF

retry gclient sync --nohooks --no-history --shallow -D --force --jobs 16 \
  --revision "src@$(git -C src rev-parse HEAD)"

if [[ ${CI:-} == true ]]; then
  ./src/build/install-build-deps.sh --android --no-prompt --no-chromeos-fonts \
    || ./src/build/install-build-deps.sh --android --no-prompt --no-chromeos-fonts --unsupported \
    || {
      echo "::warning::install-build-deps.sh of $version failed on this Ubuntu, installing the tools Android builds need"
      sudo apt-get install -y -qq gperf bison flex patch perl zip unzip xz-utils lsb-release
    }
fi

retry gclient runhooks
for a in amd64 i386; do python3 src/build/linux/sysroot_scripts/install-sysroot.py --arch=$a; done
