import 'package:oref/oref.dart';
import 'package:test/test.dart';

void main() {
  group('derived', () {
    test('should compute derived value using getter', () {
      final count = ref(0);
      final derivedValue = derived<int>((old) => count.value + 1);
      expect(derivedValue.value, equals(1));
      count.value = 2;
      expect(derivedValue.value, equals(3));
    });

    test('should update derived value using setter', () {
      final count = ref(0);
      final derivedValue = derived<int>(
        (old) => count.value * 2,
        (newValue) => count.value = newValue ~/ 2,
      );
      expect(derivedValue.value, equals(0));

      derivedValue.value = 10;
      expect(count.value, equals(5));
      expect(derivedValue.value, equals(10));
    });

    test('readonly should create a derived value without setter', () {
      final count = ref(0);
      final readonlyValue = derived.readonly(() => count.value + 2);
      expect(readonlyValue.value, equals(2));
      count.value = 3;
      expect(readonlyValue.value, equals(5));

      // Attempting to set the value should result in a warning
      readonlyValue.value = 10;
      expect(readonlyValue.value, equals(5)); // Value should not change
    });

    test('derived should cache its value', () {
      var computeCount = 0;
      final count = ref(0);
      final derivedValue = derived<int>((old) {
        computeCount++;
        return count.value * 2;
      });

      expect(derivedValue.value, equals(0));
      expect(computeCount, equals(1));

      // Accessing the value again should not recompute
      expect(derivedValue.value, equals(0));
      expect(computeCount, equals(1));

      // Changing the dependency should trigger recomputation
      count.value = 2;
      expect(derivedValue.value, equals(4));
      expect(computeCount, equals(2));
    });

    test('derived should handle multiple dependencies', () {
      final count1 = ref(1);
      final count2 = ref(2);
      final derivedValue = derived<int>((old) => count1.value + count2.value);

      expect(derivedValue.value, equals(3));

      count1.value = 3;
      expect(derivedValue.value, equals(5));

      count2.value = 4;
      expect(derivedValue.value, equals(7));
    });

    test('derived should handle nested derived values', () {
      final count = ref(0);
      final derived1 = derived<int>((old) => count.value * 2);
      final derived2 = derived<int>((old) => derived1.value + 1);

      expect(derived2.value, equals(1));

      count.value = 2;
      expect(derived1.value, equals(4));
      expect(derived2.value, equals(5));
    });
  });
}
