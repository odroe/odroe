import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide PageRoute;

import '../app/context.dart';
import '../router/codec.dart';
import '../router/load.dart';
import '../router/match.dart';
import '../router/route.dart';
import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart';
import 'external_navigation.dart';
import 'page.dart';

/// Builds a router-level error page.
typedef RouterErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

/// Server-rendered loader data consumed by the first Flutter navigation.
final class RouterInitialState {
  /// Creates initial route state produced by a server renderer.
  const RouterInitialState({required this.location, required this.loads});

  /// The canonical location that produced [loads].
  final Uri location;

  /// Ordered loader results for the matched route branch.
  final List<RouteLoadResult> loads;
}

/// Flutter's [RouterConfig] implementation backed by typed routes.
final class AppRouter extends RouterConfig<Object> implements RouteNavigator {
  /// Creates a router from manually assembled or generated routes.
  factory AppRouter({
    required Iterable<RouteNode> routes,
    AppContext? app,
    Uri? initialLocation,
    WidgetBuilder? loading,
    WidgetBuilder? notFound,
    RouterErrorBuilder? error,
    RouterInitialState? initialState,
  }) {
    final routeList = List<RouteNode>.of(routes, growable: false);
    final localRouteIdentities = HashSet<Object>.identity();
    void collectLocalRoutes(Iterable<RouteNode> nodes) {
      for (final route in nodes) {
        if (route is PageRoute || route is ShellRoute) {
          localRouteIdentities.add(route.identity);
        }
        collectLocalRoutes(route.children);
      }
    }

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
    final context = app ?? AppContext.empty();
    final provider = _RouteInformationProvider(location);
    late final AppRouter router;
    final delegate = _RouterDelegate(
      matcher: RouteMatcher(routeList),
      provider: provider,
      router: () => router,
      app: context,
      loading: loading,
      notFound: notFound,
      error: error,
      initialState: initialState,
    );
    collectLocalRoutes(routeList);
    router = AppRouter._(
      provider: provider,
      delegate: delegate,
      app: context,
      ownsApp: app == null,
      localRouteIdentities: localRouteIdentities,
    );
    return router;
  }

  AppRouter._({
    required _RouteInformationProvider provider,
    required _RouterDelegate delegate,
    required this.app,
    required bool ownsApp,
    required Set<Object> localRouteIdentities,
  }) : _provider = provider,
       _delegate = delegate,
       _ownsApp = ownsApp,
       _localRouteIdentities = localRouteIdentities,
       super(
         routeInformationProvider: provider,
         routeInformationParser: const _RouteInformationParser(),
         routerDelegate: delegate,
         backButtonDispatcher: RootBackButtonDispatcher(),
       );

  final _RouteInformationProvider _provider;
  final _RouterDelegate _delegate;
  final bool _ownsApp;
  final Set<Object> _localRouteIdentities;

  /// Application services available to page loaders.
  final AppContext app;

  @override
  Uri get location => _delegate.location ?? _provider.value.uri;

  @override
  void go(Destination destination) {
    if (_openExternal(destination, replace: false)) return;
    _provider.navigate(destination.uri, _NavigationOperation.go);
  }

  @override
  Future<T?> push<T>(Destination destination) {
    if (_openExternal(destination, replace: false)) {
      return SynchronousFuture<T?>(null);
    }
    return _provider.push<T>(destination.uri);
  }

  @override
  void replace(Destination destination) {
    if (_openExternal(destination, replace: true)) return;
    _provider.navigate(destination.uri, _NavigationOperation.replace);
  }

  bool _openExternal(Destination destination, {required bool replace}) {
    final route = destination.route;
    // Definitions and platform wrappers share the registered binding's identity.
    if (_localRouteIdentities.contains(route.identity)) return false;
    if (route is PageRoute || route is ShellRoute) return false;
    if (navigateExternal(destination.uri, replace: replace)) return true;
    throw StateError(
      'Route ${destination.uri} has no Flutter page on this platform.',
    );
  }

  /// Releases listeners owned by this router.
  void dispose() {
    _delegate.dispose();
    _provider.dispose();
    if (_ownsApp) unawaited(app.dispose());
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
  _NavigationRequest({required this.operation, this.completion});

  final _NavigationOperation operation;
  final _NavigationCompletion? completion;
}

final class _RouteConfiguration {
  const _RouteConfiguration({required this.uri, required this.request});

  final Uri uri;
  final _NavigationRequest request;
}

final class _RouteInformationParser extends RouteInformationParser<Object> {
  const _RouteInformationParser();

  @override
  Future<Object> parseRouteInformation(RouteInformation routeInformation) {
    final state = routeInformation.state;
    final request = state is _NavigationRequest
        ? state
        : _NavigationRequest(operation: _NavigationOperation.external);
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

final class _HistoryEntry {
  _HistoryEntry(this.id, this.uri);
  final String id;
  final Uri uri;
  String? browserState;
}

typedef _HistoryUpdate = ({
  RouteInformation information,
  bool replace,
  _NavigationRequest? restore,
});

final class _HistoryTraversal {
  _HistoryTraversal(this.target, this.information);
  final _HistoryEntry target;
  final RouteInformation information;
  final completed = Completer<bool>();
  bool superseded = false;
}

final class _RouteInformationProvider extends RouteInformationProvider
    with WidgetsBindingObserver, ChangeNotifier {
  _RouteInformationProvider(Uri initialLocation)
    : _value = RouteInformation(
        uri: initialLocation,
        state: _NavigationRequest(operation: _NavigationOperation.external),
      ) {
    if (browserHistoryEnabled) {
      _removeHistoryListener = listenBrowserHistory(_nativeHistoryChanged);
    }
  }

  RouteInformation _value;
  RouteInformation? _lastWebReport;
  bool _reportedToEngine = false;
  static int _sessions = 0;
  final _session = '${DateTime.now().microsecondsSinceEpoch}:${_sessions++}';
  int _nextEntry = 0;
  final _entries = <_HistoryEntry>[];
  final _anchors = Expando<_HistoryEntry>();
  final _restored = Expando<bool>();
  final _updates = Queue<_HistoryUpdate>();
  int _position = -1;
  int? _historyLength;
  bool _writing = false;
  bool _disposed = false;
  _HistoryTraversal? _traversal;
  void Function()? _removeHistoryListener;
  String? _lastHistoryEvent;
  int _historyRevision = 0;
  static const _historyTimeout = Duration(seconds: 5);

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
    if (request != null && _restored[request] == true) return;
    final replace =
        !_reportedToEngine ||
        type == RouteInformationReportingType.neglect ||
        request?.operation == _NavigationOperation.replace ||
        request?.operation == _NavigationOperation.external;
    _reportedToEngine = true;
    _value = routeInformation;
    if (browserHistoryEnabled) {
      // Some framework versions report one request again after a reentrant
      // delegate notification. It still represents a single browser write.
      if (type == RouteInformationReportingType.none &&
          identical(_lastWebReport?.state, request) &&
          _lastWebReport?.uri == routeInformation.uri) {
        return;
      }
      _lastWebReport = routeInformation;
      _updates.add((
        information: routeInformation,
        replace: replace,
        restore: null,
      ));
      unawaited(_writeHistory());
      return;
    }
    SystemNavigator.selectMultiEntryHistory();
    SystemNavigator.routeInformationUpdated(
      uri: routeInformation.uri,
      // Internal requests can contain completers and must never cross the
      // platform JSON boundary. The URI is the durable restoration contract.
      state: null,
      replace: replace,
    );
  }

  // Called before notifying delegate listeners, so a reentrant navigation
  // cannot publish ahead of the pop it follows. The later Router report is
  // suppressed; loaders and retained pages continue to use the same records.
  void restore(RouteInformation information, _NavigationRequest target) {
    if (!browserHistoryEnabled) return;
    _reportedToEngine = true;
    _restored[information.state!] = true;
    _value = information;
    _updates.add((information: information, replace: true, restore: target));
    unawaited(_writeHistory());
  }

  Future<void> _writeHistory() async {
    if (_writing || _disposed) return;
    _writing = true;
    try {
      while (_updates.isNotEmpty && !_disposed) {
        final update = _updates.removeFirst();
        _checkHistoryLength();
        final target = update.restore == null
            ? null
            : _anchors[update.restore!];
        final index = target == null ? -1 : _entries.indexOf(target);
        final source = _position < 0 ? null : _entries[_position].browserState;
        if (index >= 0 &&
            index < _position &&
            target!.uri == update.information.uri &&
            source != null) {
          final traversal = _HistoryTraversal(target, update.information);
          _traversal = traversal;
          var acknowledged = false;
          try {
            if (moveBrowserHistory(index - _position, source)) {
              acknowledged = await traversal.completed.future.timeout(
                _historyTimeout,
                onTimeout: () => false,
              );
              // Recover a missing Flutter notification only from the browser's
              // actual current entry, never from an elapsed timer or length.
              if (!acknowledged &&
                  !traversal.superseded &&
                  !_disposed &&
                  browserHistoryState != source) {
                _nativeHistoryChanged();
                if (traversal.completed.isCompleted) {
                  acknowledged = await traversal.completed.future;
                }
              }
            }
          } on Object catch (error, stack) {
            _historyError(error, stack);
          } finally {
            _traversal = null;
          }
          if (_disposed) return;
          if (acknowledged || traversal.superseded) continue;
          // No submitted move or no matching event: retire the whole chain.
          // The local pop is already complete; replace its URL below.
          _forgetHistory();
        }
        try {
          await SystemNavigator.selectMultiEntryHistory().timeout(
            _historyTimeout,
          );
          if (_disposed) return;
          final beforeLength = _checkHistoryLength();
          final beforeState = browserHistoryState;
          final revision = _historyRevision;
          final knownForward = _entries.length - _position - 1;
          final expectedLength = update.replace
              ? beforeLength
              : beforeLength + 1 - knownForward;
          final entry = _HistoryEntry(
            '$_session:${_nextEntry++}',
            update.information.uri,
          );
          // A write can change native history even if its acknowledgement
          // fails. An earlier popstate is no longer a duplicate after it.
          _lastHistoryEvent = null;
          await SystemNavigator.routeInformationUpdated(
            uri: entry.uri,
            state: <String, Object?>{'odroe.history': entry.id},
            replace: update.replace,
          ).timeout(_historyTimeout);
          if (_disposed) return;
          final afterLength = _historyLength = browserHistoryLength;
          final afterState = browserHistoryState;
          // Commit ownership only after a successful, observed native write.
          // Opaque state comparison does not depend on engine wrapper fields.
          if (revision != _historyRevision ||
              afterState == null ||
              afterState == beforeState ||
              browserHistoryLocation != entry.uri) {
            _forgetHistory();
            continue;
          }
          entry.browserState = afterState;
          if (update.replace && _position >= 0) {
            _entries[_position] = entry;
          } else {
            _entries.removeRange(_position + 1, _entries.length);
            _entries.add(entry);
            _position++;
          }
          final request = update.information.state;
          if (request is _NavigationRequest) _anchors[request] = entry;
          if (update.restore != null) _anchors[update.restore!] = entry;
          if (afterLength != expectedLength) {
            // Known Forward truncation is included in the expected delta.
            // Any other delta invalidates ALL old distances. Growth later
            // cannot restore old anchors; only this fresh entry stays owned.
            _entries
              ..clear()
              ..add(entry);
            _position = 0;
          }
        } on Object catch (error, stack) {
          _forgetHistory();
          _historyError(error, stack);
        }
      }
    } finally {
      _writing = false;
    }
  }

  void _historyError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'odroe router',
        context: ErrorDescription('synchronizing browser history'),
      ),
    );
  }

  void _forgetHistory() {
    _entries.clear();
    _position = -1;
    _historyLength = browserHistoryLength;
  }

  int _checkHistoryLength() {
    final length = browserHistoryLength;
    if (_historyLength != null && _historyLength != length) _forgetHistory();
    _historyLength = length;
    return length;
  }

  void _nativeHistoryChanged() {
    if (_disposed) return;
    final state = browserHistoryState;
    final location = browserHistoryLocation;
    if (location == null) return;
    final entry = _entries
        .where((entry) => entry.browserState == state && entry.uri == location)
        .firstOrNull;
    _platformRoute(
      RouteInformation(
        uri: location,
        state: entry == null
            ? null
            : <String, Object?>{'odroe.history': entry.id},
      ),
    );
  }

  void _platformRoute(RouteInformation routeInformation) {
    _checkHistoryLength();
    final state = routeInformation.state;
    final id = state is Map ? state['odroe.history'] : null;
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (browserHistoryEnabled) {
      final current = browserHistoryState;
      final currentEntry = _entries
          .where((entry) => entry.browserState == current)
          .firstOrNull;
      if (currentEntry != null && currentEntry.id != id) return;
      if (routeInformation.uri != browserHistoryLocation ||
          (index >= 0 && _entries[index].browserState != current)) {
        return;
      }
      // The engine and the native observer can report the same event. Delayed
      // engine notifications must not replay an event over newer application UI.
      if (current != null && current == _lastHistoryEvent) return;
      if (index == _position &&
          index >= 0 &&
          _anchors[_value.state!] == _entries[index] &&
          _value.uri == routeInformation.uri) {
        return;
      }
      _lastHistoryEvent = current;
    }
    _historyRevision++;
    _position = index;
    if (index < 0) _entries.clear();
    final traversal = _traversal;
    if (traversal != null) {
      if (!traversal.superseded && id == traversal.target.id && index >= 0) {
        _anchors[traversal.information.state!] = traversal.target;
        if (!traversal.completed.isCompleted) {
          traversal.completed.complete(true);
        }
        return;
      }
      traversal.superseded = true;
      if (!traversal.completed.isCompleted) traversal.completed.complete(false);
    }
    // External navigation supersedes older queued writes, including writes
    // waiting behind a native update whose acknowledgement has not arrived.
    _updates.clear();
    final request = _NavigationRequest(
      operation: _NavigationOperation.external,
    );
    if (index >= 0) _anchors[request] = _entries[index];
    _value = RouteInformation(uri: routeInformation.uri, state: request);
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
    _disposed = true;
    _removeHistoryListener?.call();
    _updates.clear();
    final traversal = _traversal;
    if (traversal != null && !traversal.completed.isCompleted) {
      traversal.superseded = true;
      traversal.completed.complete(false);
    }
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

final class _RouterDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  _RouterDelegate({
    required RouteMatcher matcher,
    required _RouteInformationProvider provider,
    required AppRouter Function() router,
    required AppContext app,
    required WidgetBuilder? loading,
    required WidgetBuilder? notFound,
    required RouterErrorBuilder? error,
    required RouterInitialState? initialState,
  }) : _matcher = matcher,
       _provider = provider,
       _router = router,
       _app = app,
       _loading = loading,
       _notFound = notFound,
       _error = error,
       _initialState = initialState;

  final RouteMatcher _matcher;
  final _RouteInformationProvider _provider;
  final AppRouter Function() _router;
  final AppContext _app;
  final WidgetBuilder? _loading;
  final WidgetBuilder? _notFound;
  final RouterErrorBuilder? _error;
  RouterInitialState? _initialState;
  final List<_NavigationRecord> _records = <_NavigationRecord>[];
  final Expando<_NavigationRecord> _pageOwners = Expando<_NavigationRecord>(
    'route page owner',
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
          final load = initial.loads[index];
          if (load.isLoaded) {
            results[matches.routes[index].identity] = load;
          }
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
    if (matches != null && _needsLoad(matches, snapshot.results)) {
      unawaited(_load(record, matches));
    }
    return SynchronousFuture<void>(null);
  }

  Future<void> _load(_NavigationRecord record, RouteMatches matches) async {
    final results = HashMap<Object, RouteLoadResult>.identity()
      ..addAll(record.snapshot.results ?? const <Object, RouteLoadResult>{});
    await Future.wait<void>(
      matches.routes.map((route) async {
        if (results.containsKey(route.identity) ||
            (route is! PageRoute && route is! ShellRoute)) {
          return;
        }
        try {
          final data = switch (route) {
            PageRoute() => await route.runLoader(
              app: _app,
              router: _router(),
              matches: matches,
            ),
            ShellRoute() => await route.runLoader(
              app: _app,
              router: _router(),
              matches: matches,
            ),
            _ => const NoData(),
          };
          results[route.identity] = RouteLoadResult.data(data);
        } on Object catch (error, stackTrace) {
          results[route.identity] = RouteLoadResult.error(error, stackTrace);
        }
      }),
    );
    if (!_records.contains(record)) return;
    record.snapshot.results = results;
    notifyListeners();
  }

  bool _needsLoad(RouteMatches matches, Map<Object, RouteLoadResult>? results) {
    for (final route in matches.routes) {
      if ((route is PageRoute || route is ShellRoute) &&
          !(results?.containsKey(route.identity) ?? false)) {
        return true;
      }
    }
    return false;
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
      final shellIndex = routes.indexWhere((route) => route is ShellRoute);
      if (shellIndex >= 0) {
        routes = routes.sublist(shellIndex);
      } else {
        final page = routes.whereType<PageRoute>().lastOrNull;
        routes = page == null ? const <RouteNode>[] : <RouteNode>[page];
      }
    }
    final pages = _buildMatchedPages(context, record, matches, routes);
    if (pages.isEmpty) {
      final page = _FallbackPage(
        key: ValueKey<Object>(record.pageScope),
        child:
            _notFound?.call(context) ??
            ErrorWidget('Matched route has no Flutter page.'),
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
    List<RouteNode> routes,
  ) {
    final pages = <Page<Object?>>[];
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      if (route is ShellRoute) {
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
          app: _app,
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
      if (route is PageRoute) {
        pages.add(_buildPage(context, record, matches, route));
      }
    }
    return pages;
  }

  Page<Object?> _buildPage(
    BuildContext context,
    _NavigationRecord record,
    RouteMatches matches,
    PageRoute route,
  ) {
    final page = route.buildPage(
      context: context,
      app: _app,
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
        request: _NavigationRequest(operation: _NavigationOperation.replace),
      );
      _provider.restore(
        RouteInformation(uri: active.uri, state: _configuration!.request),
        active.request,
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
