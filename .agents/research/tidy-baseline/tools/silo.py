#!/usr/bin/env python3
"""Apply the AGENTS.md renderer removal rule to a worktree: silo.py <worktree> <RealityKit|WebKit>."""
import pathlib, re, shutil, sys

root = pathlib.Path(sys.argv[1])
which = sys.argv[2]
fw = f"Renderer{which}"

for rel in [fw, f"GLTFInspector/{which}", f"GLTFInspectorTests/{which}",
            f"PreviewExtension/QuickLook{which}.swift", f"ThumbnailExtension/Thumbnail{which}.swift"]:
    p = root / rel
    if p.is_dir():
        shutil.rmtree(p)
    elif p.exists():
        p.unlink()
    else:
        print("missing", rel)

yml = (root / "project.yml").read_text()
lines = yml.split("\n")
out = []
i = 0
while i < len(lines):
    line = lines[i]
    # the target block (plus its leading comment lines)
    if line == f"  {fw}:":
        while out and out[-1].startswith("  #"):
            out.pop()
        i += 1
        while i < len(lines) and (lines[i].startswith("    ") or lines[i] == ""):
            i += 1
        continue
    if line.strip() == f"- target: {fw}":
        i += 1
        if i < len(lines) and lines[i].strip().startswith("embed:"):
            i += 1
        continue
    if which == "RealityKit":
        if line in ("  GLTFKit2:", "  DracoSwift:"):
            i += 1
            while i < len(lines) and lines[i].startswith("    "):
                i += 1
            continue
        if line.strip() in ("- package: GLTFKit2", "- package: DracoSwift"):
            while out and out[-1].strip().startswith("#"):
                out.pop()
            i += 1
            continue
    out.append(line)
    i += 1
(root / "project.yml").write_text("\n".join(out))
print("siloed", which)
