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

python_env() {
  local name=$1 version=$2 link
  shift 2
  [[ -x $name/bin/python$version ]] && return
  [[ -x $tmp/bin/micromamba ]] || curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/2.3.3 | tar -xj -C "$tmp" bin/micromamba
  retry "$tmp/bin/micromamba" create -q -y -r "$tmp/mamba" -p "$root/$name" -c conda-forge "python=$version"
  patchelf --set-rpath "$root/$name/lib" "$root/$name/bin/python$version"
  mkdir -p bin
  for link in "$@"; do
    printf '#!/bin/sh\nexec %q "$@"\n' "$root/$name/bin/python$version" >"bin/$link"
    chmod +x "bin/$link"
  done
}

if ((milestone < 119)); then
  command -v patchelf >/dev/null || sudo apt-get install -y -qq patchelf
  mkdir -p bin
  git_shim=bin/git
  {
    printf '#!/usr/bin/env bash\nreal=%q\n' "$(command -v git)"
    cat <<'SHIM'
"$real" "$@" && exit
rc=$?
template='' url=''
for arg in "$@"; do
  case $arg in
    --template=*) template=${arg#--template=} ;;
    https://*) url=$arg ;;
  esac
done
[[ " $* " == *" clone "* && -s $template/shallow && -n $url ]] || exit $rc
dir=${*: -1}
rm -rf "$dir"
"$real" init -q "$dir"
"$real" -C "$dir" remote add origin "$url"
"$real" -C "$dir" fetch -q --depth 1 origin "$(cat "$template/shallow")"
SHIM
  } >"$git_shim"
  chmod +x "$git_shim"
  python_env py3 3.8 python3 python3.8
  if ((milestone < 92)); then
    python_env py2 2.7 python python2 python2.7
  elif ((milestone < 94)); then
    python_env py2 2.7 python2 python2.7
  fi
fi
[[ -d bin ]] && export PATH="$root/bin:$PATH"

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
  "custom_vars": {"checkout_pgo_profiles": False, "checkout_traffic_annotation_tools": False},
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
rm -f src/third_party/llvm-build/Release+Asserts/lib/libstdc++.so*
if ldd src/third_party/llvm-build/Release+Asserts/bin/clang | grep -q 'libtinfo.so.5 => not found'; then
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 -o "$tmp/libtinfo5.deb" \
    http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.3_amd64.deb
  dpkg-deb -x "$tmp/libtinfo5.deb" "$tmp/libtinfo5"
  cp -a "$tmp"/libtinfo5/lib/x86_64-linux-gnu/libtinfo.so.5* src/third_party/llvm-build/Release+Asserts/lib/
fi
py=python3
[[ -x bin/python ]] && py=python
for a in amd64 i386; do "$py" src/build/linux/sysroot_scripts/install-sysroot.py --arch=$a; done
