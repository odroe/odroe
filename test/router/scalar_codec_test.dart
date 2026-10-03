import 'package:odroe/router.dart';
import 'package:test/test.dart';

PathParams<int> manualPath(String name) => PathParams<int>.codec(
  decode: (input) => input.requiredInt(name),
  encode: (value, output) => output.integer(name, value),
);

SearchParams<int> manualSearch(
  String name,
  int defaults,
  bool omit,
  InvalidSearchBehavior invalid,
) => SearchParams<int>.codec(
  keys: {name},
  defaults: defaults,
  invalid: invalid,
  decode: (input) => input.integer(name) ?? defaults,
  encode: (value, output) =>
      output.integer(name, value, omitIf: omit ? defaults : null),
);

Object outcome(Object? Function() read) {
  try {
    return read() ?? 'null';
  } on ParameterFormatException catch (e) {
    return ('format', e.message, e.source);
  }
}

void main() {
  test('scalar helpers inherit safe integer decoding and encoding limits', () {
    const safeMax = 9007199254740991;
    final path = PathParams.integer('postId');
    final optional = SearchParams.optionalInteger('authorId');
    final page = SearchParams.integer('page', defaults: 1, omitDefault: true);
    for (final value in [-safeMax, -1, 0, 1, safeMax]) {
      expect(path.decode(path.encode(value)), value);
      expect(optional.decode(optional.encode(value)).value, value);
      expect(page.decode(page.encode(value)).value, value);
    }
    for (final value in [safeMax + 1, -safeMax - 1]) {
      expect(
        () => path.encode(value),
        throwsA(isA<ParameterFormatException>()),
      );
      expect(
        () => optional.encode(value),
        throwsA(isA<ParameterFormatException>()),
      );
      expect(
        () => page.encode(value),
        throwsA(isA<ParameterFormatException>()),
      );
    }
    expect(
      () => path.decode({
        'postId': ['9007199254740993'],
      }),
      throwsA(isA<ParameterFormatException>()),
    );
    final invalid = optional.decode({
      'authorId': ['9007199254740993'],
    });
    expect(invalid.value, isNull);
    expect(invalid.error, isA<ParameterFormatException>());
    expect(
      page.decode({
        'page': ['9007199254740993'],
      }).value,
      1,
    );
    final strict = SearchParams.optionalInteger(
      'authorId',
      invalid: InvalidSearchBehavior.error,
    );
    expect(
      () => strict.decode({
        'authorId': ['9007199254740993'],
      }),
      throwsA(isA<SearchParameterFormatException>()),
    );
  });

  test('integer defaults are validated before any decode or omission', () {
    const safeMax = 9007199254740991;
    for (final omit in [false, true]) {
      for (final invalid in InvalidSearchBehavior.values) {
        for (final defaults in [safeMax + 1, -safeMax - 1]) {
          expect(
            () => SearchParams.integer(
              'page',
              defaults: defaults,
              omitDefault: omit,
              invalid: invalid,
            ),
            throwsA(
              isA<ParameterFormatException>()
                  .having((e) => e.source, 'source', defaults)
                  .having((e) => e.message, 'message', contains('default')),
            ),
          );
        }
        for (final defaults in [-safeMax, 0, safeMax]) {
          final codec = SearchParams.integer(
            'page',
            defaults: defaults,
            omitDefault: omit,
            invalid: invalid,
          );
          expect(codec.decode({}).value, defaults);
          expect(codec.decode(codec.encode(defaults)).value, defaults);
          expect(
            codec.encode(defaults),
            omit
                ? <String, List<String>>{}
                : {
                    'page': ['$defaults'],
                  },
          );
          final malformed = {
            'page': ['bad'],
          };
          if (invalid == InvalidSearchBehavior.fallback) {
            expect(codec.decode(malformed).value, defaults);
            expect(
              codec.decode(malformed).error,
              isA<ParameterFormatException>(),
            );
          } else {
            expect(
              () => codec.decode(malformed),
              throwsA(isA<SearchParameterFormatException>()),
            );
          }
        }
      }
    }
  });

  test('explicit codecs keep their own default and encoding contracts', () {
    const customDefault = 9007199254740991 + 1;
    final custom = SearchParams<int>.codec(
      keys: {'page'},
      defaults: customDefault,
      decode: (input) => input.integer('page') ?? customDefault,
      encode: (value, output) => output.string('page', '$value'),
    );
    expect(custom.decode({}).value, customDefault);
    expect(
      custom.decode({
        'page': ['bad'],
      }).value,
      customDefault,
    );
    expect(custom.encode(customDefault), {
      'page': ['$customDefault'],
    });
    final builtInEncoding = manualSearch(
      'page',
      customDefault,
      false,
      InvalidSearchBehavior.fallback,
    );
    expect(builtInEncoding.decode({}).value, customDefault);
    expect(
      () => builtInEncoding.encode(customDefault),
      throwsA(isA<ParameterFormatException>()),
    );
  });

  test(
    'missing, malformed, negative and out-of-range input preserve old parsing',
    () {
      final current = manualPath('postId');
      final candidate = PathParams.integer('postId');
      final inputs = <Map<String, List<String>>>[
        {},
        {'postId': []},
        {
          'postId': ['1', '2'],
        },
        for (final value in [
          '',
          'nope',
          '1.5',
          '1e3',
          '-7',
          '0',
          '+7',
          '007',
          '0x2a',
          '9007199254740991',
          '9007199254740993',
          '9223372036854775808',
          '9' * 400,
        ])
          {
            'postId': [value],
          },
      ];
      for (final input in inputs) {
        expect(
          outcome(() => candidate.decode(input)),
          outcome(() => current.decode(input)),
          reason: '$input',
        );
      }
      expect(
        candidate.decode({
          'postId': ['-7'],
        }),
        -7,
      );
      expect(
        () => candidate.decode({}),
        throwsA(isA<ParameterFormatException>()),
      );
    },
  );

  test(
    'portable signed integers round-trip; canonical path strings normalize',
    () {
      final codec = PathParams.integer('postId');
      for (final value in [-9007199254740991, -7, 0, 7, 9007199254740991]) {
        expect(codec.decode(codec.encode(value)), value);
        expect(codec.encode(value), {
          'postId': ['$value'],
        });
      }
      final post = AppRoute<int, NoSearch, NoData>(
        path: '/posts/:postId',
        params: codec,
      );
      final matcher = RouteMatcher([post]);
      for (final path in ['/posts', '/posts/nope', '/posts/1.5']) {
        expect(matcher.match(Uri.parse(path)), isNull);
      }
      expect(matcher.match(Uri.parse('/posts/-7'))!.leaf(post).params, -7);
      expect(
        matcher.match(Uri.parse('/posts/007'))!.location.toString(),
        '/posts/7',
      );
      expect(
        matcher.match(Uri.parse('/posts/0x2a'))!.location.toString(),
        '/posts/42',
      );
    },
  );

  test(
    'optional search owns absent key, omits null and preserves zero/negative',
    () {
      final codec = SearchParams.optionalInteger('authorId');
      expect(codec.decode({}).value, isNull);
      expect(codec.decode({}).keys, {'authorId'});
      expect(codec.encode(null), isEmpty);
      for (final value in [-7, 0, 7]) {
        expect(codec.decode(codec.encode(value)).value, value);
      }
      final invalid = codec.decode({
        'authorId': ['x'],
      });
      expect(invalid.value, isNull);
      expect(invalid.error, isA<ParameterFormatException>());
      expect(
        codec.decode({
          'authorId': ['1', '2'],
        }).error,
        isA<ParameterFormatException>(),
      );
    },
  );

  for (final omit in [false, true]) {
    for (final invalid in InvalidSearchBehavior.values) {
      test(
        'default search matches explicit codec: omit=$omit invalid=$invalid',
        () {
          final old = manualSearch('page', 1, omit, invalid);
          final next = SearchParams.integer(
            'page',
            defaults: 1,
            omitDefault: omit,
            invalid: invalid,
          );
          for (final input in <Map<String, List<String>>>[
            {},
            {
              'page': ['1'],
            },
            {
              'page': ['0'],
            },
            {
              'page': ['-3'],
            },
            {
              'page': ['bad'],
            },
            {
              'page': ['1', '2'],
            },
            {
              'page': ['9223372036854775808'],
            },
          ]) {
            expect(
              outcome(() => next.decode(input).value),
              outcome(() => old.decode(input).value),
            );
          }
          for (final value in [-1, 0, 1, 2]) {
            expect(next.encode(value), old.encode(value));
            expect(next.decode(next.encode(value)).value, value);
          }
          expect(
            next.encode(1),
            omit
                ? <String, List<String>>{}
                : {
                    'page': ['1'],
                  },
          );
        },
      );
    }
  }

  test(
    'strict search errors are unchanged; fallback canonicalizes only its key',
    () {
      final strict = SearchParams.optionalInteger(
        'authorId',
        invalid: InvalidSearchBehavior.error,
      );
      expect(
        () => strict.decode({
          'authorId': ['bad'],
        }),
        throwsA(
          isA<SearchParameterFormatException>().having(
            (e) => e.source,
            'source',
            'bad',
          ),
        ),
      );
      final posts = AppRoute<NoParams, int?, NoData>(
        path: '/posts',
        search: SearchParams.optionalInteger('authorId'),
      );
      final matches = RouteMatcher([
        posts,
      ]).match(Uri.parse('/posts?authorId=bad&utm=x#section'))!;
      expect(matches.leaf(posts).search, isNull);
      expect(matches.leaf(posts).searchError, isA<ParameterFormatException>());
      expect(matches.location.toString(), '/posts?utm=x#section');
      final defaults = AppRoute<NoParams, int, NoData>(
        path: '/posts',
        search: SearchParams.integer('page', defaults: 1),
      );
      // Existing route refs bypass search encoding when the argument is absent.
      expect(defaults.to().uri.toString(), '/posts');
      expect(defaults.to(search: 1).uri.toString(), '/posts?page=1');
      expect(
        RouteMatcher([defaults]).match(defaults.to().uri)!.location.toString(),
        '/posts?page=1',
      );
    },
  );

  test(
    'nested typed refs preserve parent codecs, owned query keys and identity',
    () {
      final parent = AppRoute<({String teamId}), int?, NoData>(
        path: '/teams/:teamId',
        terminal: false,
        params: PathParams<({String teamId})>.codec(
          decode: (input) => (teamId: input.requiredString('teamId')),
          encode: (value, output) => output.string('teamId', value.teamId),
        ),
        search: SearchParams.optionalInteger('authorId'),
      );
      final child = AppRoute<int, int, NoData>(
        path: 'posts/:postId',
        params: PathParams.integer('postId'),
        search: SearchParams.integer('page', defaults: 1, omitDefault: true),
      );
      final tree = parent.withChildren([child]);
      final destination = parent
          .ref(params: (teamId: 'alpha/beta'), search: 7)
          .then(child.ref(params: 42, search: 2))
          .destination;
      expect(
        destination.uri.toString(),
        '/teams/alpha%2Fbeta/posts/42?authorId=7&page=2',
      );
      expect(destination.route.identity, same(child.identity));
      final matches = RouteMatcher([tree]).match(destination.uri)!;
      final String team = matches.match(parent)!.params.teamId;
      final int id = matches.leaf(child).params;
      final int page = matches.leaf(child).search;
      expect((team, id, page), ('alpha/beta', 42, 2));
      expect(matches.match(parent)!.search, 7);
    },
  );

  test('duplicate search ownership still fails even when omitted', () {
    final parent = AppRoute<NoParams, int?, NoData>(
      path: '/teams',
      terminal: false,
      search: SearchParams.optionalInteger('filter'),
    );
    final child = AppRoute<NoParams, int?, NoData>(
      path: 'posts',
      search: SearchParams.optionalInteger('filter'),
    );
    final matcher = RouteMatcher([
      parent.withChildren([child]),
    ]);
    expect(
      () => parent.ref(search: 1).then(child.ref(search: 2)).destination,
      throwsStateError,
    );
    // Existing ref behavior: absent fields produce no duplicate output. The
    // matcher then rejects the overlapping declared ownership, even without ?.
    final omitted = parent.ref().then(child.ref()).destination;
    expect(omitted.uri.toString(), '/teams/posts');
    expect(() => matcher.match(omitted.uri), throwsStateError);
  });

  test(
    'custom multi-field business constraints keep the original codec escape hatch',
    () {
      final codec = PathParams<({int postId, String slug})>.codec(
        decode: (input) {
          final id = input.requiredInt('postId');
          if (id <= 0) {
            throw const ParameterFormatException('postId must be positive');
          }
          return (postId: id, slug: input.requiredString('slug'));
        },
        encode: (value, output) {
          if (value.postId <= 0) {
            throw const ParameterFormatException('postId must be positive');
          }
          output.integer('postId', value.postId);
          output.string('slug', value.slug);
        },
      );
      const value = (postId: 7, slug: 'space / 中文');
      expect(codec.decode(codec.encode(value)), value);
      expect(
        () => codec.decode({
          'postId': ['-1'],
          'slug': ['post'],
        }),
        throwsA(isA<ParameterFormatException>()),
      );
      expect(
        () => codec.encode((postId: -1, slug: 'post')),
        throwsA(isA<ParameterFormatException>()),
      );
      final multi = SearchParams<({int page, bool draft})>.codec(
        keys: {'page', 'draft'},
        defaults: (page: 1, draft: false),
        decode: (input) => (
          page: input.integer('page') ?? 1,
          draft: input.boolean('draft') ?? false,
        ),
        encode: (value, output) {
          output.integer('page', value.page, omitIf: 1);
          output.boolean('draft', value.draft, omitIf: false);
        },
      );
      expect(
        multi.decode({
          'page': ['bad'],
          'draft': ['true'],
        }).value,
        (page: 1, draft: false),
      );
    },
  );

  test('widened scalar codecs retain runtime parameter checks', () {
    final PathParams<num> path = PathParams.integer('postId');
    final SearchParams<num> search = SearchParams.integer('page', defaults: 1);
    expect(() => path.encode(1.5), throwsA(isA<TypeError>()));
    expect(() => search.encode(1.5), throwsA(isA<TypeError>()));
  });
}
