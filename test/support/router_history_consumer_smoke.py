"""Build a real Flutter app and verify browser history through Chrome CDP."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time

from fullstack_consumer_smoke import flutter, package_root, root, run, stop


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if not Path(self.translate_path(self.path)).is_file():
            self.path = '/index.html'
        super().do_GET()

    def log_message(self, *_):
        pass


def main():
    chrome = (os.environ.get('CHROME_EXECUTABLE') or shutil.which('google-chrome')
              or '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
    if not flutter or not shutil.which('node') or not Path(chrome).is_file():
        raise RuntimeError('Flutter, Node 22+, and Chrome must be available.')
    with tempfile.TemporaryDirectory(prefix='odroe-router-history-') as temporary:
        directory = Path(temporary).resolve()
        project = directory / 'app'
        run([flutter, 'create', '--empty', '--platforms=web',
             '--project-name=router_history_consumer', str(project)], directory)
        (project / 'pubspec.yaml').write_text(
            'name: router_history_consumer\nenvironment:\n  sdk: ^3.10.0\n'
            'dependencies:\n  flutter:\n    sdk: flutter\n'
            '  flutter_web_plugins:\n    sdk: flutter\n'
            '  odroe: ' + json.dumps({'path': str(package_root)}) + '\n')
        shutil.copyfile(root / 'test/fixtures/router_history/main.dart', project / 'lib/main.dart')
        run([flutter, 'pub', 'get'], project)
        run([flutter, 'build', 'web', '--release', '--no-pub',
             '--no-web-resources-cdn', '--no-wasm-dry-run'], project)
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(
            Handler, directory=str(project / 'build/web')))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        profile = directory / 'chrome-profile'
        try:
            with (directory / 'chrome.log').open('w') as log:
                process = subprocess.Popen([
                    chrome, '--headless=new', '--no-first-run', '--no-default-browser-check',
                    '--remote-debugging-port=0', f'--user-data-dir={profile}', 'about:blank',
                ], stdout=log, stderr=log, start_new_session=True)
                try:
                    port_file = profile / 'DevToolsActivePort'
                    deadline = time.monotonic() + 30
                    while not port_file.exists():
                        if process.poll() is not None or time.monotonic() >= deadline:
                            raise RuntimeError('Chrome did not start: ' + (directory / 'chrome.log').read_text())
                        time.sleep(0.05)
                    debug_port = port_file.read_text().splitlines()[0]
                    run(['node', str(root / 'test/support/router_history_browser.mjs'),
                         debug_port, f'http://127.0.0.1:{server.server_port}'], project, timeout=480)
                finally:
                    stop(process)
        finally:
            server.shutdown()
            server.server_close()
    print('Browser history consumer, Chrome profile, and HTTP server cleaned.')


if __name__ == '__main__':
    main()
