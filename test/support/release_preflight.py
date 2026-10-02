"""Validate the real pub artifact and consume its extracted package locally."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
import tempfile

from fullstack_consumer_smoke import flutter, root, run
from release_artifact import extract_package, package_version, sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if flutter is None:
        raise RuntimeError('Put the selected Flutter SDK on PATH.')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise RuntimeError('Choose an empty output directory to preserve earlier artifacts.')
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True):
        raise RuntimeError('Release preflight requires a committed, clean checkout.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    version = package_version(root)
    sdk = json.loads(subprocess.check_output([flutter, '--version', '--machine'], text=True))
    archive = output / f'odroe-{version}.tar.gz'
    run([flutter, 'pub', 'publish', '--dry-run'], root)
    # This hidden pub option is local-only. Combining it with --dry-run does
    # not emit an archive; never replace this with git archive or skip validation.
    run([flutter, 'pub', 'publish', '--to-archive=' + str(archive)], root)
    with tempfile.TemporaryDirectory(prefix='odroe-release-preflight-') as temp:
        package = Path(temp) / 'package'
        manifest = extract_package(archive, package)
        env = dict(os.environ, ODROE_PACKAGE_ROOT=str(package),
                   PUB_CACHE=str(Path(temp) / 'cache'), PUB_HOSTED_URL='https://pub.dev')
        for key in ['ODROE_HOSTED_VERSION', 'ODROE_CREATE_VERSION',
                    'ODROE_CREATE_DEFAULT', 'ODROE_CREATE_AOT']:
            env.pop(key, None)
        run([flutter, 'pub', 'get'], package, env=env)
        for name in ['fullstack_consumer_smoke', 'dependency_first_consumer_smoke',
                     'incremental_adoption_smoke']:
            run([sys.executable, str(root / 'test/support' / (name + '.py'))],
                root, timeout=900, env=env)
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True):
        raise RuntimeError('The source checkout changed during release preflight.')
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() != commit:
        raise RuntimeError('The source commit changed during release preflight.')
    result = {'package': 'odroe', 'version': version, 'sourceCommit': commit,
              'sdk': sdk, 'archiveSha256': sha256(archive), 'files': manifest,
              'archiveConsumers': 'passed', 'officialHostedAcceptance': 'not run',
              'published': False}
    (output / 'manifest.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key not in ['files', 'sdk']}))


if __name__ == '__main__':
    main()
