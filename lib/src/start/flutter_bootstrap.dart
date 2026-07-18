import 'dart:async';

import 'package:flutter/widgets.dart';

import '../query/client.dart';
import '../query/flutter_query.dart';
import '../router/flutter_router.dart';
import '../router/route.dart';
import 'handoff.dart';
import 'handoff_browser.dart';
import 'serialization.dart';

/// Builds the root Flutter widget from the connected Odroe runtime.
typedef OdroeAppBuilder = Widget Function(OdroeAppContext app);

/// Runtime objects owned by one standard Odroe Flutter application.
final class OdroeAppContext {
  OdroeAppContext._({
    required this.query,
    required this.router,
    required StreamSubscription<Map<String, Object?>> frames,
  }) : _frames = frames;

  /// Query client shared by Flutter widgets, loaders, and handoff frames.
  final QueryClient query;

  /// Router configured with the server-rendered initial route state.
  final OdroeRouter router;
  final StreamSubscription<Map<String, Object?>> _frames;

  /// Stops browser handoff consumption and disposes the router.
  Future<void> dispose() async {
    await _frames.cancel();
    router.dispose();
  }
}

/// Creates Router, Query, and browser hydration as one application runtime.
OdroeAppContext createOdroeApp({
  required Iterable<AnyAppRoute> routes,
  Uri? initialLocation,
  WidgetBuilder? loading,
  WidgetBuilder? notFound,
  RouterErrorBuilder? error,
  QueryClient? query,
  StartSerializer? serializer,
}) {
  WidgetsFlutterBinding.ensureInitialized();
  final queryClient = query ?? QueryClient();
  final handoff = StartHandoffClient(
    query: queryClient,
    serializer: serializer,
  );
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
          library: 'odroe start handoff',
        ),
      );
    },
  );
  return OdroeAppContext._(query: queryClient, router: router, frames: frames);
}

/// Runs a Flutter application with Router, Query, and Start already connected.
void runOdroeApp({
  required Iterable<AnyAppRoute> routes,
  required OdroeAppBuilder builder,
  Uri? initialLocation,
  WidgetBuilder? loading,
  WidgetBuilder? notFound,
  RouterErrorBuilder? error,
  QueryClient? query,
  StartSerializer? serializer,
}) {
  final app = createOdroeApp(
    routes: routes,
    initialLocation: initialLocation,
    loading: loading,
    notFound: notFound,
    error: error,
    query: query,
    serializer: serializer,
  );
  runApp(QueryClientProvider(client: app.query, child: builder(app)));
  WidgetsBinding.instance.addPostFrameCallback((_) => hideBrowserDocument());
}
