"""Exercise an existing Flutter app adding Query, manual routes, then HTTP RPC.

ODROE_HOSTED_VERSION is for post-release checks of a package containing the
owned QueryClientProvider API. The default exercises the candidate source.
"""
from pathlib import Path
import json
import os
import shutil
import tempfile
from urllib.parse import unquote, urljoin, urlparse

from fullstack_consumer_smoke import Server, dart, flutter, package_root, root, run


def main():
    if dart is None or flutter is None:
        raise RuntimeError('Put the selected Flutter SDK on PATH.')
    fixture = root / 'test/fixtures/incremental_adoption'
    with tempfile.TemporaryDirectory(prefix='odroe-incremental-') as temporary:
        base = Path(temporary)
        project = base / 'app'
        cache = (base / 'pub-cache').resolve()
        cache.mkdir()
        env = dict(os.environ, PUB_CACHE=str(cache), PUB_HOSTED_URL='https://pub.dev')
        version = os.environ.get('ODROE_HOSTED_VERSION')
        dependency = {'version': version} if version else {'path': str(package_root)}
        run([flutter, 'create', '--empty', '--platforms', 'web',
             '--project-name', 'incremental_consumer', str(project)], base, env=env)
        run([flutter, 'pub', 'add', 'odroe:' + json.dumps(dependency)], project, env=env)
        for directory in ['lib', 'bin']:
            shutil.copytree(fixture / directory, project / directory, dirs_exist_ok=True)
        (project / 'test').mkdir(exist_ok=True)
        shutil.copyfile(fixture / 'test/probe.dart', project / 'test/incremental_adoption_test.dart')
        config_file = project / '.dart_tool/package_config.json'
        config = json.loads(config_file.read_text())
        package = next(p for p in config['packages'] if p['name'] == 'odroe')
        resolved = Path(unquote(urlparse(urljoin(config_file.as_uri(), package['rootUri'])).path)).resolve()
        expected = cache / 'hosted/pub.dev' / ('odroe-' + version) if version else package_root
        if resolved != expected:
            raise RuntimeError(f'Unexpected dependency: {resolved}')
        if 'dependency_overrides:' in (project / 'pubspec.yaml').read_text():
            raise RuntimeError('The consumer must not use dependency overrides.')
        run([dart, 'analyze', '--fatal-infos'], project, env=env)
        server = Server([dart, 'run', 'bin/server.dart'], project, base / 'unused.sqlite3', env=env)
        try:
            define = '--dart-define=ODROE_RPC_ORIGIN=' + server.origin
            run([flutter, 'test', '--no-pub', '--reporter', 'expanded', define,
                 'test/incremental_adoption_test.dart'], project, env=env)
            for target in ['lib/main_query.dart', 'lib/main_routed.dart', 'lib/main.dart']:
                run([flutter, 'build', 'web', '--release', '--target', target, define],
                    project, env=env)
        finally:
            server.close()
        for path in ['odroe.yaml', '.odroe', '.dart_tool/odroe', 'lib/routes.dart',
                     'lib/routes.server.dart', 'lib/routes']:
            if (project / path).exists():
                raise RuntimeError(f'Unexpected initialization or generated output: {path}')
        print(json.dumps({'dependencySource': 'hosted' if version else 'path',
            'hostedVersion': version, 'existingCounter': True, 'queryCache': True,
            'manualRoutes': True, 'realHttpRpc': True, 'standardFlutterWebBuilds': 3,
            'odroeCliInvoked': False, 'odroeConfigurationOrGeneration': False}))
    print('Disposable incremental consumer, cache, and server cleaned.')


if __name__ == '__main__':
    main()
