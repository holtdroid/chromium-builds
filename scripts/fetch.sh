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
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [[ ! -d src/.git ]]; then
  git init -q src
  git -C src remote add origin https://chromium.googlesource.com/chromium/src.git
fi
retry git -C src fetch -q --depth 1 origin "refs/tags/$version:refs/tags/$version"
git -C src -c advice.detachedHead=false checkout -q --force "refs/tags/$version"

milestone=${version%%.*}
if [[ ! -d depot_tools ]]; then
  if ((milestone < 119)); then
    retry git clone -q --filter=blob:none https://chromium.googlesource.com/chromium/tools/depot_tools.git
    git -C depot_tools -c advice.detachedHead=false checkout -q \
      "$(git -C depot_tools rev-list -1 --before="$(git -C src log -1 --format=%cI)" origin/main)"
  else
    retry git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
  fi
fi

if ((milestone < 92)) && [[ ! -x bin/python ]]; then
  command -v patchelf >/dev/null || sudo apt-get install -y -qq patchelf
  curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/2.3.3 | tar -xj -C "$tmp" bin/micromamba
  retry "$tmp/bin/micromamba" create -q -y -r "$tmp/mamba" -p "$root/py2" -c conda-forge python=2.7
  patchelf --set-rpath "$root/py2/lib" "$root/py2/bin/python2.7"
  mkdir -p bin
  for name in python python2 python2.7; do
    printf '#!/bin/sh\nexec %q "$@"\n' "$root/py2/bin/python2.7" >"bin/$name"
    chmod +x "bin/$name"
  done
fi
[[ -x bin/python ]] && export PATH="$root/bin:$PATH"

export PATH="$root/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0
export GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=url.https://github.com/google/perfetto.git.insteadOf \
  GIT_CONFIG_VALUE_0=https://chromium.googlesource.com/external/github.com/google/perfetto.git

[[ -x depot_tools/ensure_bootstrap ]] && "$root/depot_tools/ensure_bootstrap"

cat >.gclient <<'EOF'
solutions = [{
  "name": "src",
  "url": "https://chromium.googlesource.com/chromium/src.git",
  "managed": False,
  "custom_deps": {"src/third_party/clang-format/script": None},
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
py=python3
[[ -x bin/python ]] && py=python
for a in amd64 i386; do "$py" src/build/linux/sysroot_scripts/install-sysroot.py --arch=$a; done
