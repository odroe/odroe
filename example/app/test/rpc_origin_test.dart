import 'package:flutter_test/flutter_test.dart';
import 'package:odroe_example/rpc_origin.dart';

void main() {
  test('Web keeps RPC on the current origin', () {
    expect(rpcBaseUri(isWeb: true), isNull);
  });

  test('native RPC requires an explicit HTTP origin', () {
    expect(() => rpcBaseUri(isWeb: false, nativeOrigin: ''), throwsStateError);
    for (final value in <String>[
      'file:///tmp/odroe.sock',
      'https://user@api.example.com',
      'https://api.example.com/v1',
      'https://api.example.com?tenant=one',
      'https://api.example.com#fragment',
    ]) {
      expect(
        () => rpcBaseUri(isWeb: false, nativeOrigin: value),
        throwsFormatException,
        reason: value,
      );
    }
    expect(
      rpcBaseUri(isWeb: false, nativeOrigin: 'https://api.example.com'),
      Uri.parse('https://api.example.com'),
    );
  });
}
