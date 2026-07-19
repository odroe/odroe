// ignore_for_file: public_member_api_docs

import '../query/client.dart';
import '../query/hydration.dart';
import '../rpc/serializer.dart';
import '../router/codec.dart';
import '../router/match.dart';

/// Applies initial and streamed server frames to one QueryClient.
final class Handoff {
  Handoff({required this.query, Serializer? serializer})
    : serializer = serializer ?? Serializer();

  final QueryClient query;
  final Serializer serializer;

  Uri? location;
  List<RouteLoadResult> loads = const <RouteLoadResult>[];

  void apply(Map<String, Object?> frame) {
    switch (frame['type']) {
      case 'initial':
        _applyInitial(Map<String, Object?>.from(frame['data']! as Map));
      case 'query':
        _hydrateQuery(Map<String, Object?>.from(frame['query']! as Map));
      case 'queryError':
        if (frame['query'] case final Map queryState) {
          _hydrateQuery(Map<String, Object?>.from(queryState));
        }
        return;
      default:
        if (frame.containsKey('query') && frame.containsKey('location')) {
          _applyInitial(frame);
          return;
        }
        throw FormatException('Unknown Odroe handoff frame: ${frame['type']}');
    }
  }

  void _applyInitial(Map<String, Object?> data) {
    location = Uri.parse(data['location']! as String);
    loads = (data['loads'] as List? ?? const <Object?>[])
        .map(_decodeLoad)
        .toList(growable: false);
    hydrate(
      query,
      DehydratedState.fromJson(
        Map<String, Object?>.from(data['query']! as Map),
      ),
      deserializeData: serializer.decode,
    );
  }

  RouteLoadResult _decodeLoad(Object? value) {
    if (value case final Map encoded) {
      switch (encoded['type']) {
        case 'noData':
          return const RouteLoadResult.data(NoData());
        case 'data':
          return RouteLoadResult.data(serializer.decode(encoded['data']));
      }
    }
    return RouteLoadResult.data(serializer.decode(value));
  }

  void _hydrateQuery(Map<String, Object?> queryState) {
    hydrate(
      query,
      DehydratedState(
        queries: <DehydratedQuery>[DehydratedQuery.fromJson(queryState)],
        mutations: const <DehydratedMutation>[],
      ),
      deserializeData: serializer.decode,
    );
  }
}
