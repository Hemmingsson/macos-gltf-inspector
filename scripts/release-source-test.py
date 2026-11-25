#!/usr/bin/env python3
"""Offline release source guards using disposable Git repositories; never sign or publish."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'source'
        self.repo.mkdir()
        self.remote = self.base / 'remote.git'
        subprocess.run(['git', 'init', '--bare', str(self.remote)], check=True, capture_output=True)
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Release Test')
        self.git('config', 'user.email', 'release-test@example.invalid')
        scripts = self.repo / 'scripts'
        scripts.mkdir()
        shutil.copyfile(ROOT / 'scripts/release.sh', scripts / 'release.sh')
        (scripts / 'sparkle-lib.sh').write_text('''GH_REPO=example/test
FEED_URL=https://example.invalid/appcast.xml
parse_project_versions() {
  MARKETING=1.0 BUILD=4 TAG=v1.0
  ZIP="$ROOT/dist/glTFInspector-1.0.zip"
  NOTES="$ROOT/dist/glTFInspector-1.0.md"
}
require_newer_build() { return 0; }
require_newer_published_build() { return 0; }
uses_placeholder_ed_key() { return 1; }
''')
        self.write_executable(scripts / 'archive.sh', '''#!/bin/bash
set -eu
touch "$ROOT/archive-ran"
printf archive > "$ROOT/dist/glTFInspector-1.0.zip"
'''.replace('$ROOT', str(self.repo)))
        self.write_executable(scripts / 'appcast.sh', '#!/bin/bash\nprintf feed > "' + str(self.repo / 'dist/appcast.xml') + '"\n')
        (self.repo / '.gitignore').write_text('dist/\narchive-ran\n')
        (self.repo / 'source.swift').write_text('// source\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Fixture')
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '-u', 'origin', 'main')
        (self.repo / 'dist').mkdir()
        (self.repo / 'dist/glTFInspector-1.0.md').write_text('Release notes\n')
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.log = self.base / 'gh.jsonl'
        self.write_executable(self.bin / 'gh', '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['GH_TEST_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1:3] == ['release', 'view']:
    sys.exit(1)
''')

    @staticmethod
    def write_executable(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout.strip()

    def release(self):
        return subprocess.run(['bash', 'scripts/release.sh'], cwd=self.repo,
                              env=dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                                       GH_TEST_LOG=str(self.log)), capture_output=True, text=True)

    def assert_blocked(self, message):
        result = self.release()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)
        self.assertFalse((self.repo / 'archive-ran').exists(), 'must reject before archive/signing')
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))

    def test_dirty_tracked_source(self):
        (self.repo / 'source.swift').write_text('// changed\n')
        self.assert_blocked('clean working tree')

    def test_untracked_source(self):
        (self.repo / 'extra.swift').write_text('// new\n')
        self.assert_blocked('clean working tree')

    def test_unpushed_head(self):
        self.git('commit', '--allow-empty', '-m', 'Unpushed')
        self.assert_blocked('must be pushed')

    def test_existing_local_tag(self):
        self.git('tag', 'v1.0')
        self.assert_blocked('already exists')

    def test_existing_remote_tag(self):
        self.git('tag', 'v1.0')
        self.git('push', 'origin', 'v1.0')
        self.git('tag', '-d', 'v1.0')
        self.assert_blocked('already exists')

    def test_missing_notes(self):
        (self.repo / 'dist/glTFInspector-1.0.md').unlink()
        self.assert_blocked('missing release notes')

    def test_empty_notes(self):
        (self.repo / 'dist/glTFInspector-1.0.md').write_text('')
        self.assert_blocked('missing release notes')

    def test_source_changed_during_archive_prevents_publication(self):
        archive = self.repo / 'scripts/archive.sh'
        archive.write_text(archive.read_text() + 'printf changed >> "' + str(self.repo / 'source.swift') + '"\n')
        self.git('add', 'scripts/archive.sh')
        self.git('commit', '-m', 'Archive fixture changes source')
        self.git('push', 'origin', 'main')
        result = self.release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('source changed during release', result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))

    def test_clean_release_targets_exact_pushed_commit(self):
        expected = self.git('rev-parse', 'HEAD')
        result = self.release()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        create, = [call for call in calls if call[:2] == ['release', 'create']]
        self.assertEqual(create[create.index('--target') + 1], expected)
        self.assertIn('--notes-file', create)
        self.assertTrue((self.repo / 'archive-ran').exists())


if __name__ == '__main__':
    unittest.main()
