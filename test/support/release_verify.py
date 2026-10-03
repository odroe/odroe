"""Accept an exact official release using the published artifact's own CLI."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

from fullstack_consumer_smoke import flutter, run
from release_artifact import extract_package, package_version, sha256, verify_manifest


def check_checkout(path, expected, label):
    if not re.fullmatch(r'[0-9a-f]{40}', expected):
        raise ValueError(f'An exact {label} commit SHA is required.')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=path, text=True):
        raise RuntimeError(f'Published acceptance requires a clean {label} checkout.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=path, text=True).strip()
    if commit != expected:
        raise ValueError(f'Checkout must match the exact reviewed {label} commit.')
    top = subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], cwd=path, text=True).strip()
    if Path(top).resolve() != Path(path).resolve():
        raise ValueError(f'The {label} path must be the checkout root.')


def verify_source_files(source, commit, files):
    for name, identity in files.items():
        payload = subprocess.check_output(['git', 'show', commit + ':' + name], cwd=source)
        if len(payload) != identity['bytes'] or hashlib.sha256(payload).hexdigest() != identity['sha256']:
            raise ValueError(f'Official file differs from the release source: {name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--source-root', required=True, type=Path)
    parser.add_argument('--harness-commit', required=True)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--archive-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    harness = Path(__file__).resolve().parents[2]
    source = args.source_root.resolve()
    check_checkout(source, args.commit, 'source')
    check_checkout(harness, args.harness_commit, 'harness')
    if package_version(source) != args.version:
        raise ValueError('Requested and checked-out package versions differ.')
    if not re.fullmatch(r'[0-9a-f]{64}', args.archive_sha256):
        raise ValueError('An exact preflight archive SHA256 is required.')
    frozen = json.loads(args.manifest.read_text())
    if (frozen['package'] != 'odroe' or frozen['version'] != args.version
            or frozen['sourceCommit'] != args.commit
            or frozen['archiveSha256'] != args.archive_sha256
            or frozen['archiveConsumers'] != 'passed'):
        raise ValueError('Frozen preflight manifest differs from the release identity.')
    frozen_hash = sha256(args.manifest)
    sdk = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError('Choose an empty output directory.')
    url = 'https://pub.dev/api/packages/odroe/versions/' + args.version
    with urllib.request.urlopen(url, timeout=60) as response:
        metadata = json.load(response)
    expected_url = 'https://pub.dev/api/archives/odroe-' + args.version + '.tar.gz'
    if (metadata['version'] != args.version or metadata['archive_url'] != expected_url
            or metadata['archive_sha256'] != args.archive_sha256):
        raise ValueError('Official registry identity differs from the preflight artifact.')
    official = output / f'odroe-{args.version}.tar.gz'
    with urllib.request.urlopen(expected_url, timeout=60) as response:
        payload = response.read(16 * 1024 * 1024 + 1)
    if len(payload) > 16 * 1024 * 1024:
        raise ValueError('Official archive exceeds the release download limit.')
    official.write_bytes(payload)
    if sha256(official) != args.archive_sha256:
        raise ValueError('Official archive checksum does not match.')
    with tempfile.TemporaryDirectory(prefix='odroe-release-verify-') as temp:
        base = Path(temp)
        package = base / 'official-package'
        manifest = extract_package(official, package)
        verify_manifest(manifest, frozen['files'])
        verify_source_files(source, args.commit, manifest)
        env = dict(os.environ, ODROE_PACKAGE_ROOT=str(package),
                   ODROE_SOURCE_ROOT=str(source),
                   PUB_CACHE=str(base / 'cache'), PUB_HOSTED_URL='https://pub.dev')
        for key in ['ODROE_HOSTED_VERSION', 'ODROE_CREATE_VERSION',
                    'ODROE_CREATE_DEFAULT', 'ODROE_CREATE_AOT']:
            env.pop(key, None)
        run([flutter, 'pub', 'get'], package, env=env)
        for aot in ['0', '1']:
            cli_env = dict(env, ODROE_CREATE_DEFAULT='1', ODROE_CREATE_AOT=aot)
            run([sys.executable, str(harness / 'test/support/fullstack_consumer_smoke.py')],
                source, timeout=900, env=cli_env)
        for name in ['dependency_first_consumer_smoke', 'incremental_adoption_smoke',
                     'query_rpc_consumer_smoke', 'router_navigation_consumer_smoke']:
            run([sys.executable, str(harness / 'test/support' / (name + '.py'))],
                source, timeout=900, env=dict(env, ODROE_HOSTED_VERSION=args.version))
    check_checkout(source, args.commit, 'source')
    check_checkout(harness, args.harness_commit, 'harness')
    if sha256(args.manifest) != frozen_hash:
        raise RuntimeError('The frozen preflight manifest changed during acceptance.')
    result = {'package': 'odroe', 'version': args.version, 'sourceCommit': args.commit,
              'harnessCommit': args.harness_commit, 'preflightManifestSha256': frozen_hash, 'sdk': sdk,
              'archiveSha256': args.archive_sha256, 'files': manifest,
              'registry': 'https://pub.dev', 'interpretedPublishedCli': 'passed',
              'aotPublishedCli': 'passed', 'freshHostedConsumers': 'passed',
              'fixtureSourceCommit': args.commit, 'routeNativeConsumer': 'passed',
              'routeControlledChromeConsumer': 'passed; external navigation intent only'}
    (output / 'acceptance.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key not in ['files', 'sdk']}))


if __name__ == '__main__':
    main()
