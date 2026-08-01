@TestOn('browser')
library;

import 'package:odroe/src/document_flutter/browser.dart';
import 'package:odroe/src/router_flutter/external_navigation.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  tearDown(() {
    document.querySelector('#__odroe_state__')?.remove();
    document.querySelector('#__odroe_document__')?.remove();
    final frames = document.querySelectorAll('[data-odroe-frame]');
    for (var index = frames.length - 1; index >= 0; index--) {
      final frame = frames.item(index);
      if (frame != null) (frame as Element).remove();
    }
  });

  test('reads initial document handoff from the browser DOM', () {
    final state = document.createElement('script')
      ..id = '__odroe_state__'
      ..textContent = '{"route":"/docs"}';
    document.body!.appendChild(state);

    expect(readBrowserHandoff(), <String, Object?>{'route': '/docs'});
    expect(document.querySelector('#__odroe_state__'), isNull);
  });

  test('streams appended handoff frames and hides semantic HTML', () async {
    final semantic = document.createElement('main')..id = '__odroe_document__';
    document.body!.appendChild(semantic);
    final nextFrame = browserHandoffFrames().first;
    final frame = document.createElement('script')
      ..setAttribute('data-odroe-frame', '')
      ..textContent = '{"type":"query","value":42}';
    document.body!.appendChild(frame);

    expect(await nextFrame, <String, Object?>{'type': 'query', 'value': 42});
    hideBrowserDocument();
    expect(semantic.hasAttribute('hidden'), isTrue);
  });

  test('external navigation is available in a browser', () {
    final original = window.location.href;
    addTearDown(
      () => window.history.replaceState(window.history.state, '', original),
    );
    final destination = Uri.parse(
      original,
    ).replace(fragment: 'odroe-browser-platform-test');

    expect(navigateExternal(destination, replace: true), isTrue);
    expect(window.location.hash, '#odroe-browser-platform-test');
  });
}
