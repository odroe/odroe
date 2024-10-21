import 'package:oref/oref.dart';
import 'package:test/test.dart';

void main() {
  group("Reactive Map", () {
    test("is", () {
      final original = {1: 1, 2: 2};
      final observed = reactiveMap(original);

      expect(isReactive(observed), isTrue);
      expect(observed, equals(original));
      expect(observed, isMap);
      expect(original, isMap);
    });

    test('should observe mutations', () {
      dynamic dummy;
      final map = reactiveMap({});

      effect(() {
        dummy = map['key'];
      });
      expect(dummy, isNull);

      map['key'] = 'value';
      expect(dummy, equals('value'));

      map['key'] = 'value2';
      expect(dummy, equals('value2'));

      map.remove('key');
      expect(dummy, isNull);
    });

    test('should only observe shallow mutations', () {
      dynamic dummy;
      final nestedMap = {'nested': 'value'};
      final map = reactiveMap({'key': nestedMap});

      effect(() {
        dummy = map['key']?['nested'];
      });
      expect(dummy, equals('value'));

      // This should not trigger the effect
      nestedMap['nested'] = 'new value';
      expect(dummy, equals('value'));

      // This should trigger the effect
      map['key'] = {'nested': 'new value'};
      expect(dummy, equals('new value'));
    });

    test('should not make nested objects reactive', () {
      final nestedObject = {'a': 1};
      final map = reactiveMap({'nested': nestedObject});

      expect(isReactive(map), isTrue);
      expect(isReactive(map['nested']), isFalse);
    });
  });
}
