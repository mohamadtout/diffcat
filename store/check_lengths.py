#!/usr/bin/env python3
"""Checks the store listing text against each store's character limits.

Run from the repo root: python3 store/check_lengths.py
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent

# (file, heading that precedes the ``` block, limit)
BLOCKS = [
    ("app-store.md", "## Promotional text (170)", 170),
    ("app-store.md", "## Description (4000)", 4000),
    ("app-store.md", "## Keywords (100, comma separated, no spaces)", 100),
    ("app-store.md", "## What's New (first version)", 4000),
    ("google-play.md", "## Short description (80)", 80),
    ("google-play.md", "## Full description (4000)", 4000),
]

# (file, table field label, limit): the value is the first `code` span in the row.
FIELDS = [
    ("app-store.md", "Name (30)", 30),
    ("app-store.md", "Subtitle (30)", 30),
    ("google-play.md", "App name (30)", 30),
]


def block_after(text: str, heading: str) -> str:
    start = text.index(heading)
    m = re.search(r"```\n(.*?)\n```", text[start:], re.S)
    return m.group(1)


def main() -> int:
    ok = True
    for name, heading, limit in BLOCKS:
        value = block_after((HERE / name).read_text(), heading)
        n = len(value)
        flag = "OK " if n <= limit else "TOO LONG"
        ok &= n <= limit
        print(f"{flag} {n:5}/{limit:<5} {name}: {heading.lstrip('# ')}")
    for name, label, limit in FIELDS:
        row = next(line for line in (HERE / name).read_text().splitlines() if line.startswith(f"| {label} |"))
        value = re.search(r"`([^`]*)`", row).group(1)
        n = len(value)
        flag = "OK " if n <= limit else "TOO LONG"
        ok &= n <= limit
        print(f"{flag} {n:5}/{limit:<5} {name}: {label} = {value!r}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
