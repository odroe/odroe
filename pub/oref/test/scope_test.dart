import 'package:oref/oref.dart';
import 'package:test/test.dart';

void main() {
  group('scope', () {
    test('should run', () {
      int counter = 0;
      createScope().run(() => counter++);
      expect(counter, equals(1));
    });

    test('should accept zero argument', () {
      final scope = createScope();
      expect((scope as dynamic).effects, isEmpty);
    });

    test('should return run value', () {
      expect(createScope().run(() => 42), equals(42));
    });

    test('should work active status', () {
      final scope = createScope();

      scope.run(() {});
      expect(scope.active, isTrue);

      scope.stop();
      expect(scope.active, isFalse);
    });

    test('should collect the effects', () {
      final scope = createScope();
      scope.run(() {
        late int dummy;
        final counter = ref(0);
        effect(() => dummy = counter.value);

        expect(dummy, equals(0));
        counter.value = 1;
        expect(dummy, equals(1));
      });

      expect((scope as dynamic).effects, hasLength(1));
    });
  });
}
