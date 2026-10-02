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

  test('hash URL strategy preserves the live route and search', () {
    final app = odroe_flutter.App(
      modules: const <odroe_flutter.Module>[],
      builder: (_) => const SizedBox.shrink(),
      webPathUrls: false,
    );
    expect(app.webPathUrls, isFalse);
    final original = window.location.href;
    addTearDown(
      () => window.history.replaceState(window.history.state, '', original),
    );
    window.history.replaceState(
      window.history.state,
      '',
      '/#/posts/42?preview=true&tags=one&tags=two',
    );
    final state = document.createElement('script')
      ..id = '__odroe_state__'
      ..textContent = jsonEncode(<String, Object?>{
        'version': 1,
        'location': '/',
        'loads': const <Object?>[],
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
