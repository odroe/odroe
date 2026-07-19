import 'dart:typed_data';

import 'package:odroe/rpc.dart';
import 'package:test/test.dart';

void main() {
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
