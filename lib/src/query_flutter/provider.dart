import 'package:flutter/widgets.dart';

import '../query/client.dart';

/// Exposes one [QueryClient] to a Flutter widget subtree.
final class QueryClientProvider extends StatefulWidget {
  /// Creates a provider for [client].
  const QueryClientProvider({
    required this.client,
    required this.child,
    super.key,
  });

  /// The client shared by the subtree.
  final QueryClient client;

  /// The root of the subtree that can read [client].
  final Widget child;

  /// Reads the nearest query client and subscribes to provider changes.
  static QueryClient of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_QueryClientInherited>();
    if (inherited == null) {
      throw FlutterError(
        'No QueryClientProvider found. Add QueryModule to App.modules, add '
        'a QueryClientProvider above this widget, or pass a client directly.',
      );
    }
    return inherited.client;
  }

  @override
  State<QueryClientProvider> createState() => _QueryClientProviderState();
}

final class _QueryClientProviderState extends State<QueryClientProvider>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    widget.client.mount();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(QueryClientProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.client, widget.client)) return;
    oldWidget.client.unmount();
    widget.client.mount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.client.focusManager.isFocused = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) =>
      _QueryClientInherited(client: widget.client, child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.unmount();
    super.dispose();
  }
}

final class _QueryClientInherited extends InheritedWidget {
  const _QueryClientInherited({required this.client, required super.child});

  final QueryClient client;

  @override
  bool updateShouldNotify(_QueryClientInherited oldWidget) =>
      !identical(client, oldWidget.client);
}
