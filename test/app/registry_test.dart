import 'package:odroe/odroe.dart';
import 'package:test/test.dart';

void main() {
  test('same-name context keys keep independent values', () {
    final first = ContextKey<String>('client');
    final second = ContextKey<String>('client');
    final registry = ModuleRegistry();
    first.provide(registry, 'first');
    second.provide(registry, 'second');

    expect(first, isNot(same(second)));
    expect(registry.read(first), 'first');
    expect(registry.read(second), 'second');
  });

  test('the same context key can deliberately replace a value', () {
    final key = ContextKey<String>('client');
    final registry = ModuleRegistry();
    key.provide(registry, 'first');
    key.provide(registry, 'second');

    expect(registry.read(key), 'second');
  });

  test('key-first factories run lazily once', () {
    final key = ContextKey<String>('client');
    final registry = ModuleRegistry();
    var calls = 0;
    key.provideFactory(registry, () {
      calls++;
      return 'client';
    });

    expect(calls, 0);
    expect(registry.read(key), 'client');
    expect(registry.read(key), 'client');
    expect(calls, 1);
  });

  test('widened context keys enforce their runtime value type', () {
    final key = ContextKey<String>('client');
    final ContextKey<Object> widened = key;
    final registry = ModuleRegistry();

    expect(() => widened.provide(registry, 42), throwsA(isA<TypeError>()));
    expect(registry.maybe(key), isNull);
    expect(
      () => widened.provideFactory(registry, () => 42),
      throwsA(isA<TypeError>()),
    );
    expect(registry.maybe(key), isNull);

    String createClient() => 'client';
    widened.provideFactory(registry, createClient);
    expect(registry.read(key), 'client');
  });
}
