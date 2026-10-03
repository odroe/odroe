import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:odroe/router_flutter.dart';

@JS('routeHistoryHash')
external JSBoolean? get _useHash;
@JS('routeHistoryAction')
external set _action(JSFunction value);
@JS('routeHistorySnapshot')
external set _snapshot(JSFunction value);
@JS('routeHistoryNativeCalls')
external JSNumber? get _nativeCalls;
@JS('routeHistoryBacksAfterGo')
external set _backsAfterGo(JSNumber value);
@JS('routeHistoryMoveFault')
external set _moveFault(JSString value);
@JS('routeHistoryNativePending')
external JSBoolean? get _nativePending;

bool _holdTraversal = false;
Completer<void>? _gate;
int _traversals = 0;
bool _holdGo = false;
bool _failWrite = false;
bool _failWriteAfter = false;
final _notifications = <void Function()>[];
final _errors = <String>[];

// The legacy go gate exposes the old delayed-strategy hazard. The notification
// gate delays Flutter delivery while native history still moves. Neither
// creates history entries or synthesizes popstate events.
mixin _TraversalGate on HashUrlStrategy {
  @override
  void Function() addPopStateListener(void Function(Object?) listener) =>
      super.addPopStateListener((state) {
        if (_holdTraversal) {
          _gate ??= Completer<void>();
          _notifications.add(() => listener(state));
        } else {
          listener(state);
        }
      });

  @override
  void pushState(Object? state, String title, String url) {
    if (_failWrite) {
      _failWrite = false;
      throw StateError('injected history write failure');
    }
    super.pushState(state, title, url);
    if (_failWriteAfter) {
      _failWriteAfter = false;
      throw StateError('injected failure after native history write');
    }
  }

  @override
  Future<void> go(int count) async {
    _traversals++;
    if (_holdGo) {
      final gate = _gate = Completer<void>();
      await gate.future;
      _gate = null;
    }
    await super.go(count);
  }
}

class _PathHistory extends PathUrlStrategy with _TraversalGate {}

class _HashHistory extends HashUrlStrategy with _TraversalGate {}

class _NavigationNotifications with WidgetsBindingObserver {
  RouteInformation? latest;

  @override
  Future<bool> didPushRouteInformation(RouteInformation information) async {
    latest = information;
    return false;
  }
}

final _home = AppRoute<NoParams, NoSearch, NoData>(path: '/');
final _posts = AppRoute<NoParams, int?, NoData>(
  path: '/posts',
  search: SearchParams.optionalInteger('authorId'),
);
final _post = AppRoute<int, NoSearch, NoData>(
  path: '/post/:postId',
  params: PathParams.integer('postId'),
);
final _edit = AppRoute<int, NoSearch, NoData>(
  path: 'edit/:postId',
  params: PathParams.integer('postId'),
);
final _workspace = AppRoute<NoParams, NoSearch, NoData>(path: '/workspace');
final _workspaceEdit = AppRoute<NoParams, NoSearch, NoData>(path: 'edit');

/// A real application: browser tests call the same actions as its controls.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) => _errors.add(details.exceptionAsString());
  setUrlStrategy((_useHash?.toDart ?? false) ? _HashHistory() : _PathHistory());
  runApp(const _HistoryApp());
}

class _HistoryApp extends StatefulWidget {
  const _HistoryApp();

  @override
  State<_HistoryApp> createState() => _HistoryAppState();
}

class _HistoryAppState extends State<_HistoryApp> {
  final list = GlobalKey<_ListState>();
  final results = <String?>[];
  final notifications = _NavigationNotifications();
  RouteInformation? savedNotification;
  bool requestedDuringNativeMove = false;
  late final router = AppRouter(
    routes: [
      _home.page(build: (_) => screen('Home')),
      _posts
          .page(
            build: (_) => _List(key: list, action: act),
          )
          .withChildren([_edit.page(build: (_) => screen('Edit post'))]),
      _post.page(build: (_) => screen('Post')),
      _workspace
          .shell(build: (_, child) => child)
          .withPage(_workspace.page(build: (_) => screen('Workspace')))
          .compiled(
            path: '/workspace',
            terminal: true,
            children: [
              _workspaceEdit.page(build: (_) => screen('Workspace edit')),
            ],
          ),
    ],
  );

  void act(String action) {
    switch (action) {
      case 'list':
        router.go(_posts.to(search: 7));
      case 'pushList':
        router.push<String>(_posts.to(search: 7)).then(results.add);
      case 'push':
        router.push<String>(_post.to(params: 1)).then(results.add);
      case 'pushNext':
        router.push<String>(_post.to(params: 3)).then(results.add);
      case 'goNext':
        router.go(_post.to(params: 3));
      case 'batchPush':
        act('push');
        act('pushNext');
      case 'shell':
        router
            .push<String>(
              _workspace.ref().then(_workspaceEdit.ref()).destination,
            )
            .then(results.add);
      case 'hold':
        _holdTraversal = true;
      case 'holdGo':
        _holdGo = true;
      case 'failWrite':
        _failWrite = true;
      case 'failWriteAfter':
        _failWriteAfter = true;
      case 'dropMove':
        _moveFault = 'drop'.toJS;
      case 'failMove':
        _moveFault = 'throw'.toJS;
      case 'backAfterGo':
        _backsAfterGo = 1.toJS;
      case 'twiceBackAfterGo':
        _backsAfterGo = 2.toJS;
      case 'release':
        _holdTraversal = false;
        _holdGo = false;
        _gate?.complete();
        _gate = null;
        final notifications = List<void Function()>.of(_notifications);
        _notifications.clear();
        for (final notification in notifications) {
          notification();
        }
      case 'reentrantPush' || 'reentrantGo':
        void listener() {
          if (router.location.path != '/posts') return;
          router.routerDelegate.removeListener(listener);
          requestedDuringNativeMove = _nativePending?.toDart ?? false;
          act(action == 'reentrantGo' ? 'goNext' : 'pushNext');
        }
        router.routerDelegate.addListener(listener);
        act('pop');
      case 'nested':
        router
            .push<String>(
              _posts.ref(search: 7).then(_edit.ref(params: 1)).destination,
            )
            .then(results.add);
      case 'replace':
        router.replace(_post.to(params: 2));
      case 'pop':
        final delegate =
            router.routerDelegate as PopNavigatorRouterDelegateMixin<Object>;
        final navigator = delegate.navigatorKey!.currentState!;
        if (navigator.canPop()) navigator.pop('saved');
      case 'draft':
        list.currentState!.increment();
      case 'captureNotification':
        savedNotification = notifications.latest!;
      case 'replayNotification':
        unawaited(
          (router.routeInformationProvider! as WidgetsBindingObserver)
              .didPushRouteInformation(savedNotification!),
        );
    }
  }

  Widget screen(String title) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Wrap(
      children: [
        for (final action in ['list', 'push', 'nested', 'replace', 'pop'])
          TextButton(onPressed: () => act(action), child: Text(action)),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(notifications);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _action = ((JSString value) => act(value.toDart)).toJS;
      _snapshot = (() => jsonEncode({
        'route': router.location.toString(),
        'draft': list.currentState?.draft,
        'mount': list.currentState?.mount,
        'results': results,
        'waiting': _gate != null,
        'traversals': _nativeCalls?.toDartInt ?? 0,
        'strategyGoCalls': _traversals,
        'errors': _errors,
        'requestedDuringNativeMove': requestedDuringNativeMove,
      }).toJS).toJS;
    });
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(notifications);
    router.dispose();
    super.dispose();
  }
}

class _List extends StatefulWidget {
  const _List({required this.action, super.key});
  final void Function(String) action;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  static int mounts = 0;
  final int mount = ++mounts;
  int draft = 0;

  void increment() => setState(() => draft++);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Posts: author 7')),
    body: Column(
      children: [
        Text('Unsaved draft $draft'),
        for (final action in ['draft', 'push', 'nested'])
          TextButton(
            onPressed: () => widget.action(action),
            child: Text(action),
          ),
      ],
    ),
  );
}
