@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/document_flutter.dart';
import 'package:odroe/odroe.dart';
import 'package:odroe/odroe_flutter.dart' as odroe_flutter;
import 'package:odroe/router_flutter.dart';
import 'package:web/web.dart';

void main() {
  tearDown(() {
    document.querySelector('#__odroe_state__')?.remove();
  });

  test('stale prerender handoff yields to the live browser location', () {
    final existingBase = document.querySelector('base');
    final base = existingBase ?? document.createElement('base');
    final originalBaseHref = base.getAttribute('href');
    if (existingBase == null) document.head!.appendChild(base);
    base.setAttribute('href', '/');
    addTearDown(() {
      if (existingBase == null) {
        base.remove();
      } else if (originalBaseHref == null) {
        base.removeAttribute('href');
      } else {
        base.setAttribute('href', originalBaseHref);
      }
    });
    final firstApp = odroe_flutter.App(
      webPathUrls: true,
      modules: const <odroe_flutter.Module>[],
      builder: (_) => const SizedBox.shrink(),
    );
    final secondApp = odroe_flutter.App(
      webPathUrls: true,
      modules: const <odroe_flutter.Module>[],
      builder: (_) => const SizedBox.shrink(),
    );
    expect(firstApp.webPathUrls, isTrue);
    expect(secondApp.webPathUrls, isTrue);
    final original = window.location.href;
    addTearDown(
      () => window.history.replaceState(window.history.state, '', original),
    );
    window.history.replaceState(
      window.history.state,
      '',
      '/posts/42?preview=true&tags=one&tags=two',
    );
    final state = document.createElement('script')
      ..id = '__odroe_state__'
      ..textContent = jsonEncode(<String, Object?>{
        'version': 1,
        'location': '/posts/42',
        'loads': const <Object?>[
          <String, Object?>{
            'type': 'data',
            'data': <String, Object?>{
              r'$type': 'removed-adapter',
              r'$value': null,
            },
          },
        ],
      });
    document.body!.appendChild(state);
    final registry = ModuleRegistry();

    DocumentModule().register(registry);
    final initial = registry.read(routerInitialStateKey);

    expect(
      initial.location,
      Uri.parse('/posts/42?preview=true&tags=one&tags=two'),
    );
    expect(initial.loads, isEmpty);
  });
}
