#!/usr/bin/env python3
"""Fan one set of Markdown agents out to Cursor, Claude and Codex.

The Markdown file is the source of truth:

    ---
    name: n-visualizer
    description: …            # when to delegate (all harnesses)
    model: composer-2.5-fast  # Cursor / Claude slug, or inherit
    readonly: true            # Cursor; Codex gets it as an instruction line
    is_background: true       # Cursor
    codex_model: gpt-6.1-sol  # optional; Codex inherits the parent's model without it
    codex_effort: low         # optional; Codex model_reasoning_effort
    ---
    <instructions>

Cursor and Claude read the Markdown as-is, so they get symlinks (no copy, no drift).
Codex needs TOML (name, description, developer_instructions, model, model_reasoning_effort);
it can't sandbox one agent, so `readonly: true` becomes a first instruction line.

    python3 sync-agents.py --src DIR [--cursor DIR] [--claude DIR] [--codex DIR] [--dry-run]
"""
import argparse, json, os, sys
from pathlib import Path

def parse(path: Path):
    text = path.read_text()
    if not text.startswith("---\n"):
        raise ValueError(f"{path}: no frontmatter")
    head, body = text[4:].split("\n---\n", 1)
    meta = {}
    for line in head.splitlines():
        if ":" in line and not line.startswith((" ", "#")):
            k, v = line.split(":", 1)
            meta[k.strip()] = v.split(" #")[0].strip().strip('"')
    if "name" not in meta or "description" not in meta:
        raise ValueError(f"{path}: needs name and description")
    return meta, body.strip() + "\n"

def toml_str(s: str) -> str:
    return json.dumps(s, ensure_ascii=False)  # a JSON string is a valid TOML basic string

def codex_toml(src: Path, meta: dict, body: str) -> str:
    instructions = body
    if meta.get("readonly") == "true":
        instructions = "Read-only: do not edit files or change git state.\n\n" + instructions
    lines = [f"# Generated from {src} by sync-agents.py. Edit the .md, not this file.",
             f"name = {toml_str(meta['name'])}",
             f"description = {toml_str(meta['description'])}"]
    if meta.get("codex_model"):
        lines.append(f"model = {toml_str(meta['codex_model'])}")
    if meta.get("codex_effort"):
        lines.append(f"model_reasoning_effort = {toml_str(meta['codex_effort'])}")
    lines.append(f"developer_instructions = {toml_str(instructions)}")
    return "\n".join(lines) + "\n"

def link(src: Path, dest_dir: Path, dry: bool):
    dest = dest_dir / src.name
    target = os.path.relpath(src.resolve(), dest_dir.resolve())
    if dest.is_symlink() and os.readlink(dest) == target:
        return "same"
    if dest.exists() and not dest.is_symlink():
        return "skip (a real file is there; remove it by hand if it is a stale copy)"
    if not dry:
        if dest.is_symlink():
            dest.unlink()
        dest.symlink_to(target)
    return "linked"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, type=Path)
    ap.add_argument("--cursor", type=Path)
    ap.add_argument("--claude", type=Path)
    ap.add_argument("--codex", type=Path)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    for d in (a.cursor, a.claude, a.codex):
        if d and not a.dry_run:
            d.mkdir(parents=True, exist_ok=True)
    ok = True
    for md in sorted(a.src.glob("*.md")):
        try:
            meta, body = parse(md)
        except ValueError as e:
            print(f"error  {e}"); ok = False; continue
        for label, d in (("cursor", a.cursor), ("claude", a.claude)):
            if d:
                print(f"{label:6} {meta['name']}: {link(md, d, a.dry_run)}")
        if a.codex:
            out = a.codex / f"{meta['name']}.toml"
            new = codex_toml(md.resolve(), meta, body)
            state = "same" if out.exists() and out.read_text() == new else "written"
            if state == "written" and not a.dry_run:
                out.write_text(new)
            print(f"codex  {meta['name']}: {state}")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
