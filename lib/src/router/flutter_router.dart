import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../query/client.dart';
import 'external_navigation.dart';
import 'match.dart';
import 'page.dart';
import 'route.dart';

/// Builds a router-level error page.
typedef RouterErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

/// Server-rendered loader data consumed by the first Flutter navigation.
final class RouterInitialState {
  /// Creates the initial route state produced by the Start server.
  const RouterInitialState({required this.location, required this.loads});

  /// The canonical location that produced [loads].
  final Uri location;

  /// Ordered loader results for the matched route branch.
  final List<RouteLoadResult> loads;
}

/// Flutter's RouterConfig implementation backed by typed Odroe routes.
final class OdroeRouter extends RouterConfig<Object> implements RouteNavigator {
  /// Creates a router from manually assembled or generated routes.
  factory OdroeRouter({
    required Iterable<AnyAppRoute> routes,
    Uri? initialLocation,
    WidgetBuilder? loading,
    WidgetBuilder? notFound,
    RouterErrorBuilder? error,
    QueryClient? query,
    RouterInitialState? initialState,
  }) {
    late final Uri location;
    if (initialLocation case final initial?) {
      if (!initial.hasAbsolutePath) {
        throw ArgumentError.value(
          initial,
          'initialLocation',
          'Router locations must have an absolute path.',
        );
      }
      location = initial;
    } else if (initialState case final initial?) {
      location = initial.location;
    } else {
      final platform = Uri.parse(
        ui.PlatformDispatcher.instance.defaultRouteName,
      );
      location = platform.hasAbsolutePath ? platform : Uri(path: '/');
    }
    final queryClient = query ?? QueryClient();
    final provider = _OdroeRouteInformationProvider(location);
    late final OdroeRouter router;
    final delegate = _OdroeRouterDelegate(
      matcher: RouteMatcher(routes),
      provider: provider,
      router: () => router,
      query: queryClient,
      loading: loading,
      notFound: notFound,
      error: error,
      initialState: initialState,
    );
    router = OdroeRouter._(
      provider: provider,
      delegate: delegate,
      query: queryClient,
      ownsQuery: query == null,
    );
    return router;
  }

  OdroeRouter._({
    required _OdroeRouteInformationProvider provider,
    required _OdroeRouterDelegate delegate,
    required this.query,
    required bool ownsQuery,
  }) : _provider = provider,
       _delegate = delegate,
       _ownsQuery = ownsQuery,
       super(
         routeInformationProvider: provider,
         routeInformationParser: const _OdroeRouteInformationParser(),
         routerDelegate: delegate,
         backButtonDispatcher: RootBackButtonDispatcher(),
       );

  final _OdroeRouteInformationProvider _provider;
  final _OdroeRouterDelegate _delegate;
  final bool _ownsQuery;

  /// Query client shared by every route loader and Flutter query observer.
  final QueryClient query;

  @override
  Uri get location => _delegate.location ?? _provider.value.uri;

  @override
  void go(Destination destination) {
    if (_openDocument(destination, replace: false)) return;
    _provider.navigate(destination.uri, _NavigationOperation.go);
  }

  @override
  Future<T?> push<T>(Destination destination) {
    if (_openDocument(destination, replace: false)) {
      return SynchronousFuture<T?>(null);
    }
    return _provider.push<T>(destination.uri);
  }

  @override
  void replace(Destination destination) {
    if (_openDocument(destination, replace: true)) return;
    _provider.navigate(destination.uri, _NavigationOperation.replace);
  }

  bool _openDocument(Destination destination, {required bool replace}) {
    final route = destination.route;
    if (route.hasFlutterPage || !route.hasDocument) return false;
    if (navigateExternal(destination.uri, replace: replace)) return true;
    throw StateError(
      'Route ${destination.uri} has a document but no Flutter page on this '
      'platform.',
    );
  }

  /// Releases listeners owned by this router.
  void dispose() {
    _delegate.dispose();
    _provider.dispose();
    if (_ownsQuery) query.clear();
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
    required QueryClient query,
    required WidgetBuilder? loading,
    required WidgetBuilder? notFound,
    required RouterErrorBuilder? error,
    required RouterInitialState? initialState,
  }) : _matcher = matcher,
       _provider = provider,
       _router = router,
       _query = query,
       _loading = loading,
       _notFound = notFound,
       _error = error,
       _initialState = initialState;

  final RouteMatcher _matcher;
  final _OdroeRouteInformationProvider _provider;
  final OdroeRouter Function() _router;
  final QueryClient _query;
  final WidgetBuilder? _loading;
  final WidgetBuilder? _notFound;
  final RouterErrorBuilder? _error;
  RouterInitialState? _initialState;
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
    late final _RouteConfiguration effectiveConfiguration;
    try {
      final matches = _matcher.match(configuration.uri);
      snapshot = matches == null
          ? _NavigationSnapshot.notFound()
          : _NavigationSnapshot.matches(matches);
      final initial = _initialState;
      if (matches != null &&
          initial != null &&
          matches.location == initial.location &&
          matches.routes.length == initial.loads.length) {
        final results = HashMap<Object, RouteLoadResult>.identity();
        for (var index = 0; index < matches.routes.length; index++) {
          results[matches.routes[index].identity] = initial.loads[index];
        }
        snapshot.results = results;
        _initialState = null;
      }
      effectiveConfiguration = matches == null
          ? configuration
          : _RouteConfiguration(
              uri: matches.location,
              request: configuration.request,
            );
    } on Object catch (error, stackTrace) {
      snapshot = _NavigationSnapshot.error(error, stackTrace);
      effectiveConfiguration = configuration;
    }

    final record = _NavigationRecord(
      configuration: effectiveConfiguration,
      snapshot: snapshot,
      completion: effectiveConfiguration.request.completion,
    );
    _install(record, effectiveConfiguration.request.operation);
    _configuration = effectiveConfiguration;
    notifyListeners();

    final matches = snapshot.matches;
    if (matches != null && snapshot.results == null) {
      unawaited(_load(record, matches));
    }
    return SynchronousFuture<void>(null);
  }

  Future<void> _load(_NavigationRecord record, RouteMatches matches) async {
    final results = await matches.loadAll(query: _query);
    if (!_records.contains(record)) return;
    record.snapshot.results = results;
    notifyListeners();
  }

  void _install(_NavigationRecord record, _NavigationOperation operation) {
    switch (operation) {
      case _NavigationOperation.push:
        _records.add(record);
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
    var routes = matches.routes;
    if (pushed) {
      final shellIndex = routes.indexWhere((route) => route is ShellBoundRoute);
      if (shellIndex >= 0) {
        routes = routes.sublist(shellIndex);
      } else {
        final page = routes.whereType<PageBoundRoute>().lastOrNull;
        routes = page == null ? const <AnyAppRoute>[] : <AnyAppRoute>[page];
      }
    }
    final pages = _buildMatchedPages(context, record, matches, routes);
    if (pages.isEmpty) {
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

    yield* pages;
  }

  List<Page<Object?>> _buildMatchedPages(
    BuildContext context,
    _NavigationRecord record,
    RouteMatches matches,
    List<AnyAppRoute> routes,
  ) {
    final pages = <Page<Object?>>[];
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      if (route is ShellBoundRoute) {
        final nestedPages = <Page<Object?>>[];
        final indexPage = route.indexPage;
        if (indexPage != null) {
          nestedPages.add(_buildPage(context, record, matches, indexPage));
        }
        nestedPages.addAll(
          _buildMatchedPages(
            context,
            record,
            matches,
            routes.sublist(index + 1),
          ),
        );
        final page = route.buildShellPage(
          context: context,
          router: _router(),
          matches: matches,
          loadResult: record.snapshot.results?[route.identity],
          pageScope: record.completion == null ? null : record.pageScope,
          pages: nestedPages,
          onPopInvoked: (didPop, result) {
            if (didPop) record.popResult = result;
          },
          onDidRemovePage: _didRemovePage,
        );
        _pageOwners[page] = record;
        pages.add(page);
        return pages;
      }
      if (route is PageBoundRoute) {
        pages.add(_buildPage(context, record, matches, route));
      }
    }
    return pages;
  }

  Page<Object?> _buildPage(
    BuildContext context,
    _NavigationRecord record,
    RouteMatches matches,
    PageBoundRoute route,
  ) {
    final page = route.buildPage(
      context: context,
      router: _router(),
      matches: matches,
      loadResult: record.snapshot.results?[route.identity],
      pageScope: record.completion == null ? null : record.pageScope,
      onPopInvoked: (didPop, result) {
        if (didPop) record.popResult = result;
      },
    );
    _pageOwners[page] = record;
    return page;
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
    if (navigator != null && navigator.canPop()) {
      return navigator.maybePop();
    }
    if (_records.isEmpty) return false;
    final parent = _records.last.snapshot.matches?.parentLocation;
    if (parent == null) return false;
    _provider.navigate(parent, _NavigationOperation.replace);
    return true;
  }

  @override
  void dispose() {
    for (final record in _records) {
      record.completion?.complete(null);
    }
    _records.clear();
    super.dispose();
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
