import 'dart:typed_data';

import 'package:odroe/rpc.dart';
import 'package:test/test.dart';

void main() {
  test('server function exposes and validates its optional wire id', () {
    final function = ServerFunction<int, int>(
      id: 'numbers.double',
      handler: (context) => context.data * 2,
    );

    expect(function.id, 'numbers.double');
    expect(
      () =>
          ServerFunction<int, int>(id: '', handler: (context) => context.data),
      throwsArgumentError,
    );
  });

  test('serializer preserves typed bytes and protocol-shaped maps', () {
    final serializer = Serializer();
    final bytes = Uint8List.fromList(<int>[1, 2, 255]);
    final reserved = <String, Object?>{
      r'$type': 'user-value',
      r'$value': <String, Object?>{'nested': true},
    };

    expect(serializer.decodeJson(serializer.encodeJson(bytes)), bytes);
    expect(serializer.decodeJson(serializer.encodeJson(reserved)), reserved);
  });
}
