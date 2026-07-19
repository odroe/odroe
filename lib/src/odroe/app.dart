import 'dart:async';

import 'package:flutter/widgets.dart';

import '../query/client.dart';
import '../query/flutter_query.dart';
import '../rpc/client.dart';
import '../rpc/http.dart';
import '../rpc/serializer.dart';
import '../router/flutter_router.dart';
import '../router/route.dart';
import 'handoff.dart';
import 'handoff_browser.dart';

/// Builds the root Flutter widget from the connected Odroe runtime.
typedef OdroeAppBuilder = Widget Function(OdroeApp app);

/// Runtime objects owned by one standard Odroe Flutter application.
final class OdroeApp {
  OdroeApp._({
    required this.query,
    required this.router,
    required this.rpc,
    required StreamSubscription<Map<String, Object?>> frames,
    HttpTransport? ownedTransport,
  }) : _frames = frames,
       _ownedTransport = ownedTransport;

  /// Query client shared by Flutter widgets, loaders, and handoff frames.
  final QueryClient query;

  /// Client used by generated server-function references.
  final RpcClient rpc;

  /// Router configured with the server-rendered initial route state.
  final OdroeRouter router;
  final StreamSubscription<Map<String, Object?>> _frames;
  final HttpTransport? _ownedTransport;

  /// Reads the running Odroe application from any descendant widget.
  static OdroeApp of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OdroeScope>()!.app;

  /// Stops browser handoff consumption and disposes the router.
  Future<void> dispose() async {
    await _frames.cancel();
    router.dispose();
    _ownedTransport?.close();
  }
}

/// Creates Router, Query, and browser hydration as one application runtime.
OdroeApp createOdroeApp({
  required Iterable<RouteNode> routes,
  Uri? initialLocation,
  WidgetBuilder? loading,
  WidgetBuilder? notFound,
  RouterErrorBuilder? error,
  QueryClient? query,
  RpcClient? rpc,
  Uri? server,
  RpcTransport? transport,
  Serializer? serializer,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  final queryClient = query ?? QueryClient();
  final wire = serializer ?? rpc?.serializer ?? Serializer();
  HttpTransport? ownedTransport;
  final rpcClient =
      rpc ??
      RpcClient(
        baseUri: server ?? Uri.base,
        transport: transport ?? (ownedTransport = HttpTransport()),
        serializer: wire,
      );
  final handoff = Handoff(query: queryClient, serializer: wire);
  final initial = readBrowserHandoff();
  if (initial != null) handoff.apply(initial);

  final handoffLocation = handoff.location;
  final useHandoff =
      handoffLocation != null &&
      (initialLocation == null || initialLocation == handoffLocation);
  final router = OdroeRouter(
    routes: routes,
    initialLocation: initialLocation ?? handoffLocation,
    initialState: useHandoff
        ? RouterInitialState(location: handoffLocation, loads: handoff.loads)
        : null,
    loading: loading,
    notFound: notFound,
    error: error,
    query: queryClient,
  );
  final frames = browserHandoffFrames().listen(
    handoff.apply,
    onError: (Object error, StackTrace stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'odroe handoff',
        ),
      );
    },
  );
  return OdroeApp._(
    query: queryClient,
    router: router,
    rpc: rpcClient,
    frames: frames,
    ownedTransport: ownedTransport,
  );
}

/// Runs a Flutter application with Router, Query, RPC, and handoff connected.
void runOdroeApp({
  required Iterable<RouteNode> routes,
  required OdroeAppBuilder builder,
  Uri? initialLocation,
  WidgetBuilder? loading,
  WidgetBuilder? notFound,
  RouterErrorBuilder? error,
  QueryClient? query,
  RpcClient? rpc,
  Uri? server,
  RpcTransport? transport,
  Serializer? serializer,
}) {
  final app = createOdroeApp(
    routes: routes,
    initialLocation: initialLocation,
    loading: loading,
    notFound: notFound,
    error: error,
    query: query,
    rpc: rpc,
    server: server,
    transport: transport,
    serializer: serializer,
  );
  runApp(
    _OdroeScope(
      app: app,
      child: QueryClientProvider(client: app.query, child: builder(app)),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => hideBrowserDocument());
}

final class _OdroeScope extends InheritedWidget {
  const _OdroeScope({required this.app, required super.child});

  final OdroeApp app;

  @override
  bool updateShouldNotify(_OdroeScope oldWidget) => oldWidget.app != app;
}
