/// Whether the host exposes browser URL history.
bool get browserHistoryEnabled => false;

/// Traverses browser history on supported hosts.
Future<void> moveBrowserHistory(int delta) async {}
