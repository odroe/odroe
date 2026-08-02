import 'dart_source.dart';
import 'model.dart';

/// Emits an encoder when [shape] contains a generated named-record contract.
String? wireEncoder(
  WireShape shape,
  String value, {
  required String Function(String source) qualify,
  bool cast = false,
}) {
  if (!wireShapeContainsRecord(shape)) return null;
  if (!cast) return _encodeTypedWireValue(shape, value, qualify);
  final type = qualify(shape.source);
  return '(($type typed) => ${_encodeTypedWireValue(shape, 'typed', qualify)})'
      '($value as $type)';
}

/// Emits a decoder for container or generated named-record [shape].
String? wireDecoder(
  WireShape shape,
  String value, {
  required String Function(String source) qualify,
}) {
  if (shape is WireValueShape) return null;
  return _decodeWireValue(shape, value, qualify);
}

/// Whether [shape] contains a generated named-record contract.
bool wireShapeContainsRecord(WireShape shape) => switch (shape) {
  WireRecordShape() => true,
  WireCollectionShape(:final value) => wireShapeContainsRecord(value),
  WireValueShape() => false,
};

String _encodeTypedWireValue(
  WireShape shape,
  String value,
  String Function(String source) qualify,
) {
  if (shape is WireValueShape || !shape.nullable) {
    return _encodeNonNullTypedWireValue(shape, value, qualify);
  }
  final type = qualify(shape.source);
  return '(($type typed) => typed == null ? null : '
      '${_encodeNonNullTypedWireValue(shape, 'typed', qualify)})($value)';
}

String _encodeNonNullTypedWireValue(
  WireShape shape,
  String value,
  String Function(String source) qualify,
) => switch (shape) {
  WireValueShape() => value,
  WireRecordShape(:final fields) =>
    '<String, Object?>{${fields.map((field) => '${dartStringLiteral(field.name)}: '
        '${_encodeTypedWireValue(field.shape, '$value.${field.name}', qualify)}').join(', ')}}',
  WireCollectionShape(value: final valueShape)
      when !wireShapeContainsRecord(valueShape) =>
    value,
  WireCollectionShape(kind: WireCollectionKind.list, value: final valueShape) ||
  WireCollectionShape(kind: WireCollectionKind.set, value: final valueShape) ||
  WireCollectionShape(
    kind: WireCollectionKind.iterable,
    value: final valueShape,
  ) =>
    '$value.map((item) => '
        '${_encodeTypedWireValue(valueShape, 'item', qualify)})'
        '.toList(growable: false)',
  WireCollectionShape(kind: WireCollectionKind.map, value: final valueShape) =>
    '<String, Object?>{for (final entry in $value.entries) '
        'entry.key: '
        '${_encodeTypedWireValue(valueShape, 'entry.value', qualify)}}',
};

String _decodeWireValue(
  WireShape shape,
  String value,
  String Function(String source) qualify,
) {
  final decoded = _decodeNonNullWireValue(shape, value, qualify);
  return shape.nullable ? '($value == null ? null : $decoded)' : decoded;
}

String _decodeNonNullWireValue(
  WireShape shape,
  String value,
  String Function(String source) qualify,
) => switch (shape) {
  WireValueShape(source: 'dynamic') => value,
  WireValueShape() => '$value as ${qualify(_nonNullableSource(shape))}',
  WireCollectionShape(kind: WireCollectionKind.list, value: final valueShape) =>
    '($value as List).map((item) => '
        '${_decodeWireValue(valueShape, 'item', qualify)})'
        '.toList(growable: false)',
  WireCollectionShape(kind: WireCollectionKind.set, value: final valueShape) =>
    '($value as List).map((item) => '
        '${_decodeWireValue(valueShape, 'item', qualify)}).toSet()',
  WireCollectionShape(
    kind: WireCollectionKind.iterable,
    value: final valueShape,
  ) =>
    '($value as List).map((item) => '
        '${_decodeWireValue(valueShape, 'item', qualify)})'
        '.toList(growable: false)',
  WireCollectionShape(kind: WireCollectionKind.map, value: final valueShape) =>
    '<String, ${qualify(valueShape.source)}>{'
        'for (final entry in ($value as Map).entries) '
        'entry.key as String: '
        '${_decodeWireValue(valueShape, 'entry.value', qualify)}}',
  WireRecordShape(:final fields) =>
    '((Map<String, Object?> record) {'
        'if (record.length != ${fields.length}'
        '${fields.map((field) => ' || !record.containsKey(${dartStringLiteral(field.name)})').join()}) '
        '{throw FormatException(${dartStringLiteral('Expected ${shape.source} fields: ${fields.map((field) => field.name).join(', ')}')});}'
        'return (${fields.map((field) => '${field.name}: ${_decodeWireValue(field.shape, 'record[${dartStringLiteral(field.name)}]', qualify)}').join(', ')},);'
        '})($value as Map<String, Object?>)',
};

String _nonNullableSource(WireShape shape) => shape.nullable
    ? shape.source.substring(0, shape.source.length - 1)
    : shape.source;
