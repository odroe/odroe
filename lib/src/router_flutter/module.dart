import 'package:flutter/widgets.dart';

import '../app/context.dart';
import '../app/key.dart';
import '../app/module.dart';
import '../app/registry.dart';
import '../router/route.dart';
import 'router.dart';

/// The application context key used to read the configured [AppRouter].
const routerKey = ContextKey<AppRouter>('router');

/// Optional server-rendered state consumed by [RouterModule].
const routerInitialStateKey = ContextKey<RouterInitialState>(
  'routerInitialState',
);

/// Installs Flutter routing into an application context.
final class RouterModule extends Module {
  /// Creates a router module from manual or generated routes.
  RouterModule({
    required Iterable<RouteNode> routes,
    this.initialLocation,
    this.loading,
    this.notFound,
    this.error,
    this.initialState,
  }) : routes = List<RouteNode>.of(routes, growable: false);

  /// Routes installed by this module.
  final List<RouteNode> routes;

  /// Initial location overriding the platform route.
  final Uri? initialLocation;

  /// Widget shown before the first route is ready.
  final WidgetBuilder? loading;

  /// Widget shown when no route matches.
  final WidgetBuilder? notFound;

  /// Widget used for router-level failures.
  final RouterErrorBuilder? error;

  /// Optional server-rendered state for the first navigation.
  final RouterInitialState? initialState;

  late AppContext _app;
  AppRouter? _router;

  @override
  void register(ModuleRegistry registry) {
    registry.provideFactory(
      routerKey,
      () => _router ??= AppRouter(
        routes: routes,
        app: _app,
        initialLocation: initialLocation,
        loading: loading,
        notFound: notFound,
        error: error,
        initialState: initialState ?? _app.maybe(routerInitialStateKey),
      ),
    );
  }

  @override
  void initialize(AppContext context) {
    _app = context;
  }

  @override
  void dispose(AppContext context) {
    _router?.dispose();
  }
}
