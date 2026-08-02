import 'dart:convert';

/// A deterministic, serializable identity for one server-state resource.
final class QueryKey<T extends Object?> {
  /// Creates a key from a stable namespace and optional JSON-like parts.
  QueryKey(this.namespace, [Iterable<Object?> parts = const <Object?>[]])
    : parts = _freezeParts(parts) {
    if (namespace.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'Must not be empty.');
    }
    _encodedParts = List<String>.generate(
      this.parts.length,
      (index) => jsonEncode(this.parts[index]),
      growable: false,
    );
    final encodedNamespace = jsonEncode(namespace);
    _canonical = _encodedParts.isEmpty
        ? '[$encodedNamespace]'
        : '[$encodedNamespace,${_encodedParts.join(',')}]';
  }

  /// Restores a key from its JSON representation.
  factory QueryKey.fromJson(Object? value) {
    if (value is! List || value.isEmpty || value.first is! String) {
      throw FormatException('A query key must be a non-empty JSON array.');
    }
    return QueryKey<T>(value.first as String, value.skip(1));
  }

  /// Exact data type associated with this key.
  ///
  /// Runtime cache checks use this token instead of covariant generic checks.
  Type get dataType => T;

  /// Human-readable resource namespace.
  final String namespace;

  /// Ordered variables that distinguish resources in the namespace.
  final List<Object?> parts;

  late final String _canonical;
  late final List<String> _encodedParts;

  /// Stable canonical form used by caches and persistence.
  String get canonical => _canonical;

  /// Whether this key begins with [prefix].
  bool startsWith(QueryKey<Object?> prefix) {
    if (namespace != prefix.namespace || parts.length < prefix.parts.length) {
      return false;
    }
    for (var index = 0; index < prefix._encodedParts.length; index++) {
      if (_encodedParts[index] != prefix._encodedParts[index]) return false;
    }
    return true;
  }

  /// JSON representation used by hydration and persistence.
  List<Object?> toJson() => <Object?>[namespace, ...parts];

  @override
  bool operator ==(Object other) =>
      other is QueryKey<Object?> && other._canonical == _canonical;

  @override
  int get hashCode => _canonical.hashCode;

  @override
  String toString() => _canonical;
}

List<Object?> _freezeParts(Iterable<Object?> parts) =>
    List<Object?>.unmodifiable(parts.map(_freeze));

Object? _freeze(Object? value, [int depth = 0]) {
  if (depth > 100) {
    throw ArgumentError.value(value, 'value', 'Query key nesting is too deep.');
  }
  return switch (value) {
    null || bool() || int() || String() => value,
    double() when value.isFinite => value,
    double() => throw ArgumentError.value(
      value,
      'value',
      'Query keys cannot contain non-finite numbers.',
    ),
    List() => List<Object?>.unmodifiable(
      value.map((item) => _freeze(item, depth + 1)),
    ),
    Map() => _freezeMap(value, depth + 1),
    _ => throw ArgumentError.value(
      value,
      'value',
      'Query keys only support null, bool, num, String, List, and Map<String, Object?>.',
    ),
  };
}

Map<String, Object?> _freezeMap(Map<Object?, Object?> value, int depth) {
  final keys = value.keys.toList(growable: false);
  if (keys.any((key) => key is! String)) {
    throw ArgumentError.value(
      value,
      'value',
      'Query key maps require String keys.',
    );
  }
  final sorted = keys.cast<String>()..sort();
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final key in sorted) key: _freeze(value[key], depth),
  });
}

/// Deeply reuses unchanged JSON-like values from [previous].
Object? structurallyShare(Object? previous, Object? next, [int depth = 0]) {
  if (identical(previous, next) || previous == next) return previous;
  if (depth > 500) return next;
  if (previous is List && next is List) {
    final shared = List<dynamic>.of(next);
    var equal = previous.length == next.length;
    for (var index = 0; index < next.length; index++) {
      final value = structurallyShare(
        index < previous.length ? previous[index] : null,
        next[index],
        depth + 1,
      );
      shared[index] = value;
      equal =
          equal && index < previous.length && identical(value, previous[index]);
    }
    return equal ? previous : shared;
  }
  if (previous is Map && next is Map) {
    if (previous.keys.any((key) => key is! String) ||
        next.keys.any((key) => key is! String)) {
      return next;
    }
    final shared = <String, Object?>{};
    var equal = previous.length == next.length;
    for (final entry in next.entries) {
      final key = entry.key as String;
      final value = structurallyShare(previous[key], entry.value, depth + 1);
      shared[key] = value;
      equal =
          equal && previous.containsKey(key) && identical(value, previous[key]);
    }
    return equal ? previous : shared;
  }
  return next;
}
