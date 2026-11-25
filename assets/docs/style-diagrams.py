#!/usr/bin/env python3
"""Add adaptive light/dark colors to SeeCode SVGs and make static preview copies."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


NAMES = ("quicklook-troubleshooting", "dev-loop", "reference-tests", "release")
LIGHT = {
    "paper": "#ffffff",
    "paper-2": "#f3f3f3",
    "ink": "#050505",
    "ink-strong": "#030303",
    "muted": "#626262",
    "soft": "#878787",
    "rule": "rgba(5,5,5,0.12)",
    "rule-solid": "#bebebe",
    "accent": "#050505",
    "accent-tint": "rgba(5,5,5,0.1)",
    "link": "#050505",
    "node": "#ffffff",
    "store": "rgba(5,5,5,0.05)",
    "external": "rgba(5,5,5,0.025)",
}
DARK = {
    "paper": "#17191d",
    "paper-2": "#22252b",
    "ink": "#eeeeef",
    "ink-strong": "#ffffff",
    "muted": "#b6bac3",
    "soft": "#8c929e",
    "rule": "#3d434e",
    "rule-solid": "#626a79",
    "accent": "#eeeeef",
    "accent-tint": "#30343c",
    "link": "#eeeeef",
    "node": "#22252b",
    "store": "#22252b",
    "external": "#1d2025",
}


def declarations(values: dict[str, str]) -> str:
    return "".join(f"--sc-{key}:{value};" for key, value in values.items())


def style_svg(svg: str) -> str:
    match = re.search(r'<svg\b[^>]*\sid="([^"]+)"', svg)
    if not match:
        raise ValueError("SVG has no root id")
    root = match.group(1)
    svg = re.sub(r'<style id="gltf-inspector-theme">.*?</style>', "", svg, flags=re.S)
    theme = (
        f'<style id="gltf-inspector-theme">svg#{root}'
        f'{{{declarations(LIGHT)}color-scheme:light dark}}'
        f'@media (prefers-color-scheme:dark){{svg#{root}'
        f'{{{declarations(DARK)}}}}}</style>'
    )
    return svg.replace("</svg>", theme + "</svg>")


def static_svg(svg: str, values: dict[str, str]) -> str:
    svg = re.sub(r"@media \(prefers-color-scheme:dark\)\{.*?\}", "", svg)
    variables = declarations(values)
    for key, value in values.items():
        svg = re.sub(rf"var\(--sc-{re.escape(key)}\)", value, svg)
    svg = re.sub(r"--sc-[\w-]+:[^;]+;", "", svg)
    return svg.replace("</style>", variables + "</style>", 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--static-dir", type=Path)
    parser.add_argument("--dark", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).parent
    for name in NAMES:
        path = root / f"{name}.svg"
        svg = path.read_text()
        if args.static_dir:
            args.static_dir.mkdir(parents=True, exist_ok=True)
            values = DARK if args.dark else LIGHT
            (args.static_dir / path.name).write_text(static_svg(svg, values))
        else:
            path.write_text(style_svg(svg))


if __name__ == "__main__":
    main()
