import 'package:oref/oref.dart';
import 'package:test/test.dart';

void main() {
  group('ref', () {
    test('should create a Ref with initial value', () {
      final a = ref(1);
      expect(a.value, 1);
    });

    test('should allow updating the value', () {
      final a = ref(1);
      a.value = 2;
      expect(a.value, 2);
    });

    test('should work with different types', () {
      final stringRef = ref('hello');
      expect(stringRef.value, 'hello');

      final boolRef = ref(true);
      expect(boolRef.value, true);

      final listRef = ref([1, 2, 3]);
      expect(listRef.value, [1, 2, 3]);
    });

    test('should return a Ref instance', () {
      final a = ref(1);
      expect(a, isA<Ref>());
    });

    test('isRef should correctly identify Ref instances', () {
      final a = ref(1);
      expect(isRef(a), true);
      expect(isRef(1), false);
    });

    test('unref should unwrap Ref instances', () {
      final a = ref(1);
      expect(unref(a), 1);
      expect(unref(2), 2);
    });

    test('triggerRef should trigger an update', () {
      final a = ref(1);
      var updateCount = 0;

      effect(() {
        a.value; // Track the ref
        updateCount++;
      });

      expect(updateCount, 1);

      triggerRef(a);
      expect(updateCount, 2);
    });

    test('should work with null values', () {
      final a = ref<int?>(null);
      expect(a.value, null);

      a.value = 5;
      expect(a.value, 5);

      a.value = null;
      expect(a.value, null);
    });
  });
}
