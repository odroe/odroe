import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('freezes nested parts for stable serialized identity', () {
    final nested = <Object?>[1];
    final values = <String, Object?>{'z': nested, 'a': 'first'};
    final key = QueryKey('resource', <Object?>[values]);
    final canonical = key.canonical;
    final hashCode = key.hashCode;

    nested
      ..[0] = 2
      ..add(3);
    values
      ..['a'] = 'changed'
      ..['new'] = true;

    expect(key.canonical, canonical);
    expect(key.hashCode, hashCode);
    expect(key.toJson(), <Object?>[
      'resource',
      <String, Object?>{
        'a': 'first',
        'z': <Object?>[1],
      },
    ]);
    expect(QueryKey.fromJson(key.toJson()), key);

    final frozen = key.parts.single as Map<String, Object?>;
    expect(frozen.keys, <String>['a', 'z']);
    expect(() => frozen['a'] = 'changed', throwsUnsupportedError);
    expect(
      () => (frozen['z']! as List<Object?>).add(2),
      throwsUnsupportedError,
    );
  });

  test('preserves the query key nesting limit while freezing', () {
    Object? atLimit = 0;
    for (var depth = 0; depth < 100; depth++) {
      atLimit = <Object?>[atLimit];
    }

    expect(() => QueryKey('deep', <Object?>[atLimit]), returnsNormally);
    expect(
      () => QueryKey('deep', <Object?>[
        <Object?>[atLimit],
      ]),
      throwsArgumentError,
    );
  });
}
