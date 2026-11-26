#!/usr/bin/env python3
"""Usage: site.py <releases.json> <out dir> [base url]

Builds the GitHub Pages site from releases.json: the home page from
site/index.html and site/style.css, one page per milestone, sitemap.xml and
robots.txt. APKs and icons stay on GitHub, the pages only link to them.
"""
import html
import json
import shutil
import sys
import urllib.request
from pathlib import Path

REPO = "https://github.com/holtdroid/chromium-builds"
SOCIAL = "https://github.com/holtdroid/.github/raw/main/profile/assets/social-chromium-builds.png"
FONTS = "https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500;600&display=swap"
FAVICON = (
    "data:image/svg+xml,"
    "%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E"
    "%3Crect width='32' height='32' rx='7' fill='%23131823'/%3E"
    "%3Ctext x='6' y='22' font-family='monospace' font-size='16' fill='%239fd17a'%3E$%3C/text%3E"
    "%3Crect x='17' y='19' width='9' height='3' fill='%23ffa36b'/%3E%3C/svg%3E"
)
NOTICE = (
    '<div class="notice" role="note"><div class="wrap"><b>UNOFFICIAL</b><p>A personal side project, '
    "not affiliated with, endorsed by or connected to Google, Google Chrome or the Chromium project. "
    "The APKs are built from Chromium's public source code by this project's own scripts. "
    "Chrome is a trademark of Google LLC.</p></div></div>"
)
ARCH = {"x86_64": "x86_64 · emulators, redroid", "arm64": "arm64 · phones, Apple Silicon emulators"}

e = html.escape


def mb(size):
    return f"{round(size / 1048576)} MB"


def first_stable():
    url = "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Android&num=1000"
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            releases = json.load(r)
    except Exception as err:
        print(f"chromium dash unavailable: {err}", file=sys.stderr)
        return {}
    first = {}
    for rel in releases:
        m, t = str(rel["milestone"]), rel["time"]
        first[m] = min(first.get(m, t), t)
    import datetime

    return {m: datetime.datetime.fromtimestamp(t / 1000, datetime.timezone.utc).strftime("%Y-%m-%d") for m, t in first.items()}


def head(title, description, url, prefix, ld):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{e(title)}</title>
<meta name="description" content="{e(description)}">
<link rel="canonical" href="{url}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Chromium Builds">
<meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(description)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SOCIAL}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="{FAVICON}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="{FONTS}">
<link rel="stylesheet" href="{prefix}style.css">
<script type="application/ld+json">{json.dumps(ld, separators=(",", ":"))}</script>
</head>
<body>"""


def header(prefix):
    return f"""{NOTICE}
<header class="top">
  <div class="wrap">
    <a class="brand" href="{prefix}"><span class="p">$</span> chromium-builds</a>
    <nav aria-label="Sections">
      <a href="{prefix}#versions">VERSIONS</a>
      <a href="{prefix}#install">INSTALL</a>
      <a href="{prefix}#files">FILES</a>
      <a class="gh" href="{REPO}" target="_blank" rel="noopener">GitHub ↗</a>
    </nav>
  </div>
</header>"""


FOOTER = f"""<footer>
  <div class="wrap">
    <span>Unofficial side project, not affiliated with Google or the Chromium project · build scripts: MIT or Apache-2.0</span>
    <span>see also: <a href="https://github.com/holtdroid/holtdroid" target="_blank" rel="noopener">holtdroid</a>, <a href="{REPO}/releases" target="_blank" rel="noopener">releases</a></span>
  </div>
</footer>"""

COPY_JS = """<script>
document.addEventListener("click", async (ev) => {
  const b = ev.target.closest("[data-copy], .sha");
  if (!b) return;
  const src = b.dataset.copy ? document.getElementById(b.dataset.copy) : b;
  const text = src.dataset.text || (src.querySelector("pre")?.textContent || "").replace(/^\\$ /gm, "");
  const old = b.textContent;
  try { await navigator.clipboard.writeText(text); b.textContent = "copied"; } catch { b.textContent = "select it"; }
  setTimeout(() => (b.textContent = old), 1400);
});
</script>"""


def pill(v):
    if v["latest"]:
        return '<span class="pill pill-l">latest</span>'
    if v["channel"] == "Beta":
        return '<span class="pill pill-b">beta</span>'
    return '<span class="pill pill-s">stable</span>'


def apk(v, kind, arch):
    return next((a for a in v["apks"] if a["kind"] == kind and a["arch"] == arch), None)


def released(v):
    return (v.get("releasedToAndroid") or v["published"])[:10]


def index_rows(versions):
    rows = []
    for v in versions:
        c, w = apk(v, "chromium", "x86_64"), apk(v, "webview", "x86_64")
        if not c or not w:
            continue
        rows.append(
            f'<tr><td><div class="ver"><img src="{c["icon"] or ""}" alt="" width="26" height="26" loading="lazy">'
            f'<a href="{v["milestone"]}/">{v["version"]}</a></div></td><td>{pill(v)}</td>'
            f'<td class="dt">{released(v)}</td>'
            f'<td><a class="file" href="{c["url"]}"><span class="k">chromium</span><small>{mb(c["size"])}</small></a></td>'
            f'<td><a class="file" href="{w["url"]}"><span class="k">webview</span><small>{mb(w["size"])}</small></a></td>'
            f'<td><button type="button" class="sha" data-text="{c["sha256"]}  {c["name"]}&#10;{w["sha256"]}  {w["name"]}">sha256</button></td></tr>'
        )
    return "".join(rows)


def compact(versions):
    data, icons = [], {}
    for v in versions:
        apks = []
        for a in v["apks"]:
            name = (a["icon"] or "").rsplit("/", 1)[-1]
            if name:
                icons[name] = a["icon"]
            apks.append({"k": a["kind"][0], "r": "a" if a["arch"] == "arm64" else "x", "s": a["size"], "h": a["sha256"], "i": name})
        data.append({"v": v["version"], "m": v["milestone"], "c": "b" if v["channel"] == "Beta" else "s", "l": v["latest"], "d": released(v), "n": v["downloads"], "a": apks})
    return data, icons


def milestone_page(m, patches, base, neighbours):
    v = patches[0]
    url = f"{base}{m}/"
    title = f"Chromium {m} and Android WebView {m} APK (x86_64, arm64) · Chromium Builds"
    description = (
        f"Download Chromium {v['version']} and Android WebView {m} APKs for x86_64 emulators and arm64 phones, "
        f"released to Android {v['channel']} on {released(v)}. Built from Chromium's release tag with H.264 and AAC."
    )
    apps = []
    for kind, label, package in (("chromium", f"Chromium {m} for Android", "org.chromium.chrome"), ("webview", f"Android WebView {m} (Chromium build)", "com.android.webview")):
        files = [a for a in v["apks"] if a["kind"] == kind]
        if not files:
            continue
        apps.append({
            "@type": "SoftwareApplication",
            "name": label,
            "softwareVersion": v["version"],
            "operatingSystem": "Android",
            "applicationCategory": "DeveloperApplication",
            "identifier": package,
            "downloadUrl": [a["url"] for a in files],
            "fileSize": mb(files[0]["size"]).replace(" ", ""),
            "datePublished": v["published"][:10],
            "image": files[0]["icon"],
            "url": url,
            "isAccessibleForFree": True,
            "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        })
    ld = {"@context": "https://schema.org", "@graph": apps + [{
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Chromium Builds", "item": base},
            {"@type": "ListItem", "position": 2, "name": f"Chromium {m}", "item": url},
        ],
    }]}

    files = []
    for arch in ("x86_64", "arm64"):
        for kind in ("chromium", "webview"):
            a = apk(v, kind, arch)
            if not a:
                continue
            files.append(
                f'<tr><td><div class="ver"><img src="{a["icon"] or ""}" alt="" width="26" height="26">'
                f'<a class="file" href="{a["url"]}"><span class="k">{kind}</span><small>{mb(a["size"])}</small></a></div></td>'
                f'<td class="dt">{"org.chromium.chrome" if kind == "chromium" else "com.android.webview"}</td>'
                f'<td class="dt">{ARCH[arch]}</td>'
                f'<td><button type="button" class="sha" data-text="{a["sha256"]}  {a["name"]}" title="{a["sha256"]}">sha256</button></td></tr>'
            )
    arch = "x86_64" if apk(v, "chromium", "x86_64") else "arm64"
    c, w = apk(v, "chromium", arch), apk(v, "webview", arch)
    install = []
    if c:
        install.append(f'<span class="pr">$ </span>adb install {c["name"]}')
    if w:
        install.append(f'<span class="pr">$ </span>adb install {w["name"]}')
        install.append('<span class="pr">$ </span>adb shell cmd webviewupdate \\\n    set-webview-implementation <span class="ts">com.android.webview</span>')
    others = "".join(
        f'<tr><td class="dt"><a href="{REPO}/releases/tag/{p["version"]}" target="_blank" rel="noopener">{p["version"]}</a></td><td>{pill(p)}</td><td class="dt">{released(p)}</td></tr>'
        for p in patches[1:]
    )
    prev, nxt = neighbours
    nav = " · ".join(
        x for x in (
            f'<a href="../{prev}/">← Chromium {prev}</a>' if prev else "",
            '<a href="../#versions">all versions</a>',
            f'<a href="../{nxt}/">Chromium {nxt} →</a>' if nxt else "",
        ) if x
    )
    return head(title, description, url, "../", ld) + header("../") + f"""
<main>
  <section class="block" style="border-top:0">
    <div class="wrap">
      <div class="block-head">
        <div class="label">MILESTONE {m}</div>
        <h1 style="font-size:clamp(2rem,4.5vw,3.2rem);font-weight:700">Chromium {m} and Android WebView {m} APKs</h1>
        <p>Version <span class="mono">{v['version']}</span>, released to Android {v['channel']} on {released(v)}. The browser installs as <span class="mono">org.chromium.chrome</span>, next to Google Chrome; the WebView provider as <span class="mono">com.android.webview</span>. Built from Chromium's <a href="{v['source']}" target="_blank" rel="noopener">{v['version']}</a> tag with proprietary codecs, without patches.</p>
      </div>
      <div class="table-wrap">
        <table>
          <thead><tr><th>File</th><th>Package</th><th>Architecture</th><th>Checksum</th></tr></thead>
          <tbody>{''.join(files)}</tbody>
        </table>
      </div>
      <p class="dt" style="margin-top:14px">{nav}</p>
    </div>
  </section>
  <section class="block" id="install">
    <div class="wrap">
      <div class="block-head">
        <div class="label">INSTALL</div>
        <h2>Install Chromium {m} on an emulator or a phone</h2>
        <p>The WebView installs on AOSP emulator images, redroid and rooted devices. Google APIs and Google Play images accept only Google's signed WebView.</p>
      </div>
      <div class="code" id="i1"><div class="code-bar"><span>SHELL · {arch.upper()}</span><button class="copy" type="button" data-copy="i1">copy</button></div><pre>{chr(10).join(install)}</pre></div>
    </div>
  </section>
  {f'''<section class="block">
    <div class="wrap">
      <div class="block-head"><div class="label">PATCHES</div><h2>Other builds of Chromium {m}</h2></div>
      <div class="table-wrap"><table><thead><tr><th>Version</th><th>Channel</th><th>Released</th></tr></thead><tbody>{others}</tbody></table></div>
    </div>
  </section>''' if others else ''}
  <section class="block">
    <div class="wrap">
      <div class="block-head">
        <div class="label">FILES</div>
        <h2>Machine-readable</h2>
        <p>This version as JSON: <a href="{REPO}/releases/download/{v['version']}/release.json">release.json</a>. Every version: <a href="https://raw.githubusercontent.com/holtdroid/chromium-builds/main/releases.json">releases.json</a>. The GitHub release: <a href="{v['release']}">{v['version']}</a>.</p>
      </div>
    </div>
  </section>
</main>
{FOOTER}
{COPY_JS}
</body>
</html>
"""


def main():
    releases, out = Path(sys.argv[1]), Path(sys.argv[2])
    base = sys.argv[3] if len(sys.argv) > 3 else "https://holtdroid.github.io/chromium-builds/"
    root = Path(__file__).resolve().parent.parent / "site"
    versions = [v for v in json.loads(releases.read_text())["versions"] if v["apks"]]
    latest = next((v for v in versions if v["latest"]), versions[0])
    milestones = sorted({v["milestone"] for v in versions})

    out.mkdir(parents=True, exist_ok=True)
    for old in out.iterdir():
        if old.name in (".git",):
            continue
        shutil.rmtree(old) if old.is_dir() else old.unlink()
    (out / ".nojekyll").write_text("")
    shutil.copy(root / "style.css", out / "style.css")

    data, icons = compact(versions)
    description = (
        f"Download any Chromium browser and Android WebView APK from milestone {milestones[0]} (Android 11) "
        f"to {milestones[-1]}, Stable and Beta, for x86_64 emulators and arm64 phones. Unofficial builds from Chromium's release tags."
    )
    ld = {"@context": "https://schema.org", "@type": "WebSite", "name": "Chromium Builds", "url": base, "description": description}
    page = (root / "index.html").read_text()
    page = page.replace("__HEAD__", head(f"Chromium & Android WebView APKs, every version {milestones[0]}–{milestones[-1]} · Chromium Builds", description, base, "", ld), 1)
    page = page.replace("__ROWS__", index_rows(versions), 1)
    page = page.replace("__DATA__", json.dumps(data, separators=(",", ":")), 1)
    page = page.replace("__FIRST__", json.dumps(first_stable(), separators=(",", ":")), 1)
    page = page.replace("__ICONS__", json.dumps(icons, separators=(",", ":")), 1)
    (out / "index.html").write_text(page + "\n</body>\n</html>\n")

    urls = [(base, latest["published"][:10])]
    for i, m in enumerate(milestones):
        patches = [v for v in versions if v["milestone"] == m]
        patches.sort(key=lambda v: (v["channel"] != "Stable", [-int(x) for x in v["version"].split(".")]))
        prev = milestones[i - 1] if i > 0 else None
        nxt = milestones[i + 1] if i + 1 < len(milestones) else None
        (out / str(m)).mkdir()
        (out / str(m) / "index.html").write_text(milestone_page(m, patches, base, (prev, nxt)))
        urls.append((f"{base}{m}/", max(p["published"][:10] for p in patches)))

    (out / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"  <url><loc>{u}</loc><lastmod>{d}</lastmod></url>\n" for u, d in urls)
        + "</urlset>\n"
    )
    (out / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {base}sitemap.xml\n")
    print(f"{len(milestones)} milestone pages, {len(urls)} sitemap entries")


if __name__ == "__main__":
    main()
