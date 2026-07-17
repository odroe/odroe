import 'dart:convert';

/// A deterministic, serializable identity for one server-state resource.
final class QueryKey {
  /// Creates a key from a stable namespace and optional JSON-like parts.
  QueryKey(this.namespace, [Iterable<Object?> parts = const <Object?>[]])
    : parts = List<Object?>.unmodifiable(parts) {
    if (namespace.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'Must not be empty.');
    }
    _canonical = _encode(<Object?>[namespace, ...this.parts]);
  }

  /// Restores a key from its JSON representation.
  factory QueryKey.fromJson(Object? value) {
    if (value is! List || value.isEmpty || value.first is! String) {
      throw FormatException('A query key must be a non-empty JSON array.');
    }
    return QueryKey(value.first as String, value.skip(1));
  }

  /// Human-readable resource namespace.
  final String namespace;

  /// Ordered variables that distinguish resources in the namespace.
  final List<Object?> parts;

  late final String _canonical;

  /// Stable canonical form used by caches and persistence.
  String get canonical => _canonical;

  /// Whether this key begins with [prefix].
  bool startsWith(QueryKey prefix) {
    if (namespace != prefix.namespace || parts.length < prefix.parts.length) {
      return false;
    }
    for (var index = 0; index < prefix.parts.length; index++) {
      if (_encode(parts[index]) != _encode(prefix.parts[index])) return false;
    }
    return true;
  }

  /// JSON representation used by hydration and persistence.
  List<Object?> toJson() => <Object?>[namespace, ...parts];

  @override
  bool operator ==(Object other) =>
      other is QueryKey && other._canonical == _canonical;

  @override
  int get hashCode => _canonical.hashCode;

  @override
  String toString() => _canonical;
}

String _encode(Object? value, [int depth = 0]) {
  if (depth > 100) {
    throw ArgumentError.value(value, 'value', 'Query key nesting is too deep.');
  }
  return switch (value) {
    null => 'null',
    bool() || int() || String() => jsonEncode(value),
    double() when value.isFinite => jsonEncode(value),
    double() => throw ArgumentError.value(
      value,
      'value',
      'Query keys cannot contain non-finite numbers.',
    ),
    List() => '[${value.map((item) => _encode(item, depth + 1)).join(',')}]',
    Map() => _encodeMap(value, depth + 1),
    _ => throw ArgumentError.value(
      value,
      'value',
      'Query keys only support null, bool, num, String, List, and Map<String, Object?>.',
    ),
  };
}

String _encodeMap(Map<Object?, Object?> value, int depth) {
  final keys = value.keys.toList(growable: false);
  if (keys.any((key) => key is! String)) {
    throw ArgumentError.value(
      value,
      'value',
      'Query key maps require String keys.',
    );
  }
  final sorted = keys.cast<String>()..sort();
  final buffer = StringBuffer('{');
  for (var index = 0; index < sorted.length; index++) {
    if (index > 0) buffer.write(',');
    final key = sorted[index];
    buffer
      ..write(jsonEncode(key))
      ..write(':')
      ..write(_encode(value[key], depth));
  }
  return '${buffer.toString()}}';
}

/// Deeply reuses unchanged JSON-like values from [previous].
Object? structurallyShare(Object? previous, Object? next, [int depth = 0]) {
  if (identical(previous, next) || previous == next) return previous;
  if (depth > 500) return next;
  if (previous is List && next is List) {
    var equal = previous.length == next.length;
    for (var index = 0; index < next.length; index++) {
      final value = structurallyShare(
        index < previous.length ? previous[index] : null,
        next[index],
        depth + 1,
      );
      equal = equal && identical(value, previous[index]);
    }
    return equal ? previous : next;
  }
  if (previous is Map && next is Map) {
    if (previous.keys.any((key) => key is! String) ||
        next.keys.any((key) => key is! String)) {
      return next;
    }
    var equal = previous.length == next.length;
    for (final entry in next.entries) {
      final key = entry.key as String;
      final value = structurallyShare(previous[key], entry.value, depth + 1);
      equal =
          equal && previous.containsKey(key) && identical(value, previous[key]);
    }
    return equal ? previous : next;
  }
  return next;
}
