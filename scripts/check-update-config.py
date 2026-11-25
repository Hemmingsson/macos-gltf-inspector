#!/usr/bin/env python3
"""Check a built app against the public update configuration in project.yml."""
import base64
import pathlib
import plistlib
import re
import sys


def check(app, project):
    text = project.read_text()
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    for source, target in [('SUPublicEDKey', 'SUPublicEDKey'),
                           ('SUFeedURL', 'SUFeedURL'),
                           ('CURRENT_PROJECT_VERSION', 'CFBundleVersion'),
                           ('MARKETING_VERSION', 'CFBundleShortVersionString')]:
        match = re.search(r'^\s*' + source + r':\s*([^\n]+)', text, re.M)
        if not match:
            raise ValueError(f'missing {source} in project.yml')
        expected = match[1].strip().strip('"\'')
        if info.get(target) != expected:
            raise ValueError(f'{target} mismatch: built {info.get(target)!r}, project {expected!r}')
    key = base64.b64decode(info['SUPublicEDKey'], validate=True)
    if len(key) != 32 or key == bytes(32):
        raise ValueError('invalid or placeholder Sparkle public key')
    if not info['SUFeedURL'].startswith('https://'):
        raise ValueError('update feed must use HTTPS')


if __name__ == '__main__':
    try:
        check(pathlib.Path(sys.argv[1]), pathlib.Path(__file__).resolve().parent.parent / 'project.yml')
    except (ValueError, OSError) as error:
        sys.exit(f'update configuration: {error}')
    print('update configuration: built key, feed and versions match project.yml')
