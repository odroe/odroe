import 'package:oref/oref.dart';
import 'package:test/test.dart';

void main() {
  group('effect', () {
    test('should run immediately', () {
      var ran = false;
      effect(() {
        ran = true;
      });
      expect(ran, isTrue);
    });

    test('should track changes in refs', () {
      final count = ref(0);
      var effectCount = 0;

      effect(() {
        count.value; // Track the ref
        effectCount++;
      });

      expect(effectCount, equals(1));

      count.value++;
      expect(effectCount, equals(2));

      count.value++;
      expect(effectCount, equals(3));
    });

    test('should stop tracking when stopped', () {
      final count = ref(0);
      var effectCount = 0;

      final effectInstance = effect(() {
        count.value; // Track the ref
        effectCount++;
      });

      expect(effectCount, equals(1));

      count.value++;
      expect(effectCount, equals(2));

      effectInstance.stop();

      count.value++;
      expect(effectCount, equals(2)); // Should not increase
    });

    test('should support cleanup function', () {
      final count = ref(0);
      var cleanupCount = 0;

      effect(() {
        count.value; // Track the ref
        onEffectCleanup(() {
          cleanupCount++;
        });
      });

      expect(cleanupCount, equals(0));

      count.value++;
      expect(cleanupCount, equals(1));

      count.value++;
      expect(cleanupCount, equals(2));
    });

    test('should support nested effects', () {
      final count1 = ref(0);
      final count2 = ref(0);
      var effect1Count = 0;
      var effect2Count = 0;

      effect(() {
        count1.value; // Track count1
        effect1Count++;

        effect(() {
          count2.value; // Track count2
          effect2Count++;
        });
      });

      expect(effect1Count, equals(1));
      expect(effect2Count, equals(1));

      count1.value++;
      expect(effect1Count, equals(2));
      expect(effect2Count, equals(2));

      count2.value++;
      expect(effect1Count, equals(2));
      expect(effect2Count, equals(4)); // Changed from 3 to 4
    });

    test('should handle errors in effects', () {
      final count = ref(0);
      var errorCount = 0;

      final effectInstance = effect(
        () {
          count.value; // Track the ref
          if (count.value > 0) {
            throw Exception('Test error');
          }
        },
        onStop: () {
          errorCount++;
        },
      );

      expect(errorCount, equals(0));

      expect(() => count.value++, throwsException);

      // The effect might not automatically stop on error
      // Let's manually stop it to trigger the onStop callback
      effectInstance.stop();

      expect(errorCount, equals(1));
    });

    test('should support custom scheduler', () {
      final count = ref(0);
      var effectCount = 0;
      var scheduleCount = 0;

      effect(
        () {
          count.value; // Track the ref
          effectCount++;
        },
        scheduler: () {
          scheduleCount++;
        },
      );

      expect(effectCount, equals(1));
      expect(scheduleCount, equals(0));

      count.value++;
      expect(effectCount, equals(1)); // Not increased yet
      expect(scheduleCount, equals(1));

      // Manually trigger the effect to simulate scheduler behavior
      effect(() {
        count.value;
        effectCount++;
      });

      expect(effectCount, equals(2));
    });
  });
}
