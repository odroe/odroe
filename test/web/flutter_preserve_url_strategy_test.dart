@TestOn('browser')
library;

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/url_strategy.dart' as web_navigation;
import 'package:odroe/odroe_flutter.dart' as odroe_flutter;

void main() {
  test('App preserves a host-disabled URL strategy by default', () {
    web_navigation.setUrlStrategy(null);

    final app = odroe_flutter.App(
      modules: const <odroe_flutter.Module>[],
      builder: (_) => const SizedBox.shrink(),
    );

    expect(app.webPathUrls, isNull);
    expect(web_navigation.urlStrategy, isNull);
  });
}
