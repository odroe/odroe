import 'dart:convert';
import 'dart:typed_data';

/// Extends RPC serialization with one tagged domain value.
abstract interface class SerializationAdapter<T> {
  /// Wire tag that identifies values handled by this adapter.
  String get tag;

  /// Whether [value] can be encoded by this adapter.
  bool canEncode(Object value);

  /// Converts [value] to a serializer-supported representation.
  Object? encode(T value, Serializer serializer);

  /// Reconstructs a value from its decoded wire representation.
  T decode(Object? value, Serializer serializer);
}

/// Versioned JSON-compatible serializer used by RPC and hydration handoff.
final class Serializer {
  /// Creates a serializer with built-in and custom [adapters].
  Serializer({Iterable<SerializationAdapter<dynamic>> adapters = const []})
    : _adapters = <SerializationAdapter<dynamic>>[
        ..._builtInAdapters,
        ...adapters,
      ] {
    for (final adapter in _adapters) {
      if (adapter.tag == 'Map') {
        throw ArgumentError('Serialization adapter tag "Map" is reserved.');
      }
      if (_byTag.containsKey(adapter.tag)) {
        throw ArgumentError('Duplicate serialization adapter: ${adapter.tag}');
      }
      _byTag[adapter.tag] = adapter;
    }
  }

  final List<SerializationAdapter<dynamic>> _adapters;
  final Map<String, SerializationAdapter<dynamic>> _byTag =
      <String, SerializationAdapter<dynamic>>{};

  /// Converts [value] to JSON-compatible values with tagged extensions.
  Object? encode(Object? value) {
    if (value == null || value is bool || value is num || value is String) {
      if (value is double && !value.isFinite) {
        throw ArgumentError('Cannot serialize a non-finite double.');
      }
      return value;
    }
    for (final adapter in _adapters) {
      if (adapter.canEncode(value)) {
        return <String, Object?>{
          r'$type': adapter.tag,
          r'$value': encode(adapter.encode(value, this)),
        };
      }
    }
    if (value is List) return value.map(encode).toList(growable: false);
    if (value is Iterable) return value.map(encode).toList(growable: false);
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw ArgumentError('Serialized maps require String keys.');
      }
      final encoded = value.map<String, Object?>(
        (key, item) => MapEntry(key as String, encode(item)),
      );
      if (encoded.containsKey(r'$type') && encoded.containsKey(r'$value')) {
        return <String, Object?>{
          r'$type': 'Map',
          r'$value': encoded.entries
              .map<Object?>((entry) => <Object?>[entry.key, entry.value])
              .toList(growable: false),
        };
      }
      return encoded;
    }
    throw ArgumentError.value(
      value,
      'value',
      'Register a SerializationAdapter for this type.',
    );
  }

  /// Restores a value previously produced by [encode].
  Object? decode(Object? value) {
    if (value is List) return value.map(decode).toList(growable: false);
    if (value is Map) {
      final typed = Map<String, Object?>.from(value);
      final tag = typed[r'$type'];
      if (tag is String && typed.containsKey(r'$value')) {
        if (tag == 'Map') {
          final entries = typed[r'$value']! as List;
          return <String, Object?>{
            for (final entry in entries.cast<List>())
              entry[0]! as String: decode(entry[1]),
          };
        }
        final adapter = _byTag[tag];
        if (adapter == null) throw FormatException('Unknown type tag: $tag');
        return adapter.decode(decode(typed[r'$value']), this);
      }
      return typed.map((key, item) => MapEntry(key, decode(item)));
    }
    return value;
  }

  /// Encodes [value] as a JSON string.
  String encodeJson(Object? value) => jsonEncode(encode(value));

  /// Decodes one JSON string produced by [encodeJson].
  Object? decodeJson(String value) => decode(jsonDecode(value));
}

final List<SerializationAdapter<dynamic>> _builtInAdapters =
    <SerializationAdapter<dynamic>>[
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

final class _SimpleAdapter<T> implements SerializationAdapter<Object?> {
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
  Object? encode(Object? value, Serializer serializer) => _encode(value as T);

  @override
  Object? decode(Object? value, Serializer serializer) => _decode(value);
}
