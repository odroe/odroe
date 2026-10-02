import 'dart:async';
import 'dart:io';

import 'package:odroe/rpc.dart';
import 'package:odroe/server_io.dart';

// Shared business protocol; the generator already supports these record aliases.
typedef Post = ({int id, String title});
typedef PageInput = ({int cursor, int limit});
typedef PostPage = ({List<Post> items, int? nextCursor});
typedef PostInput = ({int id});
typedef SaveInput = ({int id, String title});

Post decodePost(Object? value) {
  final map = value as Map;
  return (id: map['id'] as int, title: map['title'] as String);
}

Object? encodePost(Post value) => {'id': value.id, 'title': value.title};
PageInput decodePageInput(Object? value) {
  final map = value as Map;
  return (cursor: map['cursor'] as int, limit: map['limit'] as int);
}

SaveInput decodeSaveInput(Object? value) {
  final map = value as Map;
  return (id: map['id'] as int, title: map['title'] as String);
}

final listPosts = ServerFunctionRef<PageInput, PostPage>(
  id: 'posts.list',
  encodeInput: (input) => {'cursor': input.cursor, 'limit': input.limit},
  decodeOutput: (value) {
    final map = value as Map;
    return (
      items: (map['items'] as List).map(decodePost).toList(),
      nextCursor: map['nextCursor'] as int?,
    );
  },
);
final getPost = ServerFunctionRef<PostInput, Post>(
  id: 'posts.get',
  encodeInput: (input) => {'id': input.id},
  decodeOutput: decodePost,
);
final savePost = ServerFunctionRef<SaveInput, Post>(
  id: 'posts.save',
  encodeInput: (input) => {'id': input.id, 'title': input.title},
  decodeOutput: decodePost,
);

// Real HTTP fixture, also used by the runnable consumer. Each endpoint+account
// has its own store. Gates make switch/cancel/failure tests deterministic.
final class PostsServer {
  final calls =
      <({String backend, String account, String id, Object? input})>[];
  final stores = <String, List<Post>>{};
  final cancelled = <String>[];
  final completed = <String>[];
  final gates = <String, Completer<void>>{};
  final failures = <String>{};
  final requests = <String, ServerRequest>{};
  final runtimes = <Server>[];
  late HttpServer http;

  String callId(String backend, String account, String id) =>
      '$backend/$account/$id';
  List<Post> store(String backend, String account) => stores.putIfAbsent(
    '$backend/$account',
    () => List.generate(
      5,
      (i) => (id: i + 1, title: '$backend-$account Post ${i + 1}'),
    ),
  );

  Future<void> before(
    String backend,
    ServerFunctionContext<dynamic> context,
  ) async {
    final account =
        context.request.request.headers.value('x-account') ?? 'anonymous';
    final key = callId(backend, account, context.id);
    final request = context.request.request;
    calls.add((
      backend: backend,
      account: account,
      id: context.id,
      input: context.data,
    ));
    requests[key] = request;
    unawaited(request.cancelled?.then((_) => cancelled.add(key)));
    await gates[key]?.future;
    if (failures.contains(key)) {
      throw const HttpError(503, 'Injected read failure');
    }
    completed.add(key);
  }

  Future<void> start() async {
    for (final backend in ['a', 'b']) {
      runtimes.add(
        Server(
          routes: const [],
          functionPath: '/$backend/rpc',
          exposeErrors: true,
          functions: {
            listPosts.id: ServerFunctionBinding(
              ServerFunction<PageInput, PostPage>(
                decodeInput: decodePageInput,
                handler: (context) async {
                  await before(backend, context);
                  final account = context.request.request.headers.value(
                    'x-account',
                  )!;
                  final input = context.data;
                  final posts = store(backend, account);
                  final end = (input.cursor + input.limit).clamp(
                    0,
                    posts.length,
                  );
                  return (
                    items: posts.sublist(input.cursor, end),
                    nextCursor: end < posts.length ? end : null,
                  );
                },
              ),
              encodeOutput: (value) {
                final page = value as PostPage;
                return {
                  'items': page.items.map(encodePost).toList(),
                  'nextCursor': page.nextCursor,
                };
              },
            ),
            getPost.id: ServerFunctionBinding(
              ServerFunction<PostInput, Post>(
                decodeInput: (value) => (id: (value as Map)['id'] as int),
                handler: (context) async {
                  await before(backend, context);
                  return store(
                    backend,
                    context.request.request.headers.value('x-account')!,
                  ).firstWhere((post) => post.id == context.data.id);
                },
              ),
              encodeOutput: (value) => encodePost(value as Post),
            ),
            savePost.id: ServerFunctionBinding(
              ServerFunction<SaveInput, Post>(
                decodeInput: decodeSaveInput,
                handler: (context) async {
                  await before(backend, context);
                  final input = context.data;
                  if (input.title.trim().isEmpty) {
                    throw const HttpError(422, 'Title is required');
                  }
                  final posts = store(
                    backend,
                    context.request.request.headers.value('x-account')!,
                  );
                  final index = posts.indexWhere((post) => post.id == input.id);
                  return posts[index] = (
                    id: input.id,
                    title: input.title.trim(),
                  );
                },
              ),
              encodeOutput: (value) => encodePost(value as Post),
            ),
          },
        ),
      );
    }
    http = await IoServer.bind(
      (request) =>
          runtimes[request.uri.path.startsWith('/b/') ? 1 : 0].handle(request),
      port: 0,
    );
  }

  Uri get origin => Uri.parse('http://127.0.0.1:${http.port}');
  Future<void> close() async {
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await IoServer.close(http, force: true);
    for (final runtime in runtimes) {
      await runtime.close();
    }
  }
}
