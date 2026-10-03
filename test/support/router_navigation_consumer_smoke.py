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

from fullstack_consumer_smoke import flutter, package_root, root, run


def main():
    if not flutter:
        raise RuntimeError('Put the selected Flutter SDK on PATH.')
    with tempfile.TemporaryDirectory(prefix='odroe-router-consumer-') as temporary:
        project = Path(temporary)
        vendor = project / 'vendor/odroe'
        vendor.mkdir(parents=True)
        shutil.copytree(package_root / 'lib', vendor / 'lib')
        shutil.copyfile(package_root / 'pubspec.yaml', vendor / 'pubspec.yaml')
        (project / 'test').mkdir()
        shutil.copyfile(root / 'test/router/flutter_route_identity_test.dart',
                        project / 'test/navigation_test.dart')
        (project / 'pubspec.yaml').write_text(
            'name: router_navigation_consumer\nenvironment:\n  sdk: ^3.10.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n'
            '  odroe: ' + json.dumps({'path': str(vendor)}) + '\n'
            'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n')
        env = dict(os.environ)
        chrome = Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        if not env.get('CHROME_EXECUTABLE') and chrome.is_file():
            env['CHROME_EXECUTABLE'] = str(chrome)
        run([flutter, 'pub', 'get'], project, env=env)
        run([flutter, 'analyze', '--no-pub', '--fatal-infos'], project, env=env)
        run([flutter, 'test', '--no-pub', '--concurrency=1',
             '--reporter=expanded', 'test/navigation_test.dart'], project, env=env)

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
        changed = [str(source.relative_to(package_root))
                   for source in (package_root / 'lib').rglob('*.dart')
                   if source.read_bytes() != (vendor / source.relative_to(package_root)).read_bytes()]
        if changed != ['lib/src/router_flutter/external_navigation_web.dart']:
            raise RuntimeError('Unexpected product changes in the browser consumer: ' + repr(changed))
        run([flutter, 'test', '--no-pub', '--platform=chrome', '--concurrency=1',
             '--reporter=expanded', '--dart-define=ODROE_TEST_CONTROLLED_EXTERNAL=true',
             'test/navigation_test.dart'], project, env=env)
    print('Route identity consumer, controlled external adapter and Chrome profile cleaned.')


if __name__ == '__main__':
    main()
