"""Exercise archive safety and complete released-file identity."""
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

from release_artifact import extract_package, verify_manifest


class ReleaseArchiveTest(unittest.TestCase):
    def archive(self, base, extra=()):
        archive = base / 'package.tar.gz'
        with tarfile.open(archive, 'w:gz') as output:
            files = {'pubspec.yaml': b'name: odroe\nversion: 0.1.0-dev.2\n',
                     'bin/odroe.dart': b'void main() {}\n',
                     'lib/src/cli/version.dart': b"const cliVersion = '0.1.0-dev.2';\n"}
            for name, content in files.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(content)
                output.addfile(entry, io.BytesIO(content))
            for entry, content in extra:
                output.addfile(entry, io.BytesIO(content))
        return archive

    def test_extracts_complete_file_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            result = extract_package(self.archive(base), base / 'unpacked')
            self.assertEqual(len(result), 3)
            self.assertEqual(result['bin/odroe.dart']['bytes'], 15)
            verify_manifest(result, json.loads(json.dumps(result)))
            changed = dict(result, **{'extra.dart': {'sha256': 'unknown', 'bytes': 0}})
            with self.assertRaisesRegex(ValueError, 'content differs'):
                verify_manifest(result, changed)

    def test_rejects_paths_links_duplicates_and_special_files(self):
        cases = []
        for name in ['../outside', '/absolute', 'lib/../../outside', 'C:/outside', 'lib\\outside']:
            cases.append(tarfile.TarInfo(name))
        for kind in [tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE]:
            entry = tarfile.TarInfo('escape')
            entry.type = kind
            entry.linkname = '../outside'
            cases.append(entry)
        cases.append(tarfile.TarInfo('./bin/odroe.dart'))
        for entry in cases:
            with self.subTest(name=entry.name, kind=entry.type), tempfile.TemporaryDirectory() as temp:
                base = Path(temp)
                archive = self.archive(base, [(entry, b'')])
                with self.assertRaises(ValueError):
                    extract_package(archive, base / 'unpacked')
                self.assertFalse((base / 'outside').exists())

    def test_rejects_mismatched_packaged_cli_version(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            archive = self.archive(base)
            destination = base / 'unpacked'
            extract_package(archive, destination)
            # Create a separate malformed artifact, not a changed expected manifest.
            with tarfile.open(base / 'bad.tar.gz', 'w:gz') as output:
                for file in destination.rglob('*'):
                    if file.is_file():
                        if file.name == 'version.dart':
                            file.write_text("const cliVersion = '0.0.8';\n")
                        output.add(file, arcname=file.relative_to(destination))
            with self.assertRaisesRegex(ValueError, 'versions differ'):
                extract_package(base / 'bad.tar.gz', base / 'bad')


if __name__ == '__main__':
    unittest.main()
