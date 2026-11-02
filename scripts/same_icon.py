"""Usage: same_icon.py <icon> <dir>

Prints the name of an icon in <dir> that looks the same as <icon>: same size
and almost the same pixels. Builds re-encode the lossy WebP icons, so equal
icons rarely have equal bytes.
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def pixels(path):
    return Image.open(path).convert("RGBA")


icon = pixels(sys.argv[1])
for other in sorted(Path(sys.argv[2]).glob("*.*")):
    if other.suffix not in (".png", ".webp"):
        continue
    candidate = pixels(other)
    if candidate.size != icon.size:
        continue
    if max(ImageStat.Stat(ImageChops.difference(icon, candidate)).mean) < 2:
        print(other.name)
        break
