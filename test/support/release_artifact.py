"""Shared package identity and extraction checks for release acceptance."""
from pathlib import Path, PurePosixPath
import hashlib
import re
import tarfile


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def package_version(package):
    text = (Path(package) / 'pubspec.yaml').read_text()
    match = re.search(r'^version:\s*(\S+)\s*$', text, re.M)
    if not match or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?', match[1]):
        raise ValueError('The package must declare one exact version.')
    return match[1]


def extract_package(archive, destination):
    """Extract regular pub files only, rejecting unsafe or ambiguous members."""
    destination = Path(destination)
    destination.mkdir(exist_ok=False)
    manifest = {}
    seen = set()
    total = 0
    with tarfile.open(archive, 'r:gz') as package:
        for member in package:
            name = PurePosixPath(member.name)
            if (name.is_absolute() or '..' in name.parts or '\\' in member.name
                    or ':' in member.name or member.name in ('', '.')
                    or not (member.isfile() or member.isdir())):
                raise ValueError(f'Unsafe package entry: {member.name}')
            normalized = str(name)
            if normalized in seen:
                raise ValueError(f'Duplicate package entry: {member.name}')
            seen.add(normalized)
            total += member.size
            if len(seen) > 5000 or total > 128 * 1024 * 1024:
                raise ValueError('Package exceeds release archive limits.')
            target = destination.joinpath(*name.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with package.extractfile(member) as source, target.open('xb') as output:
                while data := source.read(65536):
                    output.write(data)
            target.chmod(0o755 if member.mode & 0o111 else 0o644)
            manifest[normalized] = {'sha256': sha256(target), 'bytes': target.stat().st_size}
    for required in ['pubspec.yaml', 'bin/odroe.dart', 'lib/src/cli/version.dart']:
        if required not in manifest:
            raise ValueError(f'Package is missing {required}')
    version = package_version(destination)
    if f"const cliVersion = '{version}';" not in (destination / 'lib/src/cli/version.dart').read_text():
        raise ValueError('Packaged CLI and pubspec versions differ.')
    return dict(sorted(manifest.items()))


def verify_manifest(actual, expected):
    if actual != expected:
        changed = sorted(key for key in actual.keys() | expected.keys()
                         if actual.get(key) != expected.get(key))
        raise ValueError(f'Published package content differs: {changed}')
