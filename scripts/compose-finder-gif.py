#!/usr/bin/env python3
"""Overlay turntable PNG frames onto the Finder preview pane in base-image.png."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np


def load_rgb(path: Path) -> tuple[np.ndarray, int, int]:
    probe = subprocess.check_output(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path)],
        text=True,
    ).strip().split("\n")[0]
    w, h = (int(x) for x in probe.split(",")[:2])
    raw = Path("/tmp") / f"{path.stem}-{w}x{h}.rgb"
    subprocess.check_call(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-i", str(path), "-frames:v", "1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", str(raw)]
    )
    img = np.fromfile(raw, dtype=np.uint8)[: w * h * 3].reshape(h, w, 3)
    return img, w, h


def preview_rect_dark(img: np.ndarray) -> tuple[int, int, int, int]:
    h, w, _ = img.shape
    luma = img.mean(axis=2)
    chroma = img.max(axis=2) - img.min(axis=2)
    mask = (luma > 30) & (luma < 72) & (chroma < 14)
    mask[:, : w // 2] = False
    mask[:80, :] = False
    return _rect_from_mask(mask, luma, expand_dark=True)


def preview_rect_white(img: np.ndarray) -> tuple[int, int, int, int]:
    """Straight inner viewport. Leaves the window's rounded corners to the still."""
    h, w, _ = img.shape
    luma = img.mean(axis=2)
    chroma = img.max(axis=2) - img.min(axis=2)
    mask = (luma > 240) & (chroma < 18)
    mask[:80, :] = False
    row_w = mask.sum(axis=1)
    good = np.where(row_w > w * 0.6)[0]
    if good.size == 0:
        raise SystemExit("could not find white preview pane in base image")
    lefts = np.array([np.where(mask[y])[0].min() for y in good])
    rights = np.array([np.where(mask[y])[0].max() for y in good])
    x = int(np.median(lefts))
    r = int(np.median(rights))
    aligned = (np.abs(lefts - x) <= 1) & (np.abs(rights - r) <= 1)
    ys = good[aligned]
    if ys.size == 0:
        ys = good
    y0, y1 = int(ys[0]), int(ys[-1])
    return x, y0, r - x + 1, y1 - y0 + 1


def content_bbox(frames: list[Path], threshold: float = 240, margin: float = 0.05) -> tuple[int, int, int, int]:
    """Union of non-white pixels across a few turntable frames, plus margin."""
    sample = []
    n = len(frames)
    for i in (0, n // 4, n // 2, (3 * n) // 4, n - 1):
        if 0 <= i < n and frames[i] not in sample:
            sample.append(frames[i])
    minx = miny = 10**9
    maxx = maxy = 0
    fw = fh = 0
    for path in sample:
        img, fw, fh = load_rgb(path)
        ys, xs = np.where(img.mean(axis=2) < threshold)
        if xs.size == 0:
            continue
        minx = min(minx, int(xs.min()))
        maxx = max(maxx, int(xs.max()))
        miny = min(miny, int(ys.min()))
        maxy = max(maxy, int(ys.max()))
    if maxx <= minx:
        return 0, 0, fw, fh
    pad = int(round(max(maxx - minx + 1, maxy - miny + 1) * margin))
    x = max(0, minx - pad)
    y = max(0, miny - pad)
    r = min(fw, maxx + 1 + pad)
    b = min(fh, maxy + 1 + pad)
    return x, y, r - x, b - y


def _rect_from_mask(mask: np.ndarray, luma: np.ndarray, expand_dark: bool) -> tuple[int, int, int, int]:
    h, w = mask.shape
    row_w = mask.sum(axis=1)
    good = np.where(row_w > w * 0.25)[0]
    if good.size == 0:
        raise SystemExit("could not find preview pane in base image")
    lefts = np.array([np.where(mask[y])[0].min() for y in good])
    rights = np.array([np.where(mask[y])[0].max() for y in good])
    x = int(np.median(lefts))
    r = int(np.median(rights))
    aligned = np.abs(lefts - x) <= 3
    y0 = int(good[aligned][0])
    y1 = int(good[aligned][-1])
    if expand_dark:
        mid = (y0 + y1) // 2
        while x > 0 and luma[mid, x - 1] < 80:
            x -= 1
        while r < w - 1 and luma[mid, r + 1] < 80:
            r += 1
        cx = (x + r) // 2
        while y0 > 0 and luma[y0 - 1, cx] < 80:
            y0 -= 1
        while y1 < h - 1 and luma[y1 + 1, cx] < 80:
            y1 += 1
    return x, y0, min(w - x, r - x + 2), min(h - y0, y1 - y0 + 2)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--base", type=Path, required=True)
    p.add_argument("--frames", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--fps", type=int, default=16)
    p.add_argument("--pane", choices=("dark", "white"), default="dark")
    p.add_argument("--scale-width", type=int, default=0)
    p.add_argument("--fit", type=float, default=1.0, help="scale overlay relative to the pane")
    p.add_argument("--content-crop", action="store_true", help="crop to the model then scale up to fill the pane")
    args = p.parse_args()
    frames = sorted(args.frames.glob("frame-*.png"))
    if not frames:
        sys.exit(f"no frame-*.png in {args.frames}")
    img, bw, bh = load_rgb(args.base)
    x, y, rw, rh = (preview_rect_white if args.pane == "white" else preview_rect_dark)(img)
    pattern = args.frames / "frame-%03d.png"
    if args.scale_width:
        after = f"[v]scale={args.scale_width}:-1:flags=lanczos,split[a][b];"
    else:
        after = "[v]split[a][b];"
    _, fw, fh = load_rgb(frames[0])
    crop_x, crop_y, crop_w, crop_h = 0, 0, fw, fh
    if args.content_crop:
        crop_x, crop_y, crop_w, crop_h = content_bbox(frames)
    fit = args.fit
    scale = min(rw / crop_w, rh / crop_h) * fit
    ow = max(1, int(round(crop_w * scale)))
    oh = max(1, int(round(crop_h * scale)))
    ox = x + (rw - ow) // 2
    oy = y + (rh - oh) // 2
    oy = max(y, min(y + rh - oh, oy))
    ox = max(x, min(x + rw - ow, ox))
    zoomed = args.content_crop or fit < 0.999
    scale_flags = "lanczos" if zoomed else "neighbor"
    if zoomed:
        cover = f"[0:v]drawbox={x}:{y}:{rw}:{rh}:white:t=fill[bg];"
        base_label = "[bg]"
    else:
        cover = ""
        base_label = "[0:v]"
    pre = ""
    if crop_w != fw or crop_h != fh or crop_x or crop_y:
        pre = f"crop={crop_w}:{crop_h}:{crop_x}:{crop_y},"
    chain = (
        f"{cover}"
        f"[1:v]{pre}scale={ow}:{oh}:flags={scale_flags}[g];"
        f"{base_label}[g]overlay={ox}:{oy}:shortest=1[v];"
        f"{after}"
        f"[a]palettegen=max_colors=256:stats_mode=full[p];"
        f"[b][p]paletteuse=dither=none"
    )
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-framerate", str(args.fps), "-loop", "1", "-i", str(args.base),
        "-framerate", str(args.fps), "-i", str(pattern),
        "-filter_complex", chain,
        "-r", str(args.fps),
        "-frames:v", str(len(frames)),
        "-loop", "0",
        str(args.out),
    ]
    subprocess.check_call(cmd)
    print(f"ok {args.out} overlay={ow}x{oh}+{ox}+{oy} pane={rw}x{rh}+{x}+{y}")


if __name__ == "__main__":
    main()
