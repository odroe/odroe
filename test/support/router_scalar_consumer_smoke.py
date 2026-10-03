"""Verify explicit and scalar route codecs in fresh native/Chrome consumers."""
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
    with tempfile.TemporaryDirectory(prefix='odroe-router-scalar-consumer-') as temporary:
        project = Path(temporary).resolve()
        files = [
            'test/fixtures/router_scalar/explicit_app.dart',
            'test/fixtures/router_scalar/scalar_app.dart',
            'test/router/flutter_scalar_navigation_test.dart',
        ]
        for name in files:
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(root / name, target)
        (project / 'pubspec.yaml').write_text(
            'name: router_scalar_consumer\nenvironment:\n  sdk: ^3.10.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n'
            '  odroe: ' + json.dumps({'path': str(package_root)}) + '\n'
            'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n')
        env = dict(os.environ)
        chrome = Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        if chrome.is_file():
            env.setdefault('CHROME_EXECUTABLE', str(chrome))
        run([flutter, 'pub', 'get'], project, env=env)
        config_file = project / '.dart_tool/package_config.json'
        config = json.loads(config_file.read_text())
        package = next(p for p in config['packages'] if p['name'] == 'odroe')
        resolved = Path(unquote(urlparse(urljoin(config_file.as_uri(), package['rootUri'])).path)).resolve()
        if resolved != package_root:
            raise RuntimeError('Scalar consumer resolved an unexpected Odroe source.')
        run([flutter, 'analyze', '--no-pub', '--fatal-infos'], project, env=env)
        test = 'test/router/flutter_scalar_navigation_test.dart'
        run([flutter, 'test', '--no-pub', '--reporter=expanded', test], project, env=env)
        run([flutter, 'test', '--no-pub', '--platform=chrome', '--reporter=expanded', test], project, env=env)
    print('Scalar route consumer and browser profile cleaned.')


if __name__ == '__main__':
    main()
