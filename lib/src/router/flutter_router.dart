import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'match.dart';
import 'page.dart';
import 'route.dart';

/// Builds a router-level error page.
typedef RouterErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

/// Flutter's RouterConfig implementation backed by typed Odroe routes.
final class OdroeRouter extends RouterConfig<Object> implements RouteNavigator {
  /// Creates a router from manually assembled or generated routes.
  factory OdroeRouter({
    required Iterable<AnyAppRoute> routes,
    Uri? initialLocation,
    WidgetBuilder? loading,
    WidgetBuilder? notFound,
    RouterErrorBuilder? error,
  }) {
    final location =
        initialLocation ??
        Uri.parse(ui.PlatformDispatcher.instance.defaultRouteName);
    final provider = _OdroeRouteInformationProvider(location);
    late final OdroeRouter router;
    final delegate = _OdroeRouterDelegate(
      matcher: RouteMatcher(routes),
      provider: provider,
      router: () => router,
      loading: loading,
      notFound: notFound,
      error: error,
    );
    router = OdroeRouter._(provider: provider, delegate: delegate);
    return router;
  }

  OdroeRouter._({
    required _OdroeRouteInformationProvider provider,
    required _OdroeRouterDelegate delegate,
  }) : _provider = provider,
       _delegate = delegate,
       super(
         routeInformationProvider: provider,
         routeInformationParser: const _OdroeRouteInformationParser(),
         routerDelegate: delegate,
         backButtonDispatcher: RootBackButtonDispatcher(),
       );

  final _OdroeRouteInformationProvider _provider;
  final _OdroeRouterDelegate _delegate;

  @override
  Uri get location => _delegate.location ?? _provider.value.uri;

  @override
  void go(Destination destination) {
    _provider.navigate(destination.uri, _NavigationOperation.go);
  }

  @override
  Future<T?> push<T>(Destination destination) =>
      _provider.push<T>(destination.uri);

  @override
  void replace(Destination destination) {
    _provider.navigate(destination.uri, _NavigationOperation.replace);
  }

  /// Releases listeners owned by this router.
  void dispose() {
    _delegate.dispose();
    _provider.dispose();
  }
}

enum _NavigationOperation { go, push, replace, external }

abstract interface class _NavigationCompletion {
  void complete(Object? value);
}

final class _TypedNavigationCompletion<T> implements _NavigationCompletion {
  final Completer<T?> _completer = Completer<T?>();

  Future<T?> get future => _completer.future;

  @override
  void complete(Object? value) {
    if (_completer.isCompleted) return;
    _completer.complete(value as T?);
  }
}

final class _NavigationRequest {
  const _NavigationRequest({required this.operation, this.completion});

  final _NavigationOperation operation;
  final _NavigationCompletion? completion;
}

final class _RouteConfiguration {
  const _RouteConfiguration({required this.uri, required this.request});

  final Uri uri;
  final _NavigationRequest request;
}

final class _OdroeRouteInformationParser
    extends RouteInformationParser<Object> {
  const _OdroeRouteInformationParser();

  @override
  Future<Object> parseRouteInformation(RouteInformation routeInformation) {
    final state = routeInformation.state;
    final request = state is _NavigationRequest
        ? state
        : const _NavigationRequest(operation: _NavigationOperation.external);
    return SynchronousFuture<Object>(
      _RouteConfiguration(uri: routeInformation.uri, request: request),
    );
  }

  @override
  RouteInformation restoreRouteInformation(Object configuration) {
    final value = configuration as _RouteConfiguration;
    return RouteInformation(uri: value.uri, state: value.request);
  }
}

final class _OdroeRouteInformationProvider extends RouteInformationProvider
    with WidgetsBindingObserver, ChangeNotifier {
  _OdroeRouteInformationProvider(Uri initialLocation)
    : _value = RouteInformation(
        uri: initialLocation,
        state: const _NavigationRequest(
          operation: _NavigationOperation.external,
        ),
      );

  RouteInformation _value;
  bool _reportedToEngine = false;

  @override
  RouteInformation get value => _value;

  void navigate(Uri uri, _NavigationOperation operation) {
    _value = RouteInformation(
      uri: uri,
      state: _NavigationRequest(operation: operation),
    );
    notifyListeners();
  }

  Future<T?> push<T>(Uri uri) {
    final completion = _TypedNavigationCompletion<T>();
    _value = RouteInformation(
      uri: uri,
      state: _NavigationRequest(
        operation: _NavigationOperation.push,
        completion: completion,
      ),
    );
    notifyListeners();
    return completion.future;
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    final state = routeInformation.state;
    final request = state is _NavigationRequest ? state : null;
    final replace =
        !_reportedToEngine ||
        type == RouteInformationReportingType.neglect ||
        request?.operation == _NavigationOperation.replace ||
        request?.operation == _NavigationOperation.external;
    _reportedToEngine = true;
    SystemNavigator.selectMultiEntryHistory();
    SystemNavigator.routeInformationUpdated(
      uri: routeInformation.uri,
      // Internal requests can contain completers and must never cross the
      // platform JSON boundary. The URI is the durable restoration contract.
      state: null,
      replace: replace,
    );
    _value = routeInformation;
  }

  void _platformRoute(RouteInformation routeInformation) {
    _value = RouteInformation(
      uri: routeInformation.uri,
      state:
          routeInformation.state ??
          const _NavigationRequest(operation: _NavigationOperation.external),
    );
    notifyListeners();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    _platformRoute(routeInformation);
    return SynchronousFuture<bool>(true);
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) WidgetsBinding.instance.addObserver(this);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    if (hasListeners) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final class _NavigationSnapshot {
  _NavigationSnapshot.matches(this.matches)
    : notFound = false,
      error = null,
      stackTrace = null;

  _NavigationSnapshot.notFound()
    : matches = null,
      notFound = true,
      error = null,
      stackTrace = null;

  _NavigationSnapshot.error(this.error, this.stackTrace)
    : matches = null,
      notFound = false;

  final RouteMatches? matches;
  final bool notFound;
  final Object? error;
  final StackTrace? stackTrace;
  Map<Object, RouteLoadResult>? results;
}

final class _NavigationRecord {
  _NavigationRecord({
    required this.configuration,
    required this.snapshot,
    required this.completion,
  });

  final _RouteConfiguration configuration;
  final _NavigationSnapshot snapshot;
  final _NavigationCompletion? completion;
  final Object pageScope = Object();
  Object? popResult;
}

final class _OdroeRouterDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  _OdroeRouterDelegate({
    required RouteMatcher matcher,
    required _OdroeRouteInformationProvider provider,
    required OdroeRouter Function() router,
    required WidgetBuilder? loading,
    required WidgetBuilder? notFound,
    required RouterErrorBuilder? error,
  }) : _matcher = matcher,
       _provider = provider,
       _router = router,
       _loading = loading,
       _notFound = notFound,
       _error = error;

  final RouteMatcher _matcher;
  final _OdroeRouteInformationProvider _provider;
  final OdroeRouter Function() _router;
  final WidgetBuilder? _loading;
  final WidgetBuilder? _notFound;
  final RouterErrorBuilder? _error;
  final List<_NavigationRecord> _records = <_NavigationRecord>[];
  final Expando<_NavigationRecord> _pageOwners = Expando<_NavigationRecord>(
    'Odroe page owner',
  );

  _RouteConfiguration? _configuration;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Uri? get location => _configuration?.uri;

  @override
  Object? get currentConfiguration => _configuration;

  @override
  Future<void> setNewRoutePath(Object configuration) =>
      _apply(configuration as _RouteConfiguration);

  @override
  Future<void> setInitialRoutePath(Object configuration) =>
      _apply(configuration as _RouteConfiguration);

  @override
  Future<void> setRestoredRoutePath(Object configuration) =>
      _apply(configuration as _RouteConfiguration);

  Future<void> _apply(_RouteConfiguration configuration) {
    late final _NavigationSnapshot snapshot;
    try {
      final matches = _matcher.match(configuration.uri);
      snapshot = matches == null
          ? _NavigationSnapshot.notFound()
          : _NavigationSnapshot.matches(matches);
    } on Object catch (error, stackTrace) {
      snapshot = _NavigationSnapshot.error(error, stackTrace);
    }

    final record = _NavigationRecord(
      configuration: configuration,
      snapshot: snapshot,
      completion: configuration.request.completion,
    );
    _install(record, configuration.request.operation);
    _configuration = configuration;
    notifyListeners();

    final matches = snapshot.matches;
    if (matches != null) unawaited(_load(record, matches));
    return SynchronousFuture<void>(null);
  }

  Future<void> _load(_NavigationRecord record, RouteMatches matches) async {
    final results = await matches.loadAll();
    if (!_records.contains(record)) return;
    record.snapshot.results = results;
    notifyListeners();
  }

  void _install(_NavigationRecord record, _NavigationOperation operation) {
    switch (operation) {
      case _NavigationOperation.push:
        if (_records.isEmpty) {
          _records.add(record);
        } else {
          _records.add(record);
        }
      case _NavigationOperation.replace:
        if (_records.isNotEmpty) {
          _records.removeLast().completion?.complete(null);
        }
        _records.add(record);
      case _NavigationOperation.go || _NavigationOperation.external:
        for (final previous in _records) {
          previous.completion?.complete(null);
        }
        _records
          ..clear()
          ..add(record);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Page<Object?>>[];
    if (_records.isEmpty) {
      pages.add(
        _FallbackPage(
          key: const ValueKey<String>('odroe.loading'),
          child: _loading?.call(context) ?? const SizedBox.shrink(),
        ),
      );
    } else {
      for (var index = 0; index < _records.length; index++) {
        final record = _records[index];
        pages.addAll(_buildRecordPages(context, record, pushed: index > 0));
      }
    }

    return Navigator(
      key: navigatorKey,
      pages: pages,
      onDidRemovePage: _didRemovePage,
    );
  }

  Iterable<Page<Object?>> _buildRecordPages(
    BuildContext context,
    _NavigationRecord record, {
    required bool pushed,
  }) sync* {
    final snapshot = record.snapshot;
    if (snapshot.notFound) {
      final page = _FallbackPage(
        key: ValueKey<Object>(record.pageScope),
        child:
            _notFound?.call(context) ??
            ErrorWidget('No route matches ${record.configuration.uri}.'),
      );
      _pageOwners[page] = record;
      yield page;
      return;
    }
    final failure = snapshot.error;
    if (failure != null) {
      final page = _FallbackPage(
        key: ValueKey<Object>(record.pageScope),
        child:
            _error?.call(
              context,
              failure,
              snapshot.stackTrace ?? StackTrace.empty,
            ) ??
            ErrorWidget(failure),
      );
      _pageOwners[page] = record;
      yield page;
      return;
    }

    final matches = snapshot.matches!;
    var routes = matches.routes.whereType<PageBoundRoute>().toList();
    if (pushed && routes.isNotEmpty) routes = <PageBoundRoute>[routes.last];
    if (routes.isEmpty) {
      final page = _FallbackPage(
        key: ValueKey<Object>(record.pageScope),
        child:
            _notFound?.call(context) ??
            ErrorWidget('Matched route has no page fragment.'),
      );
      _pageOwners[page] = record;
      yield page;
      return;
    }

    for (final route in routes) {
      final page = route.buildPage(
        context: context,
        router: _router(),
        matches: matches,
        loadResult: snapshot.results?[route.identity],
        pageScope: pushed ? record.pageScope : null,
        onPopInvoked: (didPop, result) {
          if (didPop) record.popResult = result;
        },
      );
      _pageOwners[page] = record;
      yield page;
    }
  }

  void _didRemovePage(Page<Object?> page) {
    final record = _pageOwners[page];
    if (record == null || !_records.contains(record)) return;
    final index = _records.indexOf(record);
    if (index > 0) {
      _records.removeAt(index);
      record.completion?.complete(record.popResult);
      final active = _records.last.configuration;
      _configuration = _RouteConfiguration(
        uri: active.uri,
        request: const _NavigationRequest(
          operation: _NavigationOperation.replace,
        ),
      );
      notifyListeners();
      return;
    }

    final parent = record.snapshot.matches?.parentLocation;
    if (parent != null) {
      _provider.navigate(parent, _NavigationOperation.replace);
    }
  }

  @override
  Future<bool> popRoute() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    return navigator.maybePop();
  }
}

final class _FallbackPage extends Page<Object?> {
  const _FallbackPage({required super.key, required this.child});

  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
    settings: this,
    pageBuilder: (context, animation, secondaryAnimation) => child,
  );
}
