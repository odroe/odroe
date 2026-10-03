"""Verify registered route identity in a fresh Flutter and Chrome consumer.

Only the temporary browser external-navigation adapter is instrumented, so
external destinations can be asserted without unloading Flutter's test runner.
The router, route definitions, bindings and matching remain unchanged.
"""
from pathlib import Path
import json
import os
import shutil
import tempfile
from urllib.parse import unquote, urljoin, urlparse

from fullstack_consumer_smoke import flutter, package_root, root, run


def main():
    if not flutter:
        raise RuntimeError('Put the selected Flutter SDK on PATH.')
    with tempfile.TemporaryDirectory(prefix='odroe-router-consumer-') as temporary:
        project = Path(temporary)
        (project / 'test').mkdir()
        shutil.copyfile(root / 'test/router/flutter_route_identity_test.dart',
                        project / 'test/navigation_test.dart')
        env = dict(os.environ)
        version = env.get('ODROE_HOSTED_VERSION')
        if version:
            env['PUB_CACHE'] = str(project / 'cache')
            env['PUB_HOSTED_URL'] = 'https://pub.dev'
        dependency = {'version': version} if version else {'path': str(package_root)}
        pubspec = (
            'name: router_navigation_consumer\nenvironment:\n  sdk: ^3.10.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n'
            '  odroe: ' + json.dumps(dependency) + '\n'
            'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n')
        (project / 'pubspec.yaml').write_text(pubspec)
        chrome = Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        if not env.get('CHROME_EXECUTABLE') and chrome.is_file():
            env['CHROME_EXECUTABLE'] = str(chrome)
        run([flutter, 'pub', 'get'], project, env=env)
        config_file = project / '.dart_tool/package_config.json'
        config = json.loads(config_file.read_text())
        package = next(p for p in config['packages'] if p['name'] == 'odroe')
        resolved = Path(unquote(urlparse(urljoin(config_file.as_uri(), package['rootUri'])).path)).resolve()
        expected = Path(env['PUB_CACHE']) / 'hosted/pub.dev' / ('odroe-' + version) if version else package_root
        if resolved != expected:
            raise RuntimeError('Route consumer did not resolve the requested dependency directly.')
        print('Native route dependency: ' + str(resolved), flush=True)
        run([flutter, 'analyze', '--no-pub', '--fatal-infos'], project, env=env)
        run([flutter, 'test', '--no-pub', '--concurrency=1',
             '--reporter=expanded', 'test/navigation_test.dart'], project, env=env)

        vendor = project / 'vendor/odroe'
        vendor.mkdir(parents=True)
        shutil.copytree(resolved / 'lib', vendor / 'lib')
        shutil.copyfile(resolved / 'pubspec.yaml', vendor / 'pubspec.yaml')
        (project / 'pubspec.yaml').write_text(pubspec.replace(
            json.dumps(dependency), json.dumps({'path': str(vendor)})))
        run([flutter, 'pub', 'get'], project, env=env)
        adapter = vendor / 'lib/src/router_flutter/external_navigation_web.dart'
        original = adapter.read_text()
        marker = 'bool navigateExternal(Uri location, {required bool replace}) {\n'
        if original.count(marker) != 1:
            raise RuntimeError('Browser external-navigation adapter changed; review instrumentation.')
        adapter.write_text("import 'dart:async';\n\n" + marker +
            '  final record = Zone.current[#odroeRouteIdentityExternal]\n'
            '      as void Function(Uri, bool)?;\n'
            "  if (record == null) throw StateError('Missing external navigation recorder.');\n"
            '  record(location, replace);\n'
            '  return true;\n}\n')
        changed = [str(source.relative_to(resolved))
                   for source in (resolved / 'lib').rglob('*.dart')
                   if source.read_bytes() != (vendor / source.relative_to(resolved)).read_bytes()]
        if changed != ['lib/src/router_flutter/external_navigation_web.dart']:
            raise RuntimeError('Unexpected product changes in the browser consumer: ' + repr(changed))
        run([flutter, 'test', '--no-pub', '--platform=chrome', '--concurrency=1',
             '--reporter=expanded', '--dart-define=ODROE_TEST_CONTROLLED_EXTERNAL=true',
             'test/navigation_test.dart'], project, env=env)
    print('Route identity consumer, controlled external adapter and Chrome profile cleaned.')


if __name__ == '__main__':
    main()
