"""Accept an exact official release using the published artifact's own CLI."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

from fullstack_consumer_smoke import flutter, root, run
from release_artifact import extract_package, package_version, sha256, verify_manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--archive-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True):
        raise RuntimeError('Published acceptance requires a clean source checkout.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', args.commit) or commit != args.commit:
        raise ValueError('Checkout must match the exact reviewed source commit.')
    if package_version(root) != args.version:
        raise ValueError('Requested and checked-out package versions differ.')
    if not re.fullmatch(r'[0-9a-f]{64}', args.archive_sha256):
        raise ValueError('An exact preflight archive SHA256 is required.')
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
        source_archive = base / 'source.tar.gz'
        run([flutter, 'pub', 'publish', '--to-archive=' + str(source_archive)], root)
        source_manifest = extract_package(source_archive, base / 'source-package')
        verify_manifest(manifest, source_manifest)
        env = dict(os.environ, ODROE_PACKAGE_ROOT=str(package),
                   PUB_CACHE=str(base / 'cache'), PUB_HOSTED_URL='https://pub.dev')
        for key in ['ODROE_HOSTED_VERSION', 'ODROE_CREATE_VERSION',
                    'ODROE_CREATE_DEFAULT', 'ODROE_CREATE_AOT']:
            env.pop(key, None)
        run([flutter, 'pub', 'get'], package, env=env)
        for aot in ['0', '1']:
            cli_env = dict(env, ODROE_CREATE_DEFAULT='1', ODROE_CREATE_AOT=aot)
            run([sys.executable, str(root / 'test/support/fullstack_consumer_smoke.py')],
                root, timeout=900, env=cli_env)
        for name in ['dependency_first_consumer_smoke', 'incremental_adoption_smoke',
                     'query_rpc_consumer_smoke', 'router_navigation_consumer_smoke']:
            run([sys.executable, str(root / 'test/support' / (name + '.py'))],
                root, timeout=900, env=dict(env, ODROE_HOSTED_VERSION=args.version))
    if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True)
            or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() != commit):
        raise RuntimeError('The source checkout changed during published acceptance.')
    result = {'package': 'odroe', 'version': args.version, 'sourceCommit': commit, 'sdk': sdk,
              'archiveSha256': args.archive_sha256, 'files': manifest,
              'registry': 'https://pub.dev', 'interpretedPublishedCli': 'passed',
              'aotPublishedCli': 'passed', 'freshHostedConsumers': 'passed'}
    (output / 'acceptance.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key not in ['files', 'sdk']}))


if __name__ == '__main__':
    main()
