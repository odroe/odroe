import 'dart:async';
import 'dart:convert';

import '../query/client.dart';
import '../query/hydration.dart';
import '../query/module.dart';
import '../router/codec.dart';
import '../router/load.dart';
import '../server/http.dart';
import '../server/render.dart';
import 'renderer.dart';
import 'route.dart';

/// Renders semantic HTML and optional Flutter hydration state.
final class DocumentRenderer {
  /// Creates a document renderer.
  const DocumentRenderer({this.flutterBootstrap, this.baseHref});

  /// Flutter bootstrap URL used for hybrid routes.
  final String? flutterBootstrap;

  /// Base URL overriding route document declarations.
  final String? baseHref;

  /// Renders one loaded route branch.
  Future<ServerResponse> call(RenderContext context) async {
    final accept =
        context.request.request.headers.value('accept')?.toLowerCase() ?? '*/*';
    final wantsJson =
        accept.contains('application/json') && !accept.contains('text/html');
    final query = context.request.maybe(queryClientKey);
    final state = query == null ? null : _dehydrate(query);
    final payload = _payload(context, state);

    if (wantsJson) {
      if (state == null ||
          !state.queries.any((query) => query.pending != null)) {
        return ServerResponse.json(payload);
      }
      return ServerResponse(
        headers: Headers.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
        body: _jsonHandoff(payload, _pendingFrames(query!, state)),
      );
    }

    final documents = await buildDocuments(context.matches, context.loads);
    final document = resolveDocument(documents);
    final bootstrap = context.flutter ? flutterBootstrap : null;
    if (bootstrap == null) {
      return ServerResponse.html(
        '${renderDocumentStart(document)}</body></html>',
      );
    }

    final initial = _escapeScript(jsonEncode(payload));
    return ServerResponse(
      headers: Headers.single(<String, String>{
        'content-type': 'text/html; charset=utf-8',
      }),
      body: _htmlHandoff(
        renderDocumentStart(document, baseHref: baseHref),
        initial,
        bootstrap,
        state == null
            ? const Stream<Map<String, Object?>>.empty()
            : _pendingFrames(query!, state),
      ),
    );
  }

  DehydratedState _dehydrate(QueryClient query) =>
      dehydrate(query, includePending: true);

  Map<String, Object?> _payload(
    RenderContext context,
    DehydratedState? state,
  ) => <String, Object?>{
    'version': 1,
    'location': context.matches.location.toString(),
    'loads': context.matches.routes
        .map((route) => context.loads[route.identity]!)
        .map((result) => _encodeLoad(result, context.serializer.encode))
        .toList(growable: false),
    if (state != null) 'query': state.toJson(),
  };

  Map<String, Object?> _encodeLoad(
    RouteLoadResult result,
    Object? Function(Object?) encode,
  ) => !result.isLoaded
      ? const <String, Object?>{'type': 'client'}
      : result.data is NoData
      ? const <String, Object?>{'type': 'noData'}
      : <String, Object?>{'type': 'data', 'data': encode(result.data)};

  Stream<List<int>> _jsonHandoff(
    Map<String, Object?> initial,
    Stream<Map<String, Object?>> pending,
  ) async* {
    yield utf8.encode(
      '${jsonEncode(<String, Object?>{'version': 1, 'type': 'initial', 'data': initial})}\n',
    );
    await for (final frame in pending) {
      yield utf8.encode('${jsonEncode(frame)}\n');
    }
  }

  Stream<List<int>> _htmlHandoff(
    String document,
    String initial,
    String bootstrap,
    Stream<Map<String, Object?>> pending,
  ) async* {
    yield utf8.encode(
      '$document<script id="__odroe_state__" type="application/json">'
      '$initial</script><script src="${_escapeAttribute(bootstrap)}" '
      'async></script>',
    );
    await for (final frame in pending) {
      yield utf8.encode(
        '<script type="application/json" data-odroe-frame>'
        '${_escapeScript(jsonEncode(frame))}</script>',
      );
    }
    yield utf8.encode('</body></html>');
  }

  Stream<Map<String, Object?>> _pendingFrames(
    QueryClient query,
    DehydratedState state,
  ) {
    final pending = state.queries
        .where((query) => query.pending != null)
        .toList(growable: false);
    if (pending.isEmpty) return const Stream<Map<String, Object?>>.empty();

    late final StreamController<Map<String, Object?>> controller;
    var remaining = pending.length;
    void completeOne() {
      if (--remaining == 0) controller.close();
    }

    controller = StreamController<Map<String, Object?>>(sync: true);
    for (final item in pending) {
      item.pending!.then<void>(
        (data) {
          final now = query.scheduler.now();
          controller.add(<String, Object?>{
            'version': 1,
            'type': 'query',
            'query': DehydratedQuery(
              key: item.key,
              state: <String, Object?>{
                ...item.state,
                'status': 'success',
                'hasData': true,
                'data': data,
                'dataUpdatedAt': now.millisecondsSinceEpoch,
                'dataUpdateCount': (item.state['dataUpdateCount']! as int) + 1,
                'fetchFailureCount': 0,
                'isInvalidated': false,
              },
              dehydratedAt: now,
              meta: item.meta,
            ).toJson(),
          });
          completeOne();
        },
        onError: (Object _, StackTrace _) {
          final now = query.scheduler.now();
          controller.add(<String, Object?>{
            'version': 1,
            'type': 'queryError',
            'key': item.key.toJson(),
            'message': 'Query failed.',
            'query': DehydratedQuery(
              key: item.key,
              state: <String, Object?>{
                ...item.state,
                'status': 'error',
                'error': 'Query failed.',
                'errorUpdatedAt': now.millisecondsSinceEpoch,
                'errorUpdateCount':
                    (item.state['errorUpdateCount']! as int) + 1,
                'fetchFailureCount':
                    (item.state['fetchFailureCount']! as int) + 1,
              },
              dehydratedAt: now,
              meta: item.meta,
            ).toJson(),
          });
          completeOne();
        },
      );
    }
    return controller.stream;
  }
}

String _escapeScript(String value) => value.replaceAllMapped(
  RegExp(r'</script', caseSensitive: false),
  (_) => r'<\/script',
);

String _escapeAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
