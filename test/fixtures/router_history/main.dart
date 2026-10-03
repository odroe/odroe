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

/// A real application: browser tests call the same actions as its controls.
void main() {
  if (!(_useHash?.toDart ?? false)) usePathUrlStrategy();
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
  late final router = AppRouter(
    routes: [
      _home.page(build: (_) => screen('Home')),
      _posts
          .page(
            build: (_) => _List(key: list, action: act),
          )
          .withChildren([_edit.page(build: (_) => screen('Edit post'))]),
      _post.page(build: (_) => screen('Post')),
    ],
  );

  void act(String action) {
    switch (action) {
      case 'list':
        router.go(_posts.to(search: 7));
      case 'push':
        router.push<String>(_post.to(params: 1)).then(results.add);
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
        delegate.navigatorKey!.currentState!.pop('saved');
      case 'draft':
        list.currentState!.increment();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _action = ((JSString value) => act(value.toDart)).toJS;
      _snapshot = (() => jsonEncode({
        'route': router.location.toString(),
        'draft': list.currentState?.draft,
        'mount': list.currentState?.mount,
        'results': results,
      }).toJS).toJS;
    });
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);

  @override
  void dispose() {
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
