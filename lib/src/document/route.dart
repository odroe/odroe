import 'dart:async';

import '../app/binding.dart';
import '../app/context.dart';
import '../app/key.dart';
import '../router/codec.dart';
import '../router/load.dart';
import '../router/match.dart';
import '../router/route.dart';
import 'document.dart';

/// Typed params, search, and loader data for one active document route.
final class DocumentValues<P, S, D> {
  const DocumentValues._({
    required this.params,
    required this.search,
    required this.data,
  });

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// Loader data owned by the route.
  final D data;
}

final class _DocumentEntry {
  const _DocumentEntry({
    required this.route,
    required this.params,
    required this.search,
    required this.data,
  });

  final RouteNode route;
  final Object? params;
  final Object? search;
  final Object? data;
}

/// Loader data for the active document branch.
final class DocumentBranch {
  DocumentBranch._(this._entries);

  final List<_DocumentEntry> _entries;

  /// Returns typed values for an active route.
  DocumentValues<P, S, D>? match<P, S, D>(TypedRoute<P, S, D> route) {
    for (final entry in _entries) {
      if (!identical(entry.route.identity, route.identity)) continue;
      return DocumentValues<P, S, D>._(
        params: entry.params as P,
        search: entry.search as S,
        data: entry.data as D,
      );
    }
    return null;
  }
}

/// Typed input passed to a route document builder.
final class DocumentContext<P, S, D> {
  /// Creates document builder input.
  const DocumentContext({
    required this.app,
    required this.route,
    required this.params,
    required this.search,
    required this.data,
    required this.location,
    required this.branch,
  });

  /// The application context containing explicitly installed modules.
  final AppContext app;

  /// The route being rendered.
  final TypedRoute<P, S, D> route;

  /// Path parameters owned by the route.
  final P params;

  /// Search state owned by the route.
  final S search;

  /// Loader data owned by the route.
  final D data;

  /// Complete matched location.
  final Uri location;

  /// Loader data for the complete active branch.
  final DocumentBranch branch;

  /// Metadata declared by the neutral route.
  RouteMetadata get metadata => route.metadata;

  /// Reads an application service.
  T read<T extends Object>(ContextKey<T> key) => app.read(key);

  /// Reads an optional application service.
  T? maybe<T extends Object>(ContextKey<T> key) => app.maybe(key);

  /// Returns module bindings assignable to [T], in registration order.
  Iterable<T> bindings<T extends ModuleBinding>() => app.bindings<T>();

  /// Returns typed values for an active route.
  DocumentValues<MatchP, MatchS, MatchD>? match<MatchP, MatchS, MatchD>(
    TypedRoute<MatchP, MatchS, MatchD> route,
  ) => branch.match(route);
}

/// Builds semantic HTML for one active route.
typedef DocumentBuilder<P, S, D> =
    FutureOr<RouteDocument?> Function(DocumentContext<P, S, D> context);

abstract interface class _DocumentBinding {
  FutureOr<RouteDocument?> build(
    AppContext app,
    RouteNode route,
    RouteMatches matches,
    Object? data,
    DocumentBranch branch,
  );
}

final class _TypedDocumentBinding<P, S, D> implements _DocumentBinding {
  const _TypedDocumentBinding(this.builder);

  final DocumentBuilder<P, S, D> builder;

  @override
  FutureOr<RouteDocument?> build(
    AppContext app,
    RouteNode route,
    RouteMatches matches,
    Object? data,
    DocumentBranch branch,
  ) {
    final typed = route as TypedRoute<P, S, D>;
    final match = matches.match(typed)!;
    return builder(
      DocumentContext<P, S, D>(
        app: app,
        route: typed,
        params: match.params,
        search: match.search,
        data: data as D,
        location: matches.location,
        branch: branch,
      ),
    );
  }
}

const _documentCapability = RouteCapability<_DocumentBinding>('document');

/// Attaches semantic HTML generation to a neutral route definition.
extension AppRouteDocument<P, S, D> on AppRoute<P, S, D> {
  /// Returns the route with [builder] installed as an optional capability.
  AppRoute<P, S, D> document(DocumentBuilder<P, S, D> builder) =>
      withCapability(
        _documentCapability,
        _TypedDocumentBinding<P, S, D>(builder),
      );
}

/// Builds document fragments for a fully loaded route branch.
Future<List<RouteDocument>> buildDocuments(
  RouteMatches matches,
  Map<Object, RouteLoadResult> loads, {
  required AppContext app,
}) async {
  final entries = <_DocumentEntry>[];
  for (final route in matches.routes) {
    final load = loads[route.identity];
    if (load == null) {
      throw StateError('Missing loader result for route ${route.path}.');
    }
    if (load.isLoaded && !load.hasData) {
      Error.throwWithStackTrace(load.error!, load.stackTrace!);
    }
    final values = matches.branch.values(route)!;
    entries.add(
      _DocumentEntry(
        route: route,
        params: values.params,
        search: values.search,
        data: load.isLoaded ? load.data : const NoData(),
      ),
    );
  }
  final branch = DocumentBranch._(entries);
  final documents = <RouteDocument>[];
  for (final route in matches.routes) {
    final binding = route.capability(_documentCapability);
    final built = binding == null
        ? null
        : await binding.build(
            app,
            route,
            matches,
            loads[route.identity]!.isLoaded
                ? loads[route.identity]!.data
                : const NoData(),
            branch,
          );
    final document = _withMetadata(route.metadata, built);
    if (document != null) documents.add(document);
  }
  return List<RouteDocument>.unmodifiable(documents);
}

RouteDocument? _withMetadata(RouteMetadata metadata, RouteDocument? document) {
  final hasMetadata =
      metadata.title != null ||
      metadata.description != null ||
      metadata.canonical != null;
  if (document == null && !hasMetadata) return null;
  return RouteDocument(
    language: document?.language,
    baseHref: document?.baseHref,
    title: document?.title ?? metadata.title,
    description: document?.description ?? metadata.description,
    canonical: document?.canonical ?? metadata.canonical,
    meta: document?.meta ?? const <DocumentMeta>[],
    links: document?.links ?? const <DocumentLink>[],
    jsonLd: document?.jsonLd ?? const <Object?>[],
    htmlAttributes: document?.htmlAttributes ?? const <String, String?>{},
    bodyAttributes: document?.bodyAttributes ?? const <String, String?>{},
    body: document?.body,
  );
}
