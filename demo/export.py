#!/usr/bin/env python3
"""Reproducible real-Metal + HyperFrames demo exports. Python standard library only."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / 'demo'
VIDEO = DEMO / 'video'
OUT = ROOT / 'docs' / 'media'
SHOTS = json.loads((DEMO / 'shots.json').read_text())

def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)

def frames():
    run('xcodegen', 'generate', cwd=ROOT)
    run('xcodebuild', '-scheme', 'ShotRenderer', '-configuration', 'Debug',
        '-destination', 'platform=macOS', '-derivedDataPath', ROOT / '.build/demo-dd', 'build', cwd=ROOT)
    binary = ROOT / '.build/demo-dd/Build/Products/Debug/shot-renderer'
    rendered = {}
    manifest = {}
    for shot, config in SHOTS.items():
        model = Path(os.path.expanduser(config['model']))
        if not model.is_absolute():
            model = ROOT / model
        if not model.is_file():
            raise SystemExit(f'Missing model: {model}. Fetch test models or edit demo/shots.json.')
        destination = VIDEO / 'assets' / shot
        key = (str(model), config.get('zoom', 0.48), config.get('view', 'shaded'))
        destination.mkdir(parents=True, exist_ok=True)
        if key in rendered:
            for frame in rendered[key].glob('*.png'):
                shutil.copyfile(frame, destination / frame.name)
        else:
            run(binary, '--model', model, '--out', destination, '--frames', '120',
                '--size', '960x720', '--zoom', str(key[1]), '--view', key[2])
            rendered[key] = destination
        manifest[shot] = {'name': model.name}
    (VIDEO / 'assets/manifest.json').write_text(json.dumps(manifest))

def video(shot, fps, resolution):
    OUT.mkdir(parents=True, exist_ok=True)
    source = (VIDEO / 'index.html').read_text()
    composition = 'index.html'
    generated = VIDEO / 'clip.generated.html'
    if shot != 'demo':
        source = source.replace('const ONLY_SHOT = null;', f'const ONLY_SHOT = "{shot}";')
        source = source.replace('data-duration="16"', 'data-duration="4"')
        generated.write_text(source)
        composition = generated.name
    try:
        run('npx', '--yes', 'hyperframes@0.8.77', 'render', VIDEO, '--composition', composition,
            '--fps', fps, '--resolution', resolution, '--output', OUT / f'{shot}.mp4')
        with tempfile.TemporaryDirectory(prefix='gltf-webp-') as temp:
            run('ffmpeg', '-y', '-loglevel', 'error', '-i', OUT / f'{shot}.mp4',
                '-vf', 'scale=1280:720:flags=lanczos', Path(temp) / '%04d.png')
            command = ['img2webp', '-loop', '0', '-lossy', '-q', '78', '-m', '4',
                       '-kmin', '20', '-kmax', '30']
            for i, frame in enumerate(sorted(Path(temp).glob('*.png'))):
                duration = round((i+1)*1000/fps) - round(i*1000/fps)
                command += ['-d', str(duration), str(frame)]
            run(*command, '-o', OUT / f'{shot}.webp')
    finally:
        generated.unlink(missing_ok=True)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('command', choices=['frames', 'demo', 'clips', 'all'])
parser.add_argument('--fps', type=int, default=30)
parser.add_argument('--resolution', default='1080p', choices=['720p', '1080p', '4k'])
args = parser.parse_args()
if args.command in ('frames', 'all'):
    frames()
if args.command in ('demo', 'all'):
    video('demo', args.fps, args.resolution)
if args.command in ('clips', 'all'):
    for shot in SHOTS:
        video(shot, args.fps, args.resolution)
