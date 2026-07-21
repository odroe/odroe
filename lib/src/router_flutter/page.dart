import 'dart:async';

import 'package:flutter/widgets.dart' hide PageRoute;
import 'package:flutter/widgets.dart' as flutter show PageRoute;

import '../app/binding.dart';
import '../app/context.dart';
import '../app/key.dart';
import '../router/codec.dart';
import '../router/load.dart';
import '../router/match.dart';
import '../router/path.dart';
import '../router/route.dart';

/// Navigation operations available to route widgets.
abstract interface class RouteNavigator {
  /// The active location.
  Uri get location;

  /// Navigates to [destination], replacing the active matched branch.
  void go(Destination destination);

  /// Pushes [destination] above the active page stack.
  Future<T?> push<T>(Destination destination);

  /// Replaces the top-most navigation entry with [destination].
  void replace(Destination destination);
}

/// Typed route state that does not depend on a Flutter build context.
class RouteState<P, S> {
  /// Creates route state.
  const RouteState({
    required this.app,
    required this.router,
    required this.params,
    required this.search,
    required this.location,
    required RouteMatches matches,
  }) : _matches = matches;

  /// The application context containing explicitly installed modules.
  final AppContext app;

  /// The active Odroe navigation controller.
  final RouteNavigator router;

  /// Path parameters owned by this route.
  final P params;

  /// Search state owned by this route.
  final S search;

  /// The complete active location.
  final Uri location;

  final RouteMatches _matches;

  /// Reads an application service.
  T read<T extends Object>(ContextKey<T> key) => app.read(key);

  /// Reads an optional application service.
  T? maybe<T extends Object>(ContextKey<T> key) => app.maybe(key);

  /// Returns module bindings assignable to [T], in registration order.
  Iterable<T> bindings<T extends ModuleBinding>() => app.bindings<T>();

  /// Returns a typed active ancestor or current route match.
  RouteMatch<ParentP, ParentS, ParentD>? match<ParentP, ParentS, ParentD>(
    TypedRoute<ParentP, ParentS, ParentD> route,
  ) => _matches.match(route);
}

/// Typed input passed to a Flutter page loader.
final class PageLoadContext<P, S> extends RouteState<P, S> {
  /// Creates page loader input.
  const PageLoadContext({
    required super.app,
    required super.router,
    required super.params,
    required super.search,
    required super.location,
    required super.matches,
  });
}

/// Loads data for a Flutter page or shell.
typedef PageLoader<P, S, D> =
    FutureOr<D> Function(PageLoadContext<P, S> context);

/// Typed state shared by route lifecycle widgets.
class RouteContext<P, S> extends RouteState<P, S> {
  /// Creates route context.
  const RouteContext({
    required this.buildContext,
    required super.app,
    required super.router,
    required super.params,
    required super.search,
    required super.location,
    required super.matches,
  });

  /// The Flutter context building this route widget.
  final BuildContext buildContext;
}

/// Typed ready state used while constructing a custom Flutter [Page].
final class RoutePageState<P, S, D> extends RouteState<P, S> {
  /// Creates custom-page state.
  const RoutePageState({
    required super.app,
    required super.router,
    required super.params,
    required super.search,
    required super.location,
    required super.matches,
    required this.data,
  });

  /// Loader data belonging to this route.
  final D data;
}

/// Typed state passed to a ready route page.
final class RoutePageContext<P, S, D> extends RouteContext<P, S> {
  /// Creates ready page context.
  const RoutePageContext({
    required super.buildContext,
    required super.app,
    required super.router,
    required super.params,
    required super.search,
    required super.location,
    required super.matches,
    required this.data,
  });

  /// Loader data belonging to this route.
  final D data;
}

/// Signals that a matched resource does not exist.
final class RouteNotFoundException implements Exception {
  /// Creates a not-found failure.
  const RouteNotFoundException([this.message]);

  /// Optional diagnostic detail.
  final String? message;

  @override
  String toString() => message == null
      ? 'RouteNotFoundException'
      : 'RouteNotFoundException: $message';
}

/// Builds a ready route widget.
typedef RouteWidgetBuilder<P, S, D> =
    Widget Function(RoutePageContext<P, S, D> context);

/// Framework-owned settings for an advanced custom [Page].
final class RoutePageSettings {
  /// Creates custom-page settings.
  const RoutePageSettings({
    required this.key,
    required this.name,
    required this.onPopInvoked,
  });

  /// Stable identity required by `Navigator.pages`.
  final LocalKey key;

  /// The complete active location.
  final String name;

  /// Callback required for typed `push<T>` results.
  final PopInvokedWithResultCallback<Object?> onPopInvoked;
}

/// Builds an advanced Flutter page for a ready route.
typedef RoutePageBuilder<P, S, D> =
    Page<Object?> Function(
      RoutePageState<P, S, D> state,
      RoutePageSettings settings,
    );

/// Builds a route while its loader is pending.
typedef RoutePendingBuilder<P, S> = Widget Function(RouteContext<P, S> context);

/// Builds a route loader failure.
typedef RouteErrorBuilder<P, S> =
    Widget Function(RouteContext<P, S> context, Object error);

/// Builds a matched route whose resource does not exist.
typedef RouteNotFoundBuilder<P, S> =
    Widget Function(RouteContext<P, S> context);

/// A typed route with Flutter page behavior.
final class PageRoute<P, S, D> implements TypedRoute<P, S, D> {
  PageRoute._({
    required this.definition,
    required this.load,
    required this.build,
    required this.page,
    required this.pending,
    required this.error,
    required this.notFound,
  }) : assert((build == null) != (page == null));

  /// The client-safe route definition supplying this route's types.
  final AppRoute<P, S, D> definition;

  /// Optional client-side loader.
  final PageLoader<P, S, D>? load;

  /// The default widget builder.
  final RouteWidgetBuilder<P, S, D>? build;

  /// The advanced page builder.
  final RoutePageBuilder<P, S, D>? page;

  /// The pending-state builder.
  final RoutePendingBuilder<P, S>? pending;

  /// The error-state builder.
  final RouteErrorBuilder<P, S>? error;

  /// The matched not-found builder.
  final RouteNotFoundBuilder<P, S>? notFound;

  @override
  List<RouteNode> get children => definition.children;

  @override
  PathTemplate get template => definition.template;

  @override
  Object get identity => definition.identity;

  @override
  bool get terminal => definition.terminal;

  @override
  bool get hasPathCodec => definition.hasPathCodec;

  @override
  RouteMetadata get metadata => definition.metadata;

  @override
  String? get path => definition.path;

  @override
  Object? decodePath(Map<String, List<String>> values) =>
      definition.decodePath(values);

  @override
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values) =>
      definition.decodeQuery(values);

  @override
  T? capability<T extends Object>(RouteCapability<T> key) =>
      definition.capability(key);

  @override
  List<String> encodePath(Object? params) => definition.encodePath(params);

  @override
  Map<String, List<String>> encodeQuery(Object? search) =>
      definition.encodeQuery(search);

  /// Returns a copy with [children] attached to the route definition.
  PageRoute<P, S, D> withChildren(Iterable<RouteNode> children) =>
      PageRoute<P, S, D>._(
        definition: definition.withChildren(children),
        load: load,
        build: build,
        page: page,
        pending: pending,
        error: error,
        notFound: notFound,
      );

  /// Binds generated file-route configuration to this page route.
  PageRoute<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) => PageRoute<P, S, D>._(
    definition: definition.compiled(
      path: path,
      params: params,
      search: search,
      terminal: terminal,
      children: children,
    ),
    load: load,
    build: build,
    page: page,
    pending: pending,
    error: error,
    notFound: notFound,
  );

  /// Runs this route's loader for the active branch.
  FutureOr<Object?> runLoader({
    required AppContext app,
    required RouteNavigator router,
    required RouteMatches matches,
  }) {
    final loader = load;
    if (loader == null) return const NoData();
    final match = matches.match(this);
    if (match == null) {
      throw StateError('Page route is not part of the active route branch.');
    }
    return loader(
      PageLoadContext<P, S>(
        app: app,
        router: router,
        params: match.params,
        search: match.search,
        location: matches.location,
        matches: matches,
      ),
    );
  }

  /// Builds this route's Flutter page for one navigation snapshot.
  Page<Object?> buildPage({
    required BuildContext context,
    required AppContext app,
    required RouteNavigator router,
    required RouteMatches matches,
    required RouteLoadResult? loadResult,
    required Object? pageScope,
    required PopInvokedWithResultCallback<Object?> onPopInvoked,
  }) {
    final match = matches.match(this);
    if (match == null) {
      throw StateError('Page route is not part of the active route branch.');
    }
    RouteContext<P, S> routeContext(BuildContext buildContext) =>
        RouteContext<P, S>(
          buildContext: buildContext,
          app: app,
          router: router,
          params: match.params,
          search: match.search,
          location: matches.location,
          matches: matches,
        );
    RoutePageContext<P, S, D> readyContext(BuildContext buildContext) =>
        RoutePageContext<P, S, D>(
          buildContext: buildContext,
          app: app,
          router: router,
          params: match.params,
          search: match.search,
          location: matches.location,
          matches: matches,
          data: loadResult!.data as D,
        );
    RoutePageState<P, S, D> readyState() => RoutePageState<P, S, D>(
      app: app,
      router: router,
      params: match.params,
      search: match.search,
      location: matches.location,
      matches: matches,
      data: loadResult!.data as D,
    );
    final key = ValueKey<_RoutePageIdentity>(
      _RoutePageIdentity(identity, match.params, pageScope),
    );

    if (loadResult == null) {
      return _WidgetPage(
        key: key,
        name: matches.location.toString(),
        onPopInvoked: onPopInvoked,
        child: Builder(
          builder: (context) =>
              pending?.call(routeContext(context)) ?? const SizedBox.shrink(),
        ),
      );
    }

    final failure = loadResult.error;
    if (failure != null) {
      return _WidgetPage(
        key: key,
        name: matches.location.toString(),
        onPopInvoked: onPopInvoked,
        child: Builder(
          builder: (context) {
            final current = routeContext(context);
            if (failure is RouteNotFoundException && notFound != null) {
              return notFound!(current);
            }
            if (error != null) return error!(current, failure);
            return ErrorWidget.withDetails(
              message: failure.toString(),
              error: FlutterError(failure.toString()),
            );
          },
        ),
      );
    }

    final pageBuilder = page;
    if (pageBuilder != null) {
      final settings = RoutePageSettings(
        key: key,
        name: matches.location.toString(),
        onPopInvoked: onPopInvoked,
      );
      final result = pageBuilder(readyState(), settings);
      if (result.key != key) {
        throw StateError('A custom route Page must use settings.key.');
      }
      if (!identical(result.onPopInvoked, onPopInvoked)) {
        throw StateError('A custom route Page must use settings.onPopInvoked.');
      }
      return result;
    }
    return _WidgetPage(
      key: key,
      name: matches.location.toString(),
      onPopInvoked: onPopInvoked,
      child: Builder(builder: (context) => build!(readyContext(context))),
    );
  }
}

/// Builds a route shell around its active descendant navigator.
typedef RouteShellBuilder<P, S, D> =
    Widget Function(RoutePageContext<P, S, D> context, Widget navigator);

/// A typed route carrying a nested Flutter navigator.
final class ShellRoute<P, S, D> implements TypedRoute<P, S, D> {
  ShellRoute._({
    required this.definition,
    required this.load,
    required this.build,
    required this.pending,
    required this.error,
    required this.notFound,
    required this.indexPage,
  });

  /// The client-safe route definition supplying this route's types.
  final AppRoute<P, S, D> definition;

  /// Optional client-side loader.
  final PageLoader<P, S, D>? load;

  /// The ready shell builder.
  final RouteShellBuilder<P, S, D> build;

  /// The pending-state builder.
  final RoutePendingBuilder<P, S>? pending;

  /// The error-state builder.
  final RouteErrorBuilder<P, S>? error;

  /// The matched not-found builder.
  final RouteNotFoundBuilder<P, S>? notFound;

  /// The optional page rendered at the shell route's own location.
  final PageRoute<P, S, D>? indexPage;

  @override
  List<RouteNode> get children => definition.children;

  @override
  PathTemplate get template => definition.template;

  @override
  Object get identity => definition.identity;

  @override
  bool get terminal => definition.terminal;

  @override
  bool get hasPathCodec => definition.hasPathCodec;

  @override
  RouteMetadata get metadata => definition.metadata;

  @override
  String? get path => definition.path;

  @override
  Object? decodePath(Map<String, List<String>> values) =>
      definition.decodePath(values);

  @override
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values) =>
      definition.decodeQuery(values);

  @override
  T? capability<T extends Object>(RouteCapability<T> key) =>
      definition.capability(key);

  @override
  List<String> encodePath(Object? params) => definition.encodePath(params);

  @override
  Map<String, List<String>> encodeQuery(Object? search) =>
      definition.encodeQuery(search);

  /// Attaches the page rendered at this shell's own location.
  ShellRoute<P, S, D> withPage(PageRoute<P, S, D> page) {
    final routeLoader = page.load ?? load;
    return ShellRoute<P, S, D>._(
      definition: definition,
      load: routeLoader,
      build: build,
      pending: pending,
      error: error,
      notFound: notFound,
      indexPage: PageRoute<P, S, D>._(
        definition: definition,
        load: routeLoader,
        build: page.build,
        page: page.page,
        pending: page.pending,
        error: page.error,
        notFound: page.notFound,
      ),
    );
  }

  /// Binds generated file-route configuration to this shell route.
  ShellRoute<P, S, D> compiled({
    required String path,
    PathParams<P>? params,
    SearchParams<S>? search,
    required bool terminal,
    Iterable<RouteNode> children = const <RouteNode>[],
  }) {
    final compiledDefinition = definition.compiled(
      path: path,
      params: params,
      search: search,
      terminal: terminal,
      children: children,
    );
    final page = indexPage;
    return ShellRoute<P, S, D>._(
      definition: compiledDefinition,
      load: load,
      build: build,
      pending: pending,
      error: error,
      notFound: notFound,
      indexPage: page == null
          ? null
          : PageRoute<P, S, D>._(
              definition: compiledDefinition,
              load: load,
              build: page.build,
              page: page.page,
              pending: page.pending,
              error: page.error,
              notFound: page.notFound,
            ),
    );
  }

  /// Runs this shell's loader for the active branch.
  FutureOr<Object?> runLoader({
    required AppContext app,
    required RouteNavigator router,
    required RouteMatches matches,
  }) {
    final loader = load;
    if (loader == null) return const NoData();
    final match = matches.match(this);
    if (match == null) {
      throw StateError('Shell route is not part of the active route branch.');
    }
    return loader(
      PageLoadContext<P, S>(
        app: app,
        router: router,
        params: match.params,
        search: match.search,
        location: matches.location,
        matches: matches,
      ),
    );
  }

  /// Builds this route's nested Flutter navigator page.
  Page<Object?> buildShellPage({
    required BuildContext context,
    required AppContext app,
    required RouteNavigator router,
    required RouteMatches matches,
    required RouteLoadResult? loadResult,
    required Object? pageScope,
    required List<Page<Object?>> pages,
    required PopInvokedWithResultCallback<Object?> onPopInvoked,
    required DidRemovePageCallback onDidRemovePage,
  }) {
    final match = matches.match(this);
    if (match == null) {
      throw StateError('Shell route is not part of the active route branch.');
    }
    RouteContext<P, S> routeContext(BuildContext buildContext) =>
        RouteContext<P, S>(
          buildContext: buildContext,
          app: app,
          router: router,
          params: match.params,
          search: match.search,
          location: matches.location,
          matches: matches,
        );
    RoutePageContext<P, S, D> readyContext(BuildContext buildContext) =>
        RoutePageContext<P, S, D>(
          buildContext: buildContext,
          app: app,
          router: router,
          params: match.params,
          search: match.search,
          location: matches.location,
          matches: matches,
          data: loadResult!.data as D,
        );
    final key = ValueKey<_RoutePageIdentity>(
      _RoutePageIdentity(identity, match.params, pageScope),
    );

    Widget child(BuildContext context) {
      if (loadResult == null) {
        return pending?.call(routeContext(context)) ?? const SizedBox.shrink();
      }
      final failure = loadResult.error;
      if (failure != null) {
        final current = routeContext(context);
        if (failure is RouteNotFoundException && notFound != null) {
          return notFound!(current);
        }
        if (error != null) return error!(current, failure);
        return ErrorWidget.withDetails(
          message: failure.toString(),
          error: FlutterError(failure.toString()),
        );
      }
      final navigator = Navigator(
        pages: pages,
        onDidRemovePage: onDidRemovePage,
      );
      return build(readyContext(context), navigator);
    }

    return _WidgetPage(
      key: key,
      name: matches.location.toString(),
      onPopInvoked: onPopInvoked,
      child: Builder(builder: child),
    );
  }
}

/// Attaches Flutter page behavior to a route definition.
extension AppRoutePage<P, S, D> on AppRoute<P, S, D> {
  /// Creates a Flutter page route.
  PageRoute<P, S, D> page({
    PageLoader<P, S, D>? load,
    RouteWidgetBuilder<P, S, D>? build,
    RoutePageBuilder<P, S, D>? page,
    RoutePendingBuilder<P, S>? pending,
    RouteErrorBuilder<P, S>? error,
    RouteNotFoundBuilder<P, S>? notFound,
  }) {
    if ((build == null) == (page == null)) {
      throw ArgumentError('Provide exactly one of build or page.');
    }
    return PageRoute<P, S, D>._(
      definition: this,
      load: load,
      build: build,
      page: page,
      pending: pending,
      error: error,
      notFound: notFound,
    );
  }
}

/// Attaches a nested Flutter navigator to a route definition.
extension AppRouteShell<P, S, D> on AppRoute<P, S, D> {
  /// Creates a Flutter shell route.
  ShellRoute<P, S, D> shell({
    PageLoader<P, S, D>? load,
    required RouteShellBuilder<P, S, D> build,
    RoutePendingBuilder<P, S>? pending,
    RouteErrorBuilder<P, S>? error,
    RouteNotFoundBuilder<P, S>? notFound,
  }) => ShellRoute<P, S, D>._(
    definition: this,
    load: load,
    build: build,
    pending: pending,
    error: error,
    notFound: notFound,
    indexPage: null,
  );
}

final class _RoutePageIdentity {
  const _RoutePageIdentity(this.route, this.params, this.scope);

  final Object route;
  final Object? params;
  final Object? scope;

  @override
  bool operator ==(Object other) =>
      other is _RoutePageIdentity &&
      identical(route, other.route) &&
      params == other.params &&
      identical(scope, other.scope);

  @override
  int get hashCode =>
      Object.hash(identityHashCode(route), params, identityHashCode(scope));
}

final class _WidgetPage extends Page<Object?> {
  const _WidgetPage({
    required super.key,
    required super.name,
    required super.onPopInvoked,
    required this.child,
  });

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) => _WidgetPageRoute(this);
}

final class _WidgetPageRoute extends flutter.PageRoute<Object?> {
  _WidgetPageRoute(_WidgetPage page) : super(settings: page);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => (settings as _WidgetPage).child;
}
