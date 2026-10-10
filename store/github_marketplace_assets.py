"""Renders the GitHub Marketplace logo and feature card into store/screenshots/github-marketplace/
and copies the five listing screenshots from the raw tablet shots.

Run from the repo root after `make store-screenshots NAME=android-tablet-10`:
    python3 store/github_marketplace_assets.py
Needs Google Chrome (headless) to turn the SVGs into PNGs.
"""

import random
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'store/screenshots/github-marketplace'
RAW = ROOT / 'app/build/store/raw/android-tablet-10'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
SHOTS = ['02_commit_split', '04_pull', '03_diff_full_width', '07_offline_mode', '09_terminal']


def logo_svg() -> str:
    """The icon's cat on a transparent background, with room for a round badge."""
    src = (ROOT / 'app/assets/icon/foreground.svg').read_text()
    return re.sub(r'<svg[^>]*>', '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" '
                  'viewBox="152 162 720 720">', src, count=1)


def card_svg(w: int = 965, h: int = 482) -> str:
    """The icon's purple gradient with faint diff lines (no text: GitHub draws the name on it)."""
    rnd = random.Random(7)
    rows, y = [], 26
    while y < h - 10:
        kind = rnd.choice(['ctx', 'ctx', 'ctx', 'add', 'del'])
        color = {'ctx': '#ffffff', 'add': '#3fb950', 'del': '#f85149'}[kind]
        if kind != 'ctx':
            rows.append(f'<rect x="0" y="{y - 7}" width="{w}" height="22" fill="{color}" opacity="0.06"/>')
            mark = '+' if kind == 'add' else '−'
            rows.append(f'<text x="14" y="{y + 9}" font-family="Menlo, monospace" font-size="16" '
                        f'fill="{color}" opacity="0.45">{mark}</text>')
        x = 40 + rnd.choice([0, 0, 24, 48])
        for _ in range(rnd.randint(2, 5)):
            seg = rnd.randint(30, 150)
            if x + seg > w - 30:
                break
            rows.append(f'<rect x="{x}" y="{y}" width="{seg}" height="8" rx="4" fill="{color}" '
                        f'opacity="{0.07 if kind == "ctx" else 0.20}"/>')
            x += seg + 14
        y += 24
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#8957e5"/><stop offset="0.55" stop-color="#4c2f9e"/><stop offset="1" stop-color="#1b1446"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.6">
    <stop offset="0" stop-color="#1b1446" stop-opacity="0.55"/><stop offset="1" stop-color="#1b1446" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect width="{w}" height="{h}" fill="url(#bg)"/>
{''.join(rows)}
<rect width="{w}" height="{h}" fill="url(#glow)"/>
</svg>'''


def render(svg: str, size: str, target: Path, transparent: bool) -> None:
    with tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False) as f:
        f.write(svg)
    args = [CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', f'--window-size={size}',
            f'--screenshot={target}', f'file://{f.name}']
    if transparent:
        args.insert(1, '--default-background-color=00000000')
    subprocess.run(args, check=True, capture_output=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    render(logo_svg(), '512,512', OUT / 'logo-512.png', transparent=True)
    render(card_svg(), '965,482', OUT / 'feature-card-965x482.png', transparent=False)
    for i, name in enumerate(SHOTS, 1):
        shutil.copy(RAW / f'{name}.png', OUT / f'screenshot-{i}-{name}.png')
    print(f'Wrote {OUT}')


if __name__ == '__main__':
    main()
