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

  test('completed Query data uses the custom server serializer', () async {
    const value = _HandoffValue(42);
    final adapter = _HandoffValueAdapter();
    final serializer = Serializer(adapters: [adapter]);
    final options = QueryOptions<_HandoffValue>(
      key: QueryKey('completed-custom'),
      query: (_) async => value,
    );
    final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
      load: (context) async {
        await context.read(queryClientKey).fetchQuery(options);
        return const NoData();
      },
    );
    final app = Server(
      routes: <RouteNode>[route],
      flutterRoutes: <RouteNode>[route],
      modules: () => [QueryClientModule.server()],
      renderer: const DocumentRenderer(
        flutterBootstrap: '/flutter_bootstrap.js',
      ).call,
      serializer: serializer,
    );

    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'application/json'}),
      ),
    );
    final payload = Map<String, Object?>.from(
      jsonDecode(await response.readText()) as Map,
    );
    final query = Map<String, Object?>.from(payload['query']! as Map);
    final queries = query['queries']! as List;
    final dehydrated = Map<String, Object?>.from(queries.single as Map);
    final state = Map<String, Object?>.from(dehydrated['state']! as Map);

    expect(state['data'], <String, Object?>{
      r'$type': 'HandoffValue',
      r'$value': 42,
    });
    expect(adapter.encodeCalls, 1);
    final hydrated = QueryClient();
    hydrate(
      hydrated,
      DehydratedState.fromJson(query),
      deserializeData: serializer.decode,
    );
    expect(hydrated.getQueryData<_HandoffValue>(options.key), value);

    final htmlResponse = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'text/html'}),
      ),
    );
    expect(await htmlResponse.readText(), contains(r'"$type":"HandoffValue"'));
    expect(adapter.encodeCalls, 2);
  });

  test('pending Query state streams after the initial handoff', () async {
    final value = DateTime.utc(2026, 8, 1, 5, 6, 7, 8, 9);
    final pending = Completer<DateTime>();
    final options = QueryOptions<DateTime>(
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
      renderer: const DocumentRenderer().call,
    );
    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'application/json'}),
      ),
    );

    expect(response.status, 200);
    expect(response.headers.value('vary'), 'Accept');
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
    final hydrated = QueryClient();
    final serializer = Serializer();
    hydrate(
      hydrated,
      DehydratedState.fromJson(
        Map<String, Object?>.from(initialData['query']! as Map),
      ),
      deserializeData: serializer.decode,
    );

    pending.complete(value);
    expect(await lines.moveNext(), isTrue);
    final update = Map<String, Object?>.from(jsonDecode(lines.current) as Map);
    expect(update['type'], 'query');
    final query = Map<String, Object?>.from(update['query']! as Map);
    final state = Map<String, Object?>.from(query['state']! as Map);
    expect(state['status'], 'success');
    expect(state['data'], <String, Object?>{
      r'$type': 'DateTime',
      r'$value': '2026-08-01T05:06:07.008009Z',
    });
    hydrate(
      hydrated,
      DehydratedState(
        queries: <DehydratedQuery>[DehydratedQuery.fromJson(query)],
        mutations: const <DehydratedMutation>[],
      ),
      deserializeData: serializer.decode,
    );
    expect(hydrated.getQueryData<DateTime>(options.key), value);
    expect(await lines.moveNext(), isFalse);
  });

  test('pending Query serialization failures stay unexpected', () async {
    final pending = Completer<_HandoffValue>();
    final options = QueryOptions<_HandoffValue>(
      key: QueryKey('unsupported-pending'),
      query: (_) => pending.future,
    );
    final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
      load: (context) {
        unawaited(context.read(queryClientKey).fetchQuery(options));
        return const NoData();
      },
    );
    final reported = Completer<Object>();
    final app = Server(
      routes: <RouteNode>[route],
      modules: () => [QueryClientModule.server()],
      renderer: const DocumentRenderer().call,
      onError: (_, error, _) {
        if (!reported.isCompleted) reported.complete(error);
      },
    );
    final response = await app.handle(
      ServerRequest.bytes(
        method: HttpMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: Headers.single(<String, String>{'accept': 'application/json'}),
      ),
    );
    final lines = StreamIterator<String>(
      response.body.transform(utf8.decoder).transform(const LineSplitter()),
    );

    expect(await lines.moveNext(), isTrue);
    pending.complete(const _HandoffValue(7));
    await expectLater(lines.moveNext(), throwsA(isA<ArgumentError>()));
    expect(
      await reported.future.timeout(const Duration(seconds: 1)),
      isA<ArgumentError>(),
    );
  });
}

final class _HandoffValue {
  const _HandoffValue(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is _HandoffValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class _HandoffValueAdapter
    implements SerializationAdapter<_HandoffValue> {
  int encodeCalls = 0;

  @override
  String get tag => 'HandoffValue';

  @override
  bool canEncode(Object value) => value is _HandoffValue;

  @override
  Object? encode(_HandoffValue value, Serializer serializer) {
    encodeCalls++;
    return value.value;
  }

  @override
  _HandoffValue decode(Object? value, Serializer serializer) =>
      _HandoffValue(value! as int);
}
