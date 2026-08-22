#!/usr/bin/env python3
"""Rewrite Sparkle appcast enclosure URLs for GitHub release assets."""

from __future__ import annotations

import argparse
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote, unquote, urlparse


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE_SHORT_VERSION = f"{{{SPARKLE_NS}}}shortVersionString"
SPARKLE_RELEASE_NOTES_LINK = f"{{{SPARKLE_NS}}}releaseNotesLink"
GITHUB_REPO = os.environ.get("GH_REPO", "Hemmingsson/macos-gltf-inspector")
GITHUB_RELEASE_BASE = f"https://github.com/{GITHUB_REPO}/releases/download"


def enclosure_filename(url: str) -> str:
    parsed = urlparse(url)
    path = parsed.path or url
    filename = Path(unquote(path)).name
    if not filename:
        raise ValueError(f"enclosure URL has no filename: {url}")
    return filename


def github_asset_url(short_version: str, url: str) -> str:
    filename = quote(enclosure_filename(url), safe="")
    return f"{GITHUB_RELEASE_BASE}/v{short_version}/{filename}"


def rewrite_release_notes_links(item: ET.Element, short_version: str) -> None:
    attribute = (item.attrib.get(SPARKLE_RELEASE_NOTES_LINK) or "").strip()
    if attribute:
        item.set(SPARKLE_RELEASE_NOTES_LINK, github_asset_url(short_version, attribute))

    for child in item.findall(SPARKLE_RELEASE_NOTES_LINK):
        text = (child.text or "").strip()
        if not text:
            raise ValueError(
                f"appcast item {short_version} has an empty sparkle:releaseNotesLink"
            )
        child.text = github_asset_url(short_version, text)


def item_short_version(item: ET.Element) -> str:
    attribute = (item.attrib.get(SPARKLE_SHORT_VERSION) or "").strip()
    if attribute:
        return attribute

    child = item.find(SPARKLE_SHORT_VERSION)
    if child is not None and child.text and child.text.strip():
        return child.text.strip()

    raise ValueError("appcast item is missing sparkle:shortVersionString")


def rewrite_appcast(path: Path) -> None:
    ET.register_namespace("sparkle", SPARKLE_NS)
    tree = ET.parse(path)
    root = tree.getroot()

    items = root.findall(".//item")
    if not items:
        raise ValueError("appcast contains no <item> entries")

    for item in items:
        short_version = item_short_version(item)

        enclosures = item.findall("enclosure")
        if not enclosures:
            raise ValueError(
                f"appcast item {short_version} is missing an <enclosure>"
            )

        for enclosure in enclosures:
            url = enclosure.attrib.get("url")
            if not url:
                raise ValueError(
                    f"appcast item {short_version} has an enclosure without a url"
                )

            enclosure.set("url", github_asset_url(short_version, url))

        rewrite_release_notes_links(item, short_version)

    tree.write(path, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Rewrite Sparkle appcast enclosure URLs for GitHub releases."
    )
    parser.add_argument("appcast", type=Path, help="Path to appcast XML to rewrite")
    args = parser.parse_args()

    try:
        rewrite_appcast(args.appcast)
    except (ET.ParseError, OSError, ValueError) as error:
        print(f"rewrite-appcast-urls: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
