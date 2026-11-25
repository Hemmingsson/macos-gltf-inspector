#!/usr/bin/env python3
"""Offline regression tests; never access signing keys or publish."""
import importlib.util
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('config', ROOT / 'scripts/check-update-config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class ReadinessTests(unittest.TestCase):
    def shell(self, body):
        return subprocess.run(['bash', '-c', f'source "{ROOT}/scripts/sparkle-lib.sh"\n' + body], capture_output=True, text=True)

    def test_appcast_versions_and_malformed_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = pathlib.Path(directory) / 'appcast.xml'
            for content, expected in [
                ('<item><sparkle:version>4</sparkle:version></item>', 0),
                ('<item><enclosure sparkle:version="5"/></item>', 0),
                ('<item><sparkle:version>bad</sparkle:version></item>', 1),
                ('', 1),
            ]:
                feed.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' + content + '</channel></rss>')
                result = self.shell(f'last_appcast_build "{feed}"')
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_remote_guard(self):
        prefix = 'BUILD=4\ngh() { echo v1.0; }\n'
        for published, expected in [(3, 0), (4, 1), (5, 1)]:
            result = self.shell(prefix + f'curl() {{ echo \'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{published}</sparkle:version></item></channel></rss>\' > "${{@: -1}}"; }}\nrequire_newer_published_build')
            self.assertEqual(result.returncode, expected, result.stderr)
        for mock, expected in [('gh() { return 1; }', 1), ('gh() { :; }', 0), ('gh() { echo v1; }; curl() { return 22; }', 1)]:
            self.assertEqual(self.shell('BUILD=4\n' + mock + '\nrequire_newer_published_build').returncode, expected)

    def test_built_config_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'Contents').mkdir()
            project = root / 'project.yml'
            project.write_text('SUPublicEDKey: OQrffRwGjVoW1aFeEKHsEcYco5WgZo1qH7syaZmjoQ8=\nSUFeedURL: https://example.com/feed\nCURRENT_PROJECT_VERSION: "4"\nMARKETING_VERSION: "1.1"\n')
            info = dict(SUPublicEDKey='OQrffRwGjVoW1aFeEKHsEcYco5WgZo1qH7syaZmjoQ8=', SUFeedURL='https://example.com/feed', CFBundleVersion='4', CFBundleShortVersionString='1.1')
            (root / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            config.check(root, project)
            info['SUPublicEDKey'] = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
            (root / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            with self.assertRaises(ValueError):
                config.check(root, project)


if __name__ == '__main__':
    unittest.main()
