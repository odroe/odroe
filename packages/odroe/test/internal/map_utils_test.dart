import 'package:odroe/src/_internal/map_utils.dart';
import 'package:test/test.dart';

void main() {
  group('InternalNullableMapUtils', () {
    test('isNullOrEmpty', () {
      expect(null.isNullOrEmpty, true);
      expect({}.isNullOrEmpty, true);
      expect({1: 2}.isNullOrEmpty, false);
    });

    test('equals()', () {
      expect(null.equals(null), equals(true));
      expect(null.equals({}), equals(false));
      expect(null.equals({1: 2}), equals(false));
      expect({}.equals(null), equals(false));
      expect({}.equals({}), equals(true));
      expect({}.equals({1: 2}), equals(false));
      expect({1: 2}.equals(null), equals(false));
      expect({1: 2}.equals({}), equals(false));
      expect({1: 2}.equals({1: 2}), equals(true));
    });
  });

  group('InternalMapUtils', () {
    test('merge()', () {
      expect({1: 2}.merge({2: 3}), equals({1: 2, 2: 3}));
    });

    test('maybeMerge()', () {
      expect({1: 2}.maybeMerge(null), equals({1: 2}));
      expect({1: 2}.maybeMerge({}), equals({1: 2}));
      expect({1: 2}.maybeMerge({2: 3}), equals({1: 2, 2: 3}));
      expect({1: 2}.maybeMerge({1: 2}), equals({1: 2}));
    });

    test('itemsHashCode', () {
      expect({}.itemsHashCode, equals(Object.hashAll([])));
      expect({1: 2}.itemsHashCode, equals(Object.hashAll([1, 2])));
      expect({1: 2, 2: 3}.itemsHashCode, equals(Object.hashAll([1, 2, 2, 3])));
      expect({1: 2, 2: 3}.where((key, _) => key == 1), equals({1: 2}));
    });
  });
}
