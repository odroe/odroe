import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

/// Whether the host exposes browser URL history.
bool get browserHistoryEnabled => urlStrategy != null;

/// A change detector only; this is not the current entry's browser index.
int get browserHistoryLength => web.window.history.length;

/// Opaque native state: no Flutter engine wrapper fields are interpreted.
String? get browserHistoryState {
  try {
    return jsonEncode(web.window.history.state.dartify());
  } on Object {
    return null;
  }
}

/// The current URL decoded by the host's strategy, retaining route fragments.
Uri? get browserHistoryLocation {
  final strategy = urlStrategy;
  if (strategy == null) return null;
  var path = strategy.getPath();
  if (strategy is PathUrlStrategy && !path.contains('#')) {
    // Default path strategies omit fragments. Read the raw suffix so an empty
    // fragment is preserved too; hash strategies already include it in path.
    final href = web.window.location.href;
    final fragment = href.indexOf('#');
    if (fragment >= 0) path += href.substring(fragment);
  }
  return Uri.parse(path);
}

/// Validates and submits in one synchronous step. A custom strategy's `go`
/// method can defer its side effect and cannot be cancelled after a user Back.
bool moveBrowserHistory(int delta, String sourceState) {
  if (browserHistoryState != sourceState) return false;
  web.window.history.go(delta);
  return true;
}

/// Observes actual browser movement even if a host delays Flutter's listener.
void Function() listenBrowserHistory(void Function() listener) {
  final callback = ((web.Event _) => listener()).toJS;
  web.window.addEventListener('popstate', callback);
  return () => web.window.removeEventListener('popstate', callback);
}
