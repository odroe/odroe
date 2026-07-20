import 'dart:async';

import '../router/load.dart';
import '../router/match.dart';
import '../rpc/serializer.dart';
import 'context.dart';
import 'http.dart';

/// Renders one fully matched and loaded route branch.
typedef Renderer = FutureOr<ServerResponse> Function(RenderContext context);

/// Data available to a route renderer.
final class RenderContext {
  /// Creates renderer input.
  const RenderContext({
    required this.request,
    required this.matches,
    required this.loads,
    required this.serializer,
    required this.flutter,
  });

  /// Request-scoped application and HTTP state.
  final RequestContext request;

  /// Active route branch.
  final RouteMatches matches;

  /// Loader results keyed by route identity.
  final Map<Object, RouteLoadResult> loads;

  /// Serializer selected by the server.
  final Serializer serializer;

  /// Whether the generated client tree contains a Flutter page for the leaf.
  final bool flutter;
}
