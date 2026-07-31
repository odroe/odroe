import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe_example/routes.dart';

void main() {
  testWidgets('generated RPC completes inside the Flutter event loop', (
    tester,
  ) async {
    final transport = _ExampleTransport();
    final client = RpcClient(
      baseUri: Uri.parse('https://api.example.com'),
      transport: transport,
    );
    final cancelled = Completer<void>();
    final value = await routes.posts.postId.readTitle(
      client,
      42,
      cancelled: cancelled.future,
    );

    expect(value, 'Post 42', reason: 'requests=${transport.requests.length}');
  });

  testWidgets('malformed stream EOF fails inside the Flutter event loop', (
    tester,
  ) async {
    final failure = await _streamFailure(
      tester,
      ServerResponse.bytes(const <int>[
        0xff,
      ], contentType: 'application/x-ndjson; charset=utf-8'),
    );

    expect(failure, isA<RpcProtocolException>());
  });

  testWidgets('stream body errors complete inside the Flutter event loop', (
    tester,
  ) async {
    final failure = await _streamFailure(
      tester,
      ServerResponse(
        headers: Headers.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
        body: Stream<List<int>>.error(StateError('response failed')),
      ),
    );

    expect(failure, isA<StateError>());
  });

  testWidgets('post page loads through Query and its generated RPC ref', (
    tester,
  ) async {
    final transport = await _pumpPostPage(tester);

    expect(find.text('Post 42; preview=true; tags=one,two'), findsOneWidget);
    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.method, HttpMethod.get);
    expect(
      transport.requests.single.uri.path,
      '/__odroe/functions/posts.read-title',
    );
    expect(transport.requests.single.cancelled, isNotNull);
  });

  testWidgets('post page retries a failed RPC query', (tester) async {
    final transport = await _pumpPostPage(tester, failures: 1);

    expect(find.text('Unable to load post.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(transport.requests, hasLength(1));

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await _pumpUntil(tester, find.text('Post 42; preview=true; tags=one,two'));

    expect(find.text('Post 42; preview=true; tags=one,two'), findsOneWidget);
    expect(transport.requests, hasLength(2));
  });
}

final class _ExampleTransport implements RpcTransport {
  _ExampleTransport({int failures = 0}) : _failures = failures;

  final List<ServerRequest> requests = <ServerRequest>[];
  int _failures;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    requests.add(request);
    if (_failures > 0) {
      _failures--;
      throw StateError('Example RPC failure.');
    }
    final payload =
        jsonDecode(request.uri.queryParameters['payload']!)
            as Map<String, Object?>;
    return ServerResponse.json(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': 'Post ${payload['data']}',
    });
  }
}

final class _StaticResponseTransport implements RpcTransport {
  const _StaticResponseTransport(this.response);

  final ServerResponse response;

  @override
  Future<ServerResponse> send(ServerRequest request) async => response;
}

Future<Object?> _streamFailure(
  WidgetTester tester,
  ServerResponse response,
) async {
  final client = RpcClient(
    baseUri: Uri.parse('https://api.example.com'),
    transport: _StaticResponseTransport(response),
  );
  final cancelled = Completer<void>();
  final stream = await const ServerStreamFunctionRef<NoServerInput, Object?>(
    id: 'watch',
  )(client, const NoServerInput(), cancelled: cancelled.future);
  Object? failure;
  var completed = false;
  unawaited(
    stream.toList().then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace _) {
        failure = error;
        completed = true;
      },
    ),
  );

  await tester.pump();

  expect(completed, isTrue);
  return failure;
}

Future<_ExampleTransport> _pumpPostPage(
  WidgetTester tester, {
  int failures = 0,
}) async {
  final transport = _ExampleTransport(failures: failures);
  final query = QueryClient(
    options: const QueryClientOptions(
      queries: QueryPolicy(gcTime: Duration.zero, retry: QueryRetry.never()),
    ),
  );
  addTearDown(query.clear);
  final rpc = RpcClient(
    baseUri: Uri.parse('https://api.example.com'),
    transport: transport,
  );

  await tester.pumpWidget(
    App(
      modules: <Module>[
        QueryModule(client: query),
        RpcModule(rpc),
        RouterModule(
          routes: routeTree,
          initialLocation: Uri.parse(
            '/posts/42?preview=true&tags=one&tags=two',
          ),
        ),
      ],
      builder: (app) => MaterialApp.router(routerConfig: app.read(routerKey)),
    ),
  );
  await tester.pump();
  await _pumpUntil(
    tester,
    failures == 0
        ? find.text('Post 42; preview=true; tags=one,two')
        : find.text('Unable to load post.'),
    reason: () =>
        'requests=${transport.requests.length}; '
        'state=${query.getQueryState<String>(QueryKey('post-title', <Object?>[42]))?.status}; '
        'fetch=${query.getQueryState<String>(QueryKey('post-title', <Object?>[42]))?.fetchStatus}; '
        'error=${query.getQueryState<String>(QueryKey('post-title', <Object?>[42]))?.error}',
  );
  return transport;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  String Function()? reason,
}) async {
  for (var frame = 0; frame < 100 && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(finder, findsOneWidget, reason: reason?.call());
}
