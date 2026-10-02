"""Consume the documented application with standard Flutter commands only.

Default: exercise the candidate checkout as a direct path dependency.
ODROE_HOSTED_VERSION: exercise an exact published package in a fresh pub cache.
Both modes keep the consumer independent of Odroe scaffolding and generation.
"""
from pathlib import Path
import json
import os
import shutil
import tempfile
from urllib.parse import unquote, urljoin, urlparse

from fullstack_consumer_smoke import dart, flutter, package_root, root, run


def main():
    if dart is None or flutter is None:
        raise RuntimeError('Put the selected Flutter SDK on PATH.')
    fixture = root / 'test/fixtures/dependency_first'
    source = (fixture / 'lib/main.dart').read_text()
    for path in ['README.md', 'sites/odroe.dev/content/docs/getting-started.mdc']:
        if f'```dart\n{source}```' not in (root / path).read_text():
            raise RuntimeError(f'{path} no longer contains the tested application.')
    with tempfile.TemporaryDirectory(prefix='odroe-dependency-first-') as temporary:
        base = Path(temporary)
        project = base / 'app'
        cache = (base / 'pub-cache').resolve()
        cache.mkdir()
        env = dict(os.environ, PUB_CACHE=str(cache), PUB_HOSTED_URL='https://pub.dev')
        version = os.environ.get('ODROE_HOSTED_VERSION')
        dependency = {'version': version} if version else {'path': str(package_root)}
        run([flutter, 'create', '--empty', '--platforms', 'web',
             '--project-name', 'dependency_first_consumer', str(project)], base, env=env)
        run([flutter, 'pub', 'add', 'odroe:' + json.dumps(dependency)], project, env=env)
        shutil.copyfile(fixture / 'lib/main.dart', project / 'lib/main.dart')
        (project / 'test').mkdir(exist_ok=True)
        shutil.copyfile(fixture / 'test/probe.dart', project / 'test/dependency_first_test.dart')
        config_file = project / '.dart_tool/package_config.json'
        config = json.loads(config_file.read_text())
        package = next(p for p in config['packages'] if p['name'] == 'odroe')
        resolved = Path(unquote(urlparse(urljoin(config_file.as_uri(), package['rootUri'])).path)).resolve()
        expected = cache / 'hosted/pub.dev' / ('odroe-' + version) if version else package_root
        if resolved != expected:
            raise RuntimeError(f'Unexpected Odroe dependency: {resolved}')
        if 'dependency_overrides:' in (project / 'pubspec.yaml').read_text():
            raise RuntimeError('The consumer must not use dependency overrides.')
        run([dart, 'analyze', '--fatal-infos'], project, env=env)
        run([flutter, 'test', '--no-pub', '--reporter', 'expanded',
             'test/dependency_first_test.dart'], project, env=env)
        run([flutter, 'build', 'web', '--release'], project, env=env)
        for path in ['odroe.yaml', '.odroe', 'lib/routes.dart', 'lib/routes.server.dart',
                     '.dart_tool/odroe', 'lib/routes']:
            if (project / path).exists():
                raise RuntimeError(f'Unexpected Odroe setup output: {path}')
        if not (project / 'build/web/main.dart.js').is_file():
            raise RuntimeError('Flutter web release output is missing.')
        print(json.dumps({'dependencySource': 'hosted' if version else 'path',
            'hostedVersion': version, 'freshOfficialCache': True,
            'analyze': True, 'query': True, 'manualNavigation': True,
            'cachedDataSurvivesNavigation': True, 'flutterWebReleaseBuild': True,
            'odroeCliInvoked': False, 'odroeConfigurationOrGeneratedRoutes': False}))
    print('Disposable dependency-first consumer and cache cleaned.')


if __name__ == '__main__':
    main()
