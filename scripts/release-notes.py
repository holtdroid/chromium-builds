#!/usr/bin/env python3
"""Usage: release-notes.py <releases.json> [--dry-run]

Rewrites each GitHub release's notes from its releases.json entry, where they
differ: the files with sizes and SHA-256, install commands and links. The
first line stays "Released to Android <channel>: <time>", which readme.sh
reads. Needs gh.
"""
import json
import os
import subprocess
import sys
import tempfile

REPO = os.environ.get("GITHUB_REPOSITORY", "holtdroid/chromium-builds")
SITE = "https://holtdroid.github.io/chromium-builds/"
ARCH = {"x86_64": "x86_64 (emulators, redroid)", "arm64": "arm64 (phones, Apple Silicon emulators)"}


def mb(size):
    return f"{round(size / 1048576)} MB"


def notes(v):
    m, version = v["milestone"], v["version"]
    rows = []
    for arch in ("x86_64", "arm64"):
        for a in v["apks"]:
            if a["arch"] != arch:
                continue
            rows.append(f"| [`{a['name']}`]({a['url']}) | `{a['package']}` | {ARCH[arch]} | {mb(a['size'])} | `{a['sha256']}` |")
    arch = "x86_64" if any(a["arch"] == "x86_64" for a in v["apks"]) else "arm64"
    names = {a["kind"]: a["name"] for a in v["apks"] if a["arch"] == arch}
    install = []
    if "chromium" in names:
        install.append(f"adb install {names['chromium']}")
    if "webview" in names:
        install += [f"adb install {names['webview']}", "adb shell cmd webviewupdate set-webview-implementation com.android.webview"]
    return f"""Released to Android {v['channel']}: {v['releasedToAndroid'] or 'unknown'}


**Chromium {version} and Android WebView {m} APKs** for Android emulators and phones, built from the
[`{version}`]({v['source']}) tag of Chromium with proprietary codecs (H.264, AAC, HEVC parsing), without patches.
Unofficial build, not affiliated with Google or the Chromium project.

| File | Package | Architecture | Size | SHA-256 |
| --- | --- | --- | --- | --- |
{chr(10).join(rows)}

### Install

```sh
{chr(10).join(install)}
```

The browser installs next to Google Chrome. The WebView installs on AOSP emulator images, redroid and rooted
devices; Google APIs and Google Play images accept only Google's signed WebView. Signed with Chromium's public
debug key; no Google services, no Widevine.

[Chromium {m} page]({SITE}{m}/) · [all versions]({SITE}) · [`release.json`](https://github.com/{REPO}/releases/download/{version}/release.json) · [`releases.json`](https://raw.githubusercontent.com/{REPO}/main/releases.json)
"""


def main():
    index, dry = sys.argv[1], "--dry-run" in sys.argv
    versions = json.load(open(index))["versions"]
    current = {}
    pages = subprocess.run(["gh", "api", f"repos/{REPO}/releases?per_page=100", "--paginate", "--jq", ".[] | {tag_name, body}"],
                           check=True, capture_output=True, text=True).stdout
    for line in pages.splitlines():
        r = json.loads(line)
        current[r["tag_name"]] = (r["body"] or "").replace("\r\n", "\n")
    changed = 0
    for v in versions:
        if not v["apks"] or v["version"] not in current:
            continue
        body = notes(v)
        if current[v["version"]].strip() == body.strip():
            continue
        changed += 1
        print(f"{v['version']} notes {'would change' if dry else 'updated'}")
        if dry:
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
            f.write(body)
        if subprocess.run(["gh", "release", "edit", v["version"], "-R", REPO, "--notes-file", f.name]).returncode != 0:
            print(f"::warning::could not update the notes of {v['version']}")
        os.unlink(f.name)
    print(f"{changed} of {len(versions)} release notes {'differ' if dry else 'updated'}")


if __name__ == "__main__":
    main()
