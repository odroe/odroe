"""Keep release source S distinct from harness H and reject identity drift."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from release_verify import check_checkout, load_frozen_manifest, verify_source_files


class ReleaseRevisionTest(unittest.TestCase):
    def git(self, directory, *args):
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')
        return subprocess.check_output(['git', *args], cwd=directory, env=env,
                                       stderr=subprocess.STDOUT, text=True).strip()

    def checkout(self, base, name, content):
        directory = base / name
        directory.mkdir()
        self.git(directory, 'init', '-q')
        self.git(directory, 'config', 'user.email', 'acceptance-test@example.invalid')
        self.git(directory, 'config', 'user.name', 'Acceptance test')
        (directory / 'source.dart').write_text(content)
        self.git(directory, 'add', '.')
        self.git(directory, 'commit', '-qm', name)
        return directory, self.git(directory, 'rev-parse', 'HEAD')

    def test_source_and_harness_are_independently_pinned_and_clean(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source, s = self.checkout(base, 'release', 'published source\n')
            harness, h = self.checkout(base, 'harness', 'fixed harness\n')
            self.assertNotEqual(s, h)
            check_checkout(source, s, 'source')
            check_checkout(harness, h, 'harness')
            for directory, expected, label in [(source, h, 'source'), (harness, s, 'harness')]:
                with self.assertRaisesRegex(ValueError, 'exact reviewed'):
                    check_checkout(directory, expected, label)
            for directory, expected, label in [(source, s, 'source'), (harness, h, 'harness')]:
                (directory / 'untracked').write_text('dirty')
                with self.assertRaisesRegex(RuntimeError, 'clean ' + label):
                    check_checkout(directory, expected, label)
                (directory / 'untracked').unlink()
                (directory / 'source.dart').write_text('modified')
                with self.assertRaisesRegex(RuntimeError, 'clean ' + label):
                    check_checkout(directory, expected, label)
                self.git(directory, 'restore', 'source.dart')
            with self.assertRaisesRegex(ValueError, 'exact source commit SHA'):
                check_checkout(source, s[:7], 'source')
            (source / 'subdirectory').mkdir()
            with self.assertRaisesRegex(ValueError, 'checkout root'):
                check_checkout(source / 'subdirectory', s, 'source')

    def test_official_content_is_compared_to_s_not_h(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            payload = b'published source\n'
            source, s = self.checkout(base, 'release', payload.decode())
            harness, h = self.checkout(base, 'harness', 'changed content\n')
            files = {'source.dart': {'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}}
            verify_source_files(source, s, files)
            with self.assertRaisesRegex(ValueError, 'differs from the release source'):
                verify_source_files(harness, h, files)
            corrupted = {'source.dart': dict(files['source.dart'], sha256='0' * 64)}
            with self.assertRaisesRegex(ValueError, 'differs from the release source'):
                verify_source_files(source, s, corrupted)

    def test_consumer_fixtures_follow_explicit_source_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary).resolve()
            env = dict(os.environ, ODROE_SOURCE_ROOT=str(source), PYTHONDONTWRITEBYTECODE='1')
            root = subprocess.check_output(
                [os.sys.executable, '-c', 'from fullstack_consumer_smoke import root; print(root)'],
                cwd=Path(__file__).parent, env=env, text=True).strip()
            self.assertEqual(Path(root), source)

    def test_manifest_must_be_the_version_fixture_in_h(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            harness, _ = self.checkout(base, 'harness', 'fixed harness\n')
            fixture = harness / 'test/fixtures/releases/odroe-0.1.0-dev.3.json'
            fixture.parent.mkdir(parents=True)
            payload = b'{"version":"0.1.0-dev.3","files":{}}\n'
            fixture.write_bytes(payload)
            self.git(harness, 'add', '.')
            self.git(harness, 'commit', '-qm', 'reviewed fixture')
            h = self.git(harness, 'rev-parse', 'HEAD')
            manifest, checksum = load_frozen_manifest(harness, h, '0.1.0-dev.3')
            self.assertEqual(manifest, json.loads(payload))
            self.assertEqual(checksum, hashlib.sha256(payload).hexdigest())
            fixture.write_text('{"forged":true}')
            with self.assertRaisesRegex(ValueError, 'pinned harness fixture'):
                load_frozen_manifest(harness, h, '0.1.0-dev.3')
            fixture.unlink()
            external = base / 'external.json'
            external.write_bytes(payload)
            # No external-manifest CLI entrypoint remains. A missing fixed
            # fixture cannot be supplied by an unrelated external JSON.
            with self.assertRaises(FileNotFoundError):
                load_frozen_manifest(harness, h, '0.1.0-dev.3')


if __name__ == '__main__':
    unittest.main()
