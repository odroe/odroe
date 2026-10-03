"""Guard fresh hosted route-cache isolation without invoking Flutter."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import router_navigation_consumer_smoke as consumer


class RouteCacheIsolationTest(unittest.TestCase):
    def exercise(self, stale=False, alias=False):
        with tempfile.TemporaryDirectory() as outer:
            outer = Path(outer).resolve()
            seeded = outer / 'existing-cache/hosted/pub.dev/odroe-0.1.0-dev.1'
            seeded.mkdir(parents=True)
            marker = seeded / 'keep'
            marker.write_text('existing cache')
            temporary_directory = tempfile.TemporaryDirectory
            roots, calls = [], []

            @contextmanager
            def temporary(**kwargs):
                with temporary_directory(**kwargs) as temporary:
                    root = Path(temporary)
                    roots.append(root.resolve())
                    if alias:
                        link = outer / 'alias'
                        link.symlink_to(root.resolve(), target_is_directory=True)
                        yield str(link)
                    else:
                        yield temporary

            def fake_run(args, project, env=None, **kwargs):
                project = Path(project)
                cache = Path(env['PUB_CACHE'])
                self.assertEqual(project.name, 'app')
                self.assertEqual(project.parent, cache.parent)
                self.assertEqual(cache, cache.resolve())
                self.assertEqual(env['PUB_HOSTED_URL'], 'https://pub.dev')
                self.assertNotIn(project, cache.parents)
                calls.append(args)
                if args[1:3] == ['pub', 'get'] and len(calls) == 1:
                    self.assertFalse(cache.exists())
                    package = cache / 'hosted/pub.dev/odroe-0.1.0-dev.3'
                    adapter = package / 'lib/src/router_flutter/external_navigation_web.dart'
                    adapter.parent.mkdir(parents=True)
                    adapter.write_text('bool navigateExternal(Uri location, {required bool replace}) {\n  return false;\n}\n')
                    (package / 'pubspec.yaml').write_text('name: odroe\nversion: 0.1.0-dev.3\n')
                    bad_test = cache / 'hosted/pub.dev/third-party/test/unresolved.dart'
                    bad_test.parent.mkdir(parents=True)
                    bad_test.write_text("import 'package:missing/test.dart';\n")
                    (project / '.dart_tool').mkdir()
                    (project / '.dart_tool/package_config.json').write_text(json.dumps({
                        'packages': [{'name': 'odroe', 'rootUri': (seeded if stale else package).as_uri()}]}))
                elif args[1] == 'analyze':
                    # Keep the ordinary full-app analysis, with the poisoned
                    # dependency test completely outside its recursive tree.
                    self.assertEqual(args[2:], ['--no-pub', '--fatal-infos'])
                    self.assertFalse(any(p.name == 'unresolved.dart' for p in project.rglob('*.dart')))

            with mock.patch.dict(os.environ, ODROE_HOSTED_VERSION='0.1.0-dev.3',
                    PUB_CACHE=str(outer / 'existing-cache')), \
                    mock.patch.object(consumer, 'flutter', 'flutter'), \
                    mock.patch.object(consumer, 'run', side_effect=fake_run), \
                    mock.patch.object(consumer.tempfile, 'TemporaryDirectory', temporary):
                if stale:
                    with self.assertRaisesRegex(RuntimeError, 'requested dependency directly'):
                        consumer.main()
                    self.assertEqual(len(calls), 1)
                else:
                    consumer.main()
                    self.assertEqual(len(calls), 5)
                    self.assertEqual(calls[2][1], 'test')
                    self.assertIn('--platform=chrome', calls[-1])
            self.assertTrue(all(not root.exists() for root in roots))
            self.assertEqual(marker.read_text(), 'existing cache')

    def test_cache_is_outside_analyzed_app(self):
        self.exercise()

    def test_cache_path_is_canonical_through_alias(self):
        self.exercise(alias=True)

    def test_rejects_seeded_dependency_before_analysis(self):
        self.exercise(stale=True)


if __name__ == '__main__':
    unittest.main()
