// ignore_for_file: public_member_api_docs

import '../query/client.dart';
import '../query/hydration.dart';
import 'serialization.dart';

/// Applies initial and streamed Start frames to one application QueryClient.
final class StartHandoffClient {
  StartHandoffClient({required this.query, StartSerializer? serializer})
    : serializer = serializer ?? StartSerializer();

  final QueryClient query;
  final StartSerializer serializer;

  Uri? location;
  List<Object?> loads = const <Object?>[];

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
        throw FormatException('Unknown Start handoff frame: ${frame['type']}');
    }
  }

  void _applyInitial(Map<String, Object?> data) {
    location = Uri.parse(data['location']! as String);
    loads = (data['loads'] as List? ?? const <Object?>[])
        .map(serializer.decode)
        .toList(growable: false);
    hydrate(
      query,
      DehydratedState.fromJson(
        Map<String, Object?>.from(data['query']! as Map),
      ),
      deserializeData: serializer.decode,
    );
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
