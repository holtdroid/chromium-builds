<p align="center">
  <a href="https://holtdroid.github.io/holtdroid/sources/chromium/"><img src="https://github.com/holtdroid/.github/raw/main/profile/assets/social-chromium-builds.png" alt="Chromium builds — Chromium and WebView for Android from release tags"></a>
</p>

<p align="center">
  Part of <a href="https://github.com/holtdroid/holtdroid"><b>Holtdroid</b></a> ·
  <a href="https://holtdroid.github.io/holtdroid/sources/chromium/">Documentation</a> ·
  <a href="https://github.com/holtdroid">All repositories</a>
</p>

Chromium for Android, built from release tags with proprietary codecs, for
x86_64 and arm64. Each [release](../../releases) is one Chromium version
(the last Android Stable patch of its milestone) and holds:

| Asset | What |
| --- | --- |
| `chromium-<version>-<arch>.apk` | the browser, `org.chromium.chrome` |
| `webview-<version>-<arch>.apk` | the WebView provider, `com.android.webview` |

The builds are plain Chromium, without patches. The only changes from
Chromium's defaults are in [`scripts/build.sh`](scripts/build.sh):
a release build without symbols, 64-bit only, and `proprietary_codecs`
with `ffmpeg_branding = "Chrome"`, so MP4, H.264, AAC and HEVC play through
the device's own decoders. Everything is signed with Chromium's public debug
key.

They are made for [Holtdroid](https://github.com/holtdroid/holtdroid), to
reproduce web and WebView bugs on the browser version they were reported on,
and are useful for any emulator or test device.

## Not Google Chrome

No Google sign-in, sync, Play services, Safe Browsing or Widevine (DRM
video doesn't play). The WebView installs only where the system accepts
`com.android.webview` as a provider: AOSP-based images whose built-in
WebView is signed with the same debug key, or rooted devices.

## Patents

H.264, AAC and HEVC are covered by patents in some countries. Chromium on
Android decodes them through the platform's `MediaCodec`: these builds
parse the formats and leave decoding to the device. Whether that needs a license where you are
is for you to judge. The build scripts are Apache-2.0; Chromium itself is
under its [own licenses](https://chromium.googlesource.com/chromium/src/+/HEAD/LICENSE).

## How it is built

Everything runs on GitHub's free runners. A build takes far longer than one
job's six hours, so [`chain.yml`](.github/workflows/chain.yml) runs up to
twelve jobs in a row:

1. each job checks the tag out with Android dependencies and no history
   ([`fetch.sh`](scripts/fetch.sh));
2. sets every source file to one fixed mtime
   ([`touch-sources.sh`](scripts/touch-sources.sh));
3. unpacks the build directory the previous job left as an artifact;
4. builds until shortly before the time limit
   ([`build.sh`](scripts/build.sh)), and either publishes the APKs or packs
   the build directory for the next job.

Because the sources always carry the same mtime, a build directory from
another machine stays up to date and the build resumes where it stopped.

Run the **build** workflow with milestones (`130-156`, `148,152`,
`latest`), full versions (`156.0.8078.73`) and architectures. A version
that is already released is skipped. A daily run builds the newest Stable
milestone.

### Compiler cache

With the repository variables `SCCACHE_BUCKET` and `SCCACHE_REGION` and the
secrets `SCCACHE_ENDPOINT`, `SCCACHE_ACCESS_KEY` and `SCCACHE_SECRET_KEY`,
the compiler runs through [sccache](https://github.com/mozilla/sccache)
with any S3-compatible store. It mostly speeds up patch releases of a
milestone already built; every milestone brings its own clang. Forks build
without it.

### On your own machine

Linux x86_64, about 100 GB of disk and 16 GB of memory:

```sh
scripts/fetch.sh 156.0.8078.73
./chromium/src/build/install-build-deps.sh --android
scripts/touch-sources.sh
scripts/build.sh x86_64
scripts/package.sh 156.0.8078.73 x86_64 dist
```
