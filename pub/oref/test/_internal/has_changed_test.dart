import 'package:flutter_test/flutter_test.dart';
import 'package:oref/src/_internal/has_changed.dart';

void main() {
  group('hasChanged', () {
    test('primitive types', () {
      expect(hasChanged(1, 1), isFalse);
      expect(hasChanged(1, 2), isTrue);
      expect(hasChanged('a', 'a'), isFalse);
      expect(hasChanged('a', 'b'), isTrue);
      expect(hasChanged(true, true), isFalse);
      expect(hasChanged(true, false), isTrue);
      expect(hasChanged(null, null), isFalse);
      expect(hasChanged(null, 1), isTrue);
    });

    test('lists', () {
      expect(hasChanged([], []), isFalse);
      expect(hasChanged([1, 2, 3], [1, 2, 3]), isFalse);
      expect(hasChanged([1, 2, 3], [1, 2]), isTrue);
      expect(hasChanged([1, 2, 3], [1, 2, 4]), isTrue);
      expect(
          hasChanged([
            1,
            [2, 3]
          ], [
            1,
            [2, 3]
          ]),
          isFalse);
      expect(
          hasChanged([
            1,
            [2, 3]
          ], [
            1,
            [2, 4]
          ]),
          isTrue);
    });

    test('sets', () {
      expect(hasChanged(<int>{}, <int>{}), isFalse);
      expect(hasChanged({1, 2, 3}, {1, 2, 3}), isFalse);
      expect(hasChanged({1, 2, 3}, {1, 2}), isTrue);
      expect(hasChanged({1, 2, 3}, {1, 2, 4}), isTrue);
    });

    test('maps', () {
      expect(hasChanged({}, {}), isFalse);
      expect(hasChanged({'a': 1, 'b': 2}, {'a': 1, 'b': 2}), isFalse);
      expect(hasChanged({'a': 1, 'b': 2}, {'a': 1}), isTrue);
      expect(hasChanged({'a': 1, 'b': 2}, {'a': 1, 'b': 3}), isTrue);
      expect(
          hasChanged({
            'a': {'b': 1}
          }, {
            'a': {'b': 1}
          }),
          isFalse);
      expect(
          hasChanged({
            'a': {'b': 1}
          }, {
            'a': {'b': 2}
          }),
          isTrue);
    });
  });
}
