import 'package:odroe/router.dart';
import 'package:test/test.dart';

const _safeMax = 9007199254740991;
final _path = PathParams<int>.codec(
  decode: (input) => input.requiredInt('postId'),
  encode: (value, output) => output.integer('postId', value),
);

SearchParams<int> _search(InvalidSearchBehavior invalid) =>
    SearchParams<int>.codec(
      keys: {'page'},
      defaults: 1,
      invalid: invalid,
      decode: (input) => input.integer('page') ?? 1,
      encode: (value, output) => output.integer('page', value, omitIf: 1),
    );

Matcher _formatError(Object source) => isA<ParameterFormatException>().having(
  (error) => error.source,
  'source',
  source,
);

void main() {
  final post = AppRoute<int, NoSearch, NoData>(
    path: '/posts/:postId',
    params: _path,
  );
  final pathMatcher = RouteMatcher([post]);
  final fallback = AppRoute<NoParams, int, NoData>(
    path: '/posts',
    search: _search(InvalidSearchBehavior.fallback),
  );
  final strict = AppRoute<NoParams, int, NoData>(
    path: '/posts',
    search: _search(InvalidSearchBehavior.error),
  );

  for (final entry in {
    '9007199254740991': _safeMax,
    '-9007199254740991': -_safeMax,
    '+9007199254740991': _safeMax,
    '-0009007199254740991': -_safeMax,
    '0x1fffffffffffff': _safeMax,
    '-0X1FFFFFFFFFFFFF': -_safeMax,
    '0': 0,
    '+0': 0,
    '-0': 0,
    '000': 0,
    '-7': -7,
    '+007': 7,
    '-007': -7,
    '0x2a': 42,
    '-0x2A': -42,
    '+0X002a': 42,
    ' 7 ': 7,
    '\t-7\n': -7,
  }.entries) {
    test('path/search preserve and canonicalize ${entry.key.trim()}', () {
      final input = entry.key;
      final value = entry.value;
      expect(
        _path.decode({
          'postId': [input],
        }),
        value,
      );
      expect(
        SearchInput({
          'page': [input],
        }).integer('page'),
        value,
      );
      expect(_path.decode(_path.encode(value)), value);
      final search = _search(InvalidSearchBehavior.error);
      expect(search.decode(search.encode(value)).value, value);
      final destination = post.to(params: value);
      expect(destination.uri.path, '/posts/$value');
      final match = pathMatcher.match(Uri(path: '/posts/$input'))!;
      expect(match.leaf(post).params, value);
      expect(match.location, destination.uri);
    });
  }

  for (final input in [
    '9007199254740992',
    '-9007199254740992',
    '9007199254740993',
    '-9007199254740993',
    '9223372036854775807',
    '9223372036854775808',
    '-9223372036854775808',
    '-9223372036854775809',
    '+0009007199254740992',
    '0x20000000000000',
    '-0x20000000000000',
    // Native int.tryParse used to wrap this hexadecimal value to -1.
    '0xffffffffffffffff',
    '-0xffffffffffffffff',
    '9' * 400,
  ]) {
    test('out-of-range $input never becomes another path or search ID', () {
      expect(
        () => _path.decode({
          'postId': [input],
        }),
        throwsA(_formatError(input)),
      );
      expect(
        () => SearchInput({
          'page': [input],
        }).integer('page'),
        throwsA(_formatError(input)),
      );
      expect(pathMatcher.match(Uri(path: '/posts/$input')), isNull);
      final uri = Uri(
        path: '/posts',
        queryParameters: {'page': input, 'keep': 'x'},
        fragment: 'top',
      );
      final match = RouteMatcher([fallback]).match(uri)!;
      expect(match.leaf(fallback).search, 1);
      expect(match.leaf(fallback).searchError, _formatError(input));
      expect(match.location.toString(), '/posts?keep=x#top');
      expect(
        () => RouteMatcher([strict]).match(uri),
        throwsA(
          isA<SearchParameterFormatException>().having(
            (error) => error.source,
            'source',
            input,
          ),
        ),
      );
    });
  }

  test('missing and malformed integers preserve existing error policies', () {
    expect(() => _path.decode({}), throwsA(isA<ParameterFormatException>()));
    expect(pathMatcher.match(Uri.parse('/posts')), isNull);
    expect(SearchInput({}).integer('page'), isNull);
    for (final input in ['', '+', '-', '0x', '1.5', '1e3', '--1', '1_000']) {
      expect(
        () => _path.decode({
          'postId': [input],
        }),
        throwsA(_formatError(input)),
      );
      expect(
        _search(InvalidSearchBehavior.fallback).decode({
          'page': [input],
        }).error,
        _formatError(input),
      );
      expect(
        () => _search(InvalidSearchBehavior.error).decode({
          'page': [input],
        }),
        throwsA(isA<SearchParameterFormatException>()),
      );
    }
    expect(
      () => _path.decode({
        'postId': ['1', '2'],
      }),
      throwsA(isA<ParameterFormatException>()),
    );
    expect(
      _search(InvalidSearchBehavior.fallback).decode({
        'page': ['1', '2'],
      }).error,
      isA<ParameterFormatException>(),
    );
  });

  test('encoding refuses unsafe values before search omission', () {
    for (final value in [
      _safeMax + 1,
      -_safeMax - 1,
      BigInt.parse('9007199254740993').toInt(),
      BigInt.parse('9223372036854775807').toInt(),
    ]) {
      expect(() => post.to(params: value), throwsA(_formatError(value)));
      expect(() => fallback.to(search: value), throwsA(_formatError(value)));
      expect(
        () => SearchOutput().integer('page', value, omitIf: value),
        throwsA(_formatError(value)),
      );
    }
    final optional = SearchParams<int?>.codec(
      keys: {'page'},
      defaults: null,
      decode: (input) => input.integer('page'),
      encode: (value, output) => output.integer('page', value, omitIf: 1),
    );
    expect(optional.encode(null), isEmpty);
    expect(optional.encode(1), isEmpty);
    expect(optional.encode(0), {
      'page': ['0'],
    });
  });

  test('large IDs remain exact through string or custom BigInt codecs', () {
    const largeId = '9007199254740993';
    final strings = PathParams<String>.codec(
      decode: (input) => input.requiredString('postId'),
      encode: (value, output) => output.string('postId', value),
    );
    final large = PathParams<BigInt>.codec(
      decode: (input) {
        final value = input.requiredString('postId');
        return BigInt.tryParse(value) ??
            (throw ParameterFormatException('Invalid postId.', source: value));
      },
      encode: (value, output) => output.string('postId', value.toString()),
    );
    expect(strings.decode(strings.encode(largeId)), largeId);
    final value = BigInt.parse(largeId);
    expect(large.decode(large.encode(value)), value);
    expect(
      () => large.decode({
        'postId': ['bad'],
      }),
      throwsA(_formatError('bad')),
    );
  });
}
