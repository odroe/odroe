/// Whether the host exposes browser URL history.
bool get browserHistoryEnabled => false;

/// Browser history is unavailable on this host.
int get browserHistoryLength => 0;

/// Browser history is unavailable on this host.
String? get browserHistoryState => null;

/// Browser history is unavailable on this host.
Uri? get browserHistoryLocation => null;

/// Traverses browser history on supported hosts.
bool moveBrowserHistory(int delta, String sourceState) => false;

/// Observes actual browser movement on supported hosts.
void Function() listenBrowserHistory(void Function() listener) => () {};
