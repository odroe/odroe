import 'dart:async';
import 'dart:convert';

import 'package:odroe/document.dart';
import 'package:odroe/query.dart';
import 'package:odroe/router.dart';
import 'package:odroe/server.dart';
import 'package:test/test.dart';

void main() {
  test('hybrid renderer leaves document-only routes as pure HTML', () async {
    final route = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).document((_) => const RouteDocument(title: 'Document only'));
    final app = Server(
      routes: <RouteNode>[route],
      renderer: const DocumentRenderer(
        flutterBootstrap: '/flutter_bootstrap.js',
        baseHref: '/',
      ).call,
    );

    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );
    final html = await response.readText();

    expect(html, contains('<title>Document only</title>'));
    expect(html, isNot(contains('<base')));
    expect(html, isNot(contains('__odroe_state__')));
    expect(html, isNot(contains('flutter_bootstrap.js')));

    final hybrid = Server(
      routes: <RouteNode>[route],
      flutterRoutes: <RouteNode>[route],
      renderer: const DocumentRenderer(
        flutterBootstrap: '/flutter_bootstrap.js',
        baseHref: '/',
      ).call,
    );
    final hybridResponse = await hybrid.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );
    final hybridHtml = await hybridResponse.readText();
    expect(hybridHtml, contains('src="/flutter_bootstrap.js"'));
    expect(hybridHtml, isNot(contains('&#47;')));
  });

  test('pending Query state streams after the initial handoff', () async {
    final pending = Completer<int>();
    final options = QueryOptions<int>(
      key: QueryKey('deferred'),
      query: (_) => pending.future,
    );
    final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
      load: (context) {
        unawaited(context.read(queryClientKey).fetchQuery(options));
        return const NoData();
      },
    );
    final app = Server(
      routes: <RouteNode>[route],
      modules: () => [QueryClientModule.server()],
      renderer: (context) {
        final query = context.request.read(queryClientKey);
        final state = dehydrate(query, includePending: true);
        expect(state.queries, hasLength(1));
        expect(state.queries.single.pending, isNotNull);
        return const DocumentRenderer().call(context);
      },
    );
    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'application/json'}),
      ),
    );

    expect(response.status, 200);
    expect(
      response.headers.value('content-type'),
      'application/x-ndjson; charset=utf-8',
    );
    final lines = StreamIterator<String>(
      response.body.transform(utf8.decoder).transform(const LineSplitter()),
    );
    expect(await lines.moveNext(), isTrue);
    final initial = Map<String, Object?>.from(jsonDecode(lines.current) as Map);
    expect(initial['type'], 'initial');
    final initialData = Map<String, Object?>.from(initial['data']! as Map);
    expect(initialData['location'], '/');

    pending.complete(7);
    expect(await lines.moveNext(), isTrue);
    final update = Map<String, Object?>.from(jsonDecode(lines.current) as Map);
    expect(update['type'], 'query');
    final query = Map<String, Object?>.from(update['query']! as Map);
    final state = Map<String, Object?>.from(query['state']! as Map);
    expect(state['status'], 'success');
    expect(state['data'], 7);
    expect(await lines.moveNext(), isFalse);
  });
}
