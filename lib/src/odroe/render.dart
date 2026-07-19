// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import '../document/renderer.dart';
import '../query/client.dart';
import '../query/hydration.dart';
import '../rpc/serializer.dart';
import '../router/codec.dart';
import '../router/match.dart';
import '../server/context.dart';
import '../server/http.dart';

typedef Renderer = FutureOr<ServerResponse> Function(RenderContext context);

/// Data available to a first-screen renderer.
final class RenderContext {
  const RenderContext({
    required this.request,
    required this.matches,
    required this.loads,
    required this.query,
    required this.serializer,
  });

  final RequestContext request;
  final RouteMatches matches;
  final Map<Object, RouteLoadResult> loads;
  final QueryClient query;
  final Serializer serializer;
}

/// Renders semantic HTML and, for Flutter routes, the hydration handoff.
final class DocumentRenderer {
  const DocumentRenderer({this.flutterBootstrap, this.baseHref});

  final String? flutterBootstrap;
  final String? baseHref;

  Future<ServerResponse> call(RenderContext context) async {
    final accept =
        context.request.request.headers.value('accept')?.toLowerCase() ?? '*/*';
    final wantsJson =
        accept.contains('application/json') && !accept.contains('text/html');
    if (wantsJson) {
      final state = _dehydrate(context);
      final payload = _payload(context, state);
      if (!state.queries.any((query) => query.pending != null)) {
        return ServerResponse.json(payload);
      }
      return ServerResponse(
        headers: Headers.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
        body: _jsonHandoff(payload, _pendingFrames(context, state)),
      );
    }

    final documents = await context.matches.buildDocuments(context.loads);
    final document = resolveDocument(documents);
    final bootstrap = context.matches.routes.last.hasFlutterPage
        ? flutterBootstrap
        : null;
    if (bootstrap == null) {
      return ServerResponse.html(
        '${renderDocumentStart(document)}</body></html>',
      );
    }

    final state = _dehydrate(context);
    final initial = _escapeScript(jsonEncode(_payload(context, state)));
    return ServerResponse(
      headers: Headers.single(<String, String>{
        'content-type': 'text/html; charset=utf-8',
      }),
      body: _htmlHandoff(
        renderDocumentStart(document, baseHref: baseHref),
        initial,
        bootstrap,
        _pendingFrames(context, state),
      ),
    );
  }

  DehydratedState _dehydrate(RenderContext context) => dehydrate(
    context.query,
    serializeData: context.serializer.encode,
    includePending: true,
  );

  Map<String, Object?> _payload(RenderContext context, DehydratedState state) =>
      <String, Object?>{
        'version': 1,
        'location': context.matches.location.toString(),
        'loads': context.matches.routes
            .map((route) => context.loads[route.identity]!)
            .map((result) => _encodeLoad(result, context.serializer))
            .toList(growable: false),
        'query': state.toJson(),
      };

  Map<String, Object?> _encodeLoad(
    RouteLoadResult result,
    Serializer serializer,
  ) => result.data is NoData
      ? const <String, Object?>{'type': 'noData'}
      : <String, Object?>{
          'type': 'data',
          'data': serializer.encode(result.data),
        };

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
      '$initial</script><script src="${htmlEscape.convert(bootstrap)}" '
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
    RenderContext context,
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
          final now = context.query.scheduler.now();
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
          final now = context.query.scheduler.now();
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
