#!/usr/bin/env python3
"""Capture native Finder windows into staged transparent PNG/animated WebP mockups."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('kind', choices=['thumbnails', 'quick-look', 'preview-pane'])
parser.add_argument('--finder', type=int, help='Finder window ID (not a PID)')
parser.add_argument('--quick-look', type=int, help='Quick Look window ID')
parser.add_argument('--seconds', type=float, default=6)
parser.add_argument('--fps', type=float, default=15)
parser.add_argument('--frames-dir', type=Path, help='Re-export existing composed PNG frames without desktop capture')
parser.add_argument('--output', type=Path, help='New staging directory; must not already exist')
args = parser.parse_args()
if args.seconds <= 0 or not 0 < args.fps <= 60:
    parser.error('seconds must be positive; fps must be between 0 and 60')
if not args.frames_dir and (not args.finder or (args.kind == 'quick-look' and not args.quick_look)):
    parser.error('capture needs --finder and, for quick-look, --quick-look')
out = args.output or ROOT / '.build/mockups' / (args.kind + '-' + time.strftime('%Y%m%d-%H%M%S'))
out.mkdir(parents=True, exist_ok=False)
run = lambda *a: subprocess.run([str(v) for v in a], check=True)
animated = args.kind != 'thumbnails'
if animated and not shutil.which('img2webp'):
    parser.error('img2webp is required: brew install webp')
frames = []
durations = []
if args.frames_dir:
    frames = sorted(args.frames_dir.glob('*.png'))
    if not frames:
        parser.error('frames directory has no PNGs')
    durations = [round(1000 / args.fps)] * len(frames)
else:
    composer = out / 'compose-mockup'
    run('swiftc', ROOT / 'tools/readme/compose-mockup.swift', '-o', composer)
    source = out / 'sources'
    source.mkdir()
    frame_dir = out / 'frames'
    frame_dir.mkdir()
    start = time.monotonic()
    previous = None
    while not frames or (animated and time.monotonic() - start < args.seconds):
        if previous is not None:
            time.sleep(max(0, 1 / args.fps - (time.monotonic() - previous)))
        now = time.monotonic()
        if previous is not None:
            durations.append(max(1, round((now - previous) * 1000)))
        previous = now
        # Finder is a still backing window in the overlapping Quick Look composition.
        if args.kind != 'quick-look' or not frames:
            run('screencapture', '-x', '-l', args.finder, source / 'finder.png')
        if args.kind == 'quick-look':
            run('screencapture', '-x', '-l', args.quick_look, source / 'quick-look.png')
        frame = frame_dir / f'{len(frames):04d}.png'
        run(composer, ROOT / 'tools/readme/mockup-layouts.json', args.kind, source, frame)
        frames.append(frame)
    durations.append(max(1, round((time.monotonic() - previous) * 1000)))
name = {'thumbnails': 'finder-thumbnails', 'quick-look': 'quick-look', 'preview-pane': 'preview-pane'}[args.kind]
if animated:
    command = ['img2webp', '-loop', '0']
    for frame, duration in zip(frames, durations):
        command += ['-d', str(duration), '-lossless', str(frame)]
    run(*command, '-o', out / (name + '.webp'))
else:
    shutil.copyfile(frames[0], out / (name + '.png'))
(out / 'capture.json').write_text(json.dumps({
    'kind': args.kind, 'finder': args.finder, 'quickLook': args.quick_look,
    'frameCount': len(frames), 'durationMs': sum(durations),
    'layout': json.loads((ROOT / 'tools/readme/mockup-layouts.json').read_text())[args.kind],
}, indent=2) + '\n')
print(out)
