import 'dart:async';
import 'dart:convert';

import 'package:odroe/start.dart';
import 'package:test/test.dart';

typedef _Params = ({int userId});

void main() {
  test(
    'public server routes use typed params and HEAD falls back to GET',
    () async {
      final definition = AppRoute<_Params, NoSearch, NoData>(
        path: '/users/[userId]',
        params: PathParams<_Params>.codec(
          decode: (input) => (userId: input.requiredInt('userId')),
          encode: (value, output) => output.integer('userId', value.userId),
        ),
      );
      final route = definition.server(
        handlers: <StartMethod, ServerRouteHandler<_Params, NoSearch>>{
          StartMethod.get: (context) => StartResponse.json(<String, Object?>{
            'id': context.params.userId,
          }),
        },
      );
      final app = StartApplication(routes: <AnyAppRoute>[route]);

      final get = await app.handle(
        StartRequest.bytes(
          method: StartMethod.get,
          uri: Uri.parse('http://localhost/users/42'),
        ),
      );
      expect(jsonDecode(await get.readText()), <String, Object?>{'id': 42});

      final head = await app.handle(
        StartRequest.bytes(
          method: StartMethod.head,
          uri: Uri.parse('http://localhost/users/42'),
        ),
      );
      expect(head.status, 200);
      expect(await head.readBytes(), isEmpty);
    },
  );

  test('app route loaders hand Query state to the default renderer', () async {
    var calls = 0;
    final data = QueryOptions<int>(
      key: QueryKey('home'),
      query: (_) => ++calls,
    );
    final definition = AppRoute<NoParams, NoSearch, int>(path: '/');
    final route = definition.server(
      load: (context) => context.query.ensureQueryData(data),
    );
    final app = StartApplication(routes: <AnyAppRoute>[route]);

    final response = await app.handle(
      StartRequest.bytes(
        method: StartMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: StartHeaders.single(<String, String>{
          'accept': 'application/json',
        }),
      ),
    );
    final payload =
        jsonDecode(await response.readText()) as Map<String, Object?>;

    expect(calls, 1);
    expect(payload['loads'], <Object?>[1]);
    final query = payload['query']! as Map<String, Object?>;
    expect(query['queries'], isNotEmpty);
  });

  test('pending Query state streams after the initial handoff', () async {
    final pending = Completer<int>();
    final options = QueryOptions<int>(
      key: QueryKey('deferred'),
      query: (_) => pending.future,
    );
    final route = AppRoute<NoParams, NoSearch, NoData>(path: '/').server(
      load: (context) {
        unawaited(context.query.fetchQuery(options));
        return const NoData();
      },
    );
    final app = StartApplication(
      routes: <AnyAppRoute>[route],
      renderer: (context) {
        expect(context.dehydrated.queries, hasLength(1));
        expect(context.dehydrated.queries.single.pending, isNotNull);
        return const StartHandoffRenderer().call(context);
      },
    );
    final response = await app.handle(
      StartRequest.bytes(
        method: StartMethod.get,
        uri: Uri.parse('http://localhost/'),
        headers: StartHeaders.single(<String, String>{
          'accept': 'application/json',
        }),
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
    final clientQuery = QueryClient();
    final handoff = StartHandoffClient(query: clientQuery);
    handoff.apply(initial);
    expect(clientQuery.getQueryData<int>(options.key), isNull);

    pending.complete(7);
    expect(await lines.moveNext(), isTrue);
    final update = Map<String, Object?>.from(jsonDecode(lines.current) as Map);
    handoff.apply(update);
    expect(clientQuery.getQueryData<int>(options.key), 7);
    expect(await lines.moveNext(), isFalse);
  });
}
