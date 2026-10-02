"""Consume the public read bridge from source, a pub archive, or a hosted package.

Runs a typed native HTTP consumer and an actual Chrome/Fetch consumer, including
relative URLs, document base changes, frozen destinations and account identity.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import time
from urllib.parse import unquote, urljoin, urlparse

from fullstack_consumer_smoke import Server, dart, flutter, package_root, root, run, stop


def main():
    chrome = (os.environ.get('CHROME_EXECUTABLE') or shutil.which('google-chrome')
              or shutil.which('chromium') or shutil.which('chromium-browser'))
    if chrome is None:
        mac = Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        if mac.is_file():
            chrome = str(mac)
    if not dart or not flutter or not chrome:
        raise RuntimeError('Dart, Flutter and Chrome are required; set CHROME_EXECUTABLE if needed.')
    with tempfile.TemporaryDirectory(prefix='odroe-query-consumer-') as temporary:
        base = Path(temporary)
        project = base / 'app'
        (project / 'lib').mkdir(parents=True)
        env = dict(os.environ)
        version = env.get('ODROE_HOSTED_VERSION')
        if version:
            env['PUB_CACHE'] = str(base / 'cache')
            env['PUB_HOSTED_URL'] = 'https://pub.dev'
        dependency = {'version': version} if version else {'path': str(package_root)}
        (project / 'pubspec.yaml').write_text(
            'name: query_rpc_consumer\nenvironment:\n  sdk: ^3.10.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n'
            '  web: ^1.1.1\n  odroe: ' + json.dumps(dependency) + '\n')
        for name in ['value_consumer.dart', 'browser_consumer.dart', 'browser_server.dart']:
            shutil.copyfile(root / 'test/fixtures/query_rpc' / name, project / 'lib' / name)
        run([flutter, 'pub', 'get'], project, env=env)
        config_file = project / '.dart_tool/package_config.json'
        config = json.loads(config_file.read_text())
        package = next(p for p in config['packages'] if p['name'] == 'odroe')
        resolved = Path(unquote(urlparse(urljoin(config_file.as_uri(), package['rootUri'])).path)).resolve()
        expected = Path(env['PUB_CACHE']) / 'hosted/pub.dev' / ('odroe-' + version) if version else package_root
        if resolved != expected or 'dependency_overrides:' in (project / 'pubspec.yaml').read_text():
            raise RuntimeError('Consumer did not resolve the requested dependency directly.')
        run([dart, 'analyze', '--fatal-infos', 'lib'], project, env=env)
        run([dart, 'run', 'lib/value_consumer.dart'], project, env=env)
        javascript = base / 'consumer.js'
        run([dart, 'compile', 'js', '-O2', '-o', str(javascript), 'lib/browser_consumer.dart'], project, env=env)
        report = base / 'report.json'
        server = Server([dart, 'run', 'lib/browser_server.dart', str(javascript), str(report)], project, base / 'unused.sqlite3', env=env)
        browser = None
        try:
            with (base / 'chrome.log').open('w') as log:
                browser = subprocess.Popen([chrome, '--headless', '--disable-gpu', '--no-sandbox',
                    '--no-first-run', '--no-default-browser-check',
                    '--user-data-dir=' + str(base / 'chrome-profile'),
                    server.origin + '/page/location.html'], stdout=log, stderr=log, start_new_session=True)
                deadline = time.monotonic() + 90
                while not report.exists():
                    if browser.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError('Chrome consumer did not report a result:\n' + (base / 'chrome.log').read_text()[-3000:])
                    time.sleep(0.1)
                result = json.loads(report.read_text())
                print(json.dumps(result), flush=True)
                if not result.get('passed'):
                    raise RuntimeError('Browser consumer failed.')
        finally:
            if browser is not None:
                stop(browser)
            server.close()
    print('Temporary consumer, browser profile, report and server cleaned.')


if __name__ == '__main__':
    main()
