import 'dart:convert';
import 'dart:typed_data';

/// Extends Start serialization with one tagged domain value.
abstract interface class StartSerializationAdapter<T> {
  String get tag;
  bool canEncode(Object value);
  Object? encode(T value, StartSerializer serializer);
  T decode(Object? value, StartSerializer serializer);
}

/// Versioned JSON-compatible serializer used by RPC and hydration handoff.
final class StartSerializer {
  StartSerializer({
    Iterable<StartSerializationAdapter<dynamic>> adapters = const [],
  }) : _adapters = <StartSerializationAdapter<dynamic>>[
         ..._builtInAdapters,
         ...adapters,
       ] {
    for (final adapter in _adapters) {
      if (_byTag.containsKey(adapter.tag)) {
        throw ArgumentError('Duplicate serialization adapter: ${adapter.tag}');
      }
      _byTag[adapter.tag] = adapter;
    }
  }

  final List<StartSerializationAdapter<dynamic>> _adapters;
  final Map<String, StartSerializationAdapter<dynamic>> _byTag =
      <String, StartSerializationAdapter<dynamic>>{};

  Object? encode(Object? value) {
    if (value == null || value is bool || value is num || value is String) {
      if (value is double && !value.isFinite) {
        throw ArgumentError('Cannot serialize a non-finite double.');
      }
      return value;
    }
    if (value is List) return value.map(encode).toList(growable: false);
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw ArgumentError('Serialized maps require String keys.');
      }
      return value.map<String, Object?>(
        (key, item) => MapEntry(key as String, encode(item)),
      );
    }
    for (final adapter in _adapters) {
      if (adapter.canEncode(value)) {
        return <String, Object?>{
          r'$type': adapter.tag,
          r'$value': encode(adapter.encode(value, this)),
        };
      }
    }
    throw ArgumentError.value(
      value,
      'value',
      'Register a StartSerializationAdapter for this type.',
    );
  }

  Object? decode(Object? value) {
    if (value is List) return value.map(decode).toList(growable: false);
    if (value is Map) {
      final typed = Map<String, Object?>.from(value);
      final tag = typed[r'$type'];
      if (tag is String && typed.containsKey(r'$value')) {
        final adapter = _byTag[tag];
        if (adapter == null) throw FormatException('Unknown type tag: $tag');
        return adapter.decode(decode(typed[r'$value']), this);
      }
      return typed.map((key, item) => MapEntry(key, decode(item)));
    }
    return value;
  }

  String encodeJson(Object? value) => jsonEncode(encode(value));
  Object? decodeJson(String value) => decode(jsonDecode(value));
}

final List<StartSerializationAdapter<dynamic>> _builtInAdapters =
    <StartSerializationAdapter<dynamic>>[
      _SimpleAdapter<DateTime>(
        tag: 'DateTime',
        encode: (value) => value.toUtc().toIso8601String(),
        decode: (value) => DateTime.parse(value as String),
      ),
      _SimpleAdapter<Duration>(
        tag: 'Duration',
        encode: (value) => value.inMicroseconds,
        decode: (value) => Duration(microseconds: value as int),
      ),
      _SimpleAdapter<Uri>(
        tag: 'Uri',
        encode: (value) => value.toString(),
        decode: (value) => Uri.parse(value as String),
      ),
      _SimpleAdapter<BigInt>(
        tag: 'BigInt',
        encode: (value) => value.toString(),
        decode: (value) => BigInt.parse(value as String),
      ),
      _SimpleAdapter<Uint8List>(
        tag: 'Bytes',
        encode: base64Encode,
        decode: (value) => base64Decode(value as String),
      ),
    ];

final class _SimpleAdapter<T> implements StartSerializationAdapter<Object?> {
  const _SimpleAdapter({
    required this.tag,
    required Object? Function(T value) encode,
    required T Function(Object? value) decode,
  }) : _encode = encode,
       _decode = decode;

  @override
  final String tag;
  final Object? Function(T value) _encode;
  final T Function(Object? value) _decode;

  @override
  bool canEncode(Object value) => value is T;

  @override
  Object? encode(Object? value, StartSerializer serializer) =>
      _encode(value as T);

  @override
  Object? decode(Object? value, StartSerializer serializer) => _decode(value);
}
