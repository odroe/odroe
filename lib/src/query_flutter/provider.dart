import 'package:flutter/widgets.dart';

import '../query/client.dart';

/// Owns or borrows one [QueryClient] for a Flutter widget subtree.
final class QueryClientProvider extends StatefulWidget {
  /// Creates and owns a client for this mounted provider.
  ///
  /// [create] defaults to creating a [QueryClient]. It runs once when an owned
  /// lifetime begins, not on ordinary rebuilds or when the callback changes.
  /// Use a new [key] to reset that lifetime. The provider clears its owned
  /// client when the lifetime ends. Return a fresh client from [create]; use
  /// [QueryClientProvider.value] to borrow an existing client instead.
  const QueryClientProvider({
    required this.child,
    QueryClient Function()? create,
    super.key,
  }) : _create = create,
       _value = null;

  /// Borrows [client] without clearing its caches on replacement or disposal.
  ///
  /// The caller retains ownership. Passing a previously owned client to this
  /// constructor transfers cleanup responsibility to the caller without
  /// clearing the instance. Use [of] to read the mounted provider's client.
  const QueryClientProvider.value({
    required QueryClient client,
    required this.child,
    super.key,
  }) : _value = client,
       _create = null;

  final QueryClient Function()? _create;
  final QueryClient? _value;

  /// The root of the subtree that can read the shared client.
  final Widget child;

  /// Reads the nearest query client and subscribes to provider changes.
  static QueryClient of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_QueryClientInherited>();
    if (inherited == null) {
      throw FlutterError(
        'No QueryClientProvider found. Add a QueryClientProvider above this '
        'widget, pass a client directly, or install QueryModule in App.modules.',
      );
    }
    return inherited.client;
  }

  @override
  State<QueryClientProvider> createState() => _QueryClientProviderState();
}

final class _QueryClientProviderState extends State<QueryClientProvider>
    with WidgetsBindingObserver {
  QueryClient? _client;
  bool _ownsClient = false;

  @override
  void initState() {
    super.initState();
    _replaceClient(
      widget._value ?? widget._create?.call() ?? QueryClient(),
      ownsClient: widget._value == null,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(QueryClientProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changing an owned factory is an ordinary rebuild. A key change or a
    // transition back from borrowing starts a new owned lifetime.
    if (widget._value == null && _ownsClient) return;
    _replaceClient(
      widget._value ?? widget._create?.call() ?? QueryClient(),
      ownsClient: widget._value == null,
    );
  }

  void _replaceClient(QueryClient next, {required bool ownsClient}) {
    final previous = _client;
    final ownedPrevious = _ownsClient;
    _client = next;
    _ownsClient = ownsClient;
    if (identical(previous, next)) return;
    previous?.unmount();
    try {
      if (ownedPrevious) previous?.clear();
    } finally {
      // A lifecycle event may have happened before this provider connected.
      // Synchronize before mounting so polling and retries use the current state.
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null) {
        next.focusManager.isFocused = state == AppLifecycleState.resumed;
      }
      next.mount();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _client?.focusManager.isFocused = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) =>
      _QueryClientInherited(client: _client!, child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final client = _client;
    _client = null;
    client?.unmount();
    try {
      if (_ownsClient) client?.clear();
    } finally {
      super.dispose();
    }
  }
}

final class _QueryClientInherited extends InheritedWidget {
  const _QueryClientInherited({required this.client, required super.child});

  final QueryClient client;

  @override
  bool updateShouldNotify(_QueryClientInherited oldWidget) =>
      !identical(client, oldWidget.client);
}
