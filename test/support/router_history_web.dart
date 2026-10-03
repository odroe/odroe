import 'package:flutter_web_plugins/url_strategy.dart';

/// Pairs a mocked navigation channel with disabled browser history traversal.
void disableBrowserHistory() => setUrlStrategy(null);
