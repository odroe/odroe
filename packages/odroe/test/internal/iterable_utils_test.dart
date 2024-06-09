import 'package:odroe/next/_internal/iterable_utils.dart';
import 'package:test/test.dart';

void main() {
  group('IterableMapEntryUtils', () {
    test('toMap()', () {
      const entries = [MapEntry(1, 2), MapEntry(2, 1)];

      expect(entries.toMap(), equals({1: 2, 2: 1}));
    });
  });
}
