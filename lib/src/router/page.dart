import 'dart:async';

import 'package:flutter/widgets.dart';

import 'codec.dart';
import 'match.dart';
import 'pattern.dart';
import 'route.dart';

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

/// Typed state shared by route lifecycle widgets.
class RouteContext<P, S> {
  /// Creates route context.
  const RouteContext({
    required this.buildContext,
    required this.router,
    required this.params,
    required this.search,
    required this.location,
    required RouteMatches matches,
  }) : _matches = matches;

  /// The Flutter context building this route page.
  final BuildContext buildContext;

  /// The active Odroe navigation controller.
  final RouteNavigator router;

  /// Path parameters owned by this route.
  final P params;

  /// Search state owned by this route.
  final S search;

  /// The complete active location.
  final Uri location;

  final RouteMatches _matches;

  /// Returns a typed active ancestor or current route match.
  RouteMatch<ParentP, ParentS, ParentD>? match<ParentP, ParentS, ParentD>(
    AppRoute<ParentP, ParentS, ParentD> route,
  ) => _matches.match(route);
}

/// Typed state passed to a ready route page.
final class RoutePageContext<P, S, D> extends RouteContext<P, S> {
  /// Creates ready page context.
  const RoutePageContext({
    required super.buildContext,
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

/// Builds an advanced Flutter page for a ready route.
typedef RoutePageBuilder<P, S, D> =
    Page<Object?> Function(RoutePageContext<P, S, D> context, LocalKey key);

/// Builds a route while its loader is pending.
typedef RoutePendingBuilder<P, S> = Widget Function(RouteContext<P, S> context);

/// Builds a route loader failure.
typedef RouteErrorBuilder<P, S> =
    Widget Function(RouteContext<P, S> context, Object error);

/// Builds a matched route whose resource does not exist.
typedef RouteNotFoundBuilder<P, S> =
    Widget Function(RouteContext<P, S> context);

/// A route definition carrying Flutter page behavior.
abstract class PageBoundRoute implements AnyAppRoute {
  /// Builds this route's page for one navigation snapshot.
  Page<Object?> buildPage({
    required BuildContext context,
    required RouteNavigator router,
    required RouteMatches matches,
    required RouteLoadResult? loadResult,
    required Object? pageScope,
    required PopInvokedWithResultCallback<Object?> onPopInvoked,
  });
}

/// The page fragment attached to an [AppRoute].
final class PageRouteFragment<P, S, D> implements PageBoundRoute {
  PageRouteFragment._({
    required this.definition,
    required this.build,
    required this.page,
    required this.pending,
    required this.error,
    required this.notFound,
  }) : assert((build == null) != (page == null));

  /// The client-safe route definition supplying this fragment's types.
  final AppRoute<P, S, D> definition;

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
  List<AnyAppRoute> get children => definition.children;

  @override
  RoutePattern get compiledPattern => definition.compiledPattern;

  @override
  Object get identity => definition.identity;

  @override
  bool get terminal => definition.terminal;

  @override
  bool get hasPathCodec => definition.hasPathCodec;

  @override
  String? get path => definition.path;

  @override
  Object? decodePath(Map<String, List<String>> values) =>
      definition.decodePath(values);

  @override
  DecodedSearch<Object?> decodeQuery(Map<String, List<String>> values) =>
      definition.decodeQuery(values);

  @override
  FutureOr<Object?> loadObject(Object? params, Object? search, Uri location) =>
      definition.loadObject(params, search, location);

  /// Returns a copy with [children] attached to the route definition.
  PageRouteFragment<P, S, D> withChildren(Iterable<AnyAppRoute> children) =>
      PageRouteFragment<P, S, D>._(
        definition: definition.withChildren(children),
        build: build,
        page: page,
        pending: pending,
        error: error,
        notFound: notFound,
      );

  @override
  Page<Object?> buildPage({
    required BuildContext context,
    required RouteNavigator router,
    required RouteMatches matches,
    required RouteLoadResult? loadResult,
    required Object? pageScope,
    required PopInvokedWithResultCallback<Object?> onPopInvoked,
  }) {
    final match = matches.match(definition);
    if (match == null) {
      throw StateError('Page fragment is not part of the active route branch.');
    }
    RouteContext<P, S> routeContext(BuildContext buildContext) =>
        RouteContext<P, S>(
          buildContext: buildContext,
          router: router,
          params: match.params,
          search: match.search,
          location: matches.location,
          matches: matches,
        );
    RoutePageContext<P, S, D> readyContext(BuildContext buildContext) =>
        RoutePageContext<P, S, D>(
          buildContext: buildContext,
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
    if (pageBuilder != null) return pageBuilder(readyContext(context), key);
    return _WidgetPage(
      key: key,
      name: matches.location.toString(),
      onPopInvoked: onPopInvoked,
      child: Builder(builder: (context) => build!(readyContext(context))),
    );
  }
}

/// Attaches Flutter page behavior to a route definition.
extension AppRoutePage<P, S, D> on AppRoute<P, S, D> {
  /// Creates a page fragment.
  PageRouteFragment<P, S, D> page({
    RouteWidgetBuilder<P, S, D>? build,
    RoutePageBuilder<P, S, D>? page,
    RoutePendingBuilder<P, S>? pending,
    RouteErrorBuilder<P, S>? error,
    RouteNotFoundBuilder<P, S>? notFound,
  }) {
    if ((build == null) == (page == null)) {
      throw ArgumentError('Provide exactly one of build or page.');
    }
    return PageRouteFragment<P, S, D>._(
      definition: this,
      build: build,
      page: page,
      pending: pending,
      error: error,
      notFound: notFound,
    );
  }
}

/// Creates destinations from a page fragment with path parameters.
extension ParameterizedPageRouteDestination<P, S, D>
    on PageRouteFragment<P, S, D> {
  /// Builds a canonical destination.
  Destination to({required P params, S? search}) =>
      definition.to(params: params, search: search);
}

/// Creates destinations from a static page fragment.
extension StaticPageRouteDestination<S, D>
    on PageRouteFragment<NoParams, S, D> {
  /// Builds a canonical destination.
  Destination to({S? search}) => definition.to(search: search);
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

final class _WidgetPageRoute extends PageRoute<Object?> {
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
