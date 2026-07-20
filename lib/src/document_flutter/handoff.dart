import '../query/client.dart';
import '../query/hydration.dart';
import '../router/codec.dart';
import '../router/load.dart';
import '../router_flutter/router.dart';
import '../rpc/serializer.dart';

/// Decodes initial and streamed server-rendering frames.
final class Handoff {
  /// Creates a handoff decoder.
  Handoff({Serializer? serializer}) : serializer = serializer ?? Serializer();

  /// Serializer used for loader and Query data.
  final Serializer serializer;

  /// Canonical server-rendered location.
  Uri? location;

  /// Server-rendered loader results in route order.
  List<RouteLoadResult> loads = const <RouteLoadResult>[];

  /// Converts current state into router initial state.
  RouterInitialState? get routerState {
    final current = location;
    return current == null
        ? null
        : RouterInitialState(location: current, loads: loads);
  }

  /// Applies one raw frame and optionally hydrates [query].
  void apply(Map<String, Object?> frame, {QueryClient? query}) {
    switch (frame['type']) {
      case 'initial':
        _applyInitial(Map<String, Object?>.from(frame['data']! as Map), query);
      case 'query':
        if (query != null) {
          _hydrateQuery(
            query,
            Map<String, Object?>.from(frame['query']! as Map),
          );
        }
      case 'queryError':
        if (query != null) {
          if (frame['query'] case final Map queryState) {
            _hydrateQuery(query, Map<String, Object?>.from(queryState));
          }
        }
      default:
        if (frame.containsKey('loads') && frame.containsKey('location')) {
          _applyInitial(frame, query);
          return;
        }
        throw FormatException('Unknown handoff frame: ${frame['type']}');
    }
  }

  void _applyInitial(Map<String, Object?> data, QueryClient? query) {
    location = Uri.parse(data['location']! as String);
    loads = (data['loads'] as List? ?? const <Object?>[])
        .map(_decodeLoad)
        .toList(growable: false);
    if (query != null) {
      if (data['query'] case final Map queryState) {
        hydrate(
          query,
          DehydratedState.fromJson(Map<String, Object?>.from(queryState)),
          deserializeData: serializer.decode,
        );
      }
    }
  }

  RouteLoadResult _decodeLoad(Object? value) {
    if (value case final Map encoded) {
      switch (encoded['type']) {
        case 'client':
          return const RouteLoadResult.client();
        case 'noData':
          return const RouteLoadResult.data(NoData());
        case 'data':
          return RouteLoadResult.data(serializer.decode(encoded['data']));
      }
    }
    return RouteLoadResult.data(serializer.decode(value));
  }

  void _hydrateQuery(QueryClient query, Map<String, Object?> queryState) {
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
