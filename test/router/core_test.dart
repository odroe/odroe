import 'package:odroe/router_core.dart';
import 'package:test/test.dart';

typedef _PostParams = ({int postId});
typedef _PostSearch = ({int page, String? query});
typedef _OrganizationParams = ({String organizationId});
typedef _OrganizationSearch = ({String tab});
typedef _ProjectParams = ({int projectId});

PathParams<_PostParams> get _postParams => PathParams<_PostParams>.codec(
  decode: (input) => (postId: input.requiredInt('postId')),
  encode: (value, output) => output.integer('postId', value.postId),
);

SearchParams<_PostSearch> get _postSearch => SearchParams<_PostSearch>.codec(
  keys: const <String>{'page', 'query'},
  defaults: (page: 1, query: null),
  decode: (input) =>
      (page: input.integer('page') ?? 1, query: input.string('query')),
  encode: (value, output) {
    output.integer('page', value.page, omitIf: 1);
    output.string('query', value.query);
  },
);

void main() {
  group('typed locations', () {
    test('builds a canonical destination', () {
      final route = AppRoute<_PostParams, _PostSearch, NoData>(
        path: '/posts/[postId]',
        params: _postParams,
        search: _postSearch,
      );

      final destination = route.to(
        params: (postId: 42),
        search: (page: 2, query: 'flutter router'),
      );

      expect(
        destination.uri.toString(),
        '/posts/42?page=2&query=flutter+router',
      );
    });

    test('omits default search values', () {
      final route = AppRoute<_PostParams, _PostSearch, NoData>(
        path: '/posts/[postId]',
        params: _postParams,
        search: _postSearch,
      );

      expect(
        route
            .to(params: (postId: 42), search: (page: 1, query: null))
            .uri
            .toString(),
        '/posts/42',
      );
    });

    test('supports static route destinations without empty params', () {
      final route = AppRoute<NoParams, NoSearch, NoData>(path: '/about');

      expect(route.to().uri.toString(), '/about');
    });

    test('keeps the root destination canonical', () {
      final route = AppRoute<NoParams, NoSearch, NoData>(path: '/');

      expect(route.to().uri.toString(), '/');
    });

    test('RouteRef composes typed nested params and search ownership', () {
      final organization =
          AppRoute<_OrganizationParams, _OrganizationSearch, NoData>(
            path: '/organizations/[organizationId]',
            params: PathParams<_OrganizationParams>.codec(
              decode: (input) =>
                  (organizationId: input.requiredString('organizationId')),
              encode: (value, output) =>
                  output.string('organizationId', value.organizationId),
            ),
            search: SearchParams<_OrganizationSearch>.codec(
              keys: const <String>{'tab'},
              defaults: (tab: 'overview'),
              decode: (input) => (tab: input.string('tab') ?? 'overview'),
              encode: (value, output) =>
                  output.string('tab', value.tab, omitIf: 'overview'),
            ),
            terminal: false,
          );
      final project = AppRoute<_ProjectParams, NoSearch, NoData>(
        path: 'projects/[projectId]',
        params: PathParams<_ProjectParams>.codec(
          decode: (input) => (projectId: input.requiredInt('projectId')),
          encode: (value, output) =>
              output.integer('projectId', value.projectId),
        ),
      );

      final destination = organization
          .ref(params: (organizationId: 'odroe'), search: (tab: 'activity'))
          .then(project.ref(params: (projectId: 7)))
          .destination;

      expect(
        destination.uri.toString(),
        '/organizations/odroe/projects/7?tab=activity',
      );
      expect(destination.route.identity, same(project.identity));
    });
  });

  group('matching', () {
    test('ranks a static route before a dynamic route', () {
      final create = AppRoute<NoParams, NoSearch, NoData>(
        path: '/posts/create',
      );
      final post = AppRoute<_PostParams, NoSearch, NoData>(
        path: '/posts/[postId]',
        params: _postParams,
      );
      final matcher = RouteMatcher(<AnyAppRoute>[post, create]);

      final matches = matcher.match(Uri.parse('/posts/create'))!;

      expect(matches.routes.single.identity, same(create.identity));
    });

    test('rejects a path value that its typed codec cannot decode', () {
      final post = AppRoute<_PostParams, NoSearch, NoData>(
        path: '/posts/[postId]',
        params: _postParams,
      );

      expect(
        RouteMatcher(<AnyAppRoute>[post]).match(Uri.parse('/posts/nope')),
        isNull,
      );
    });

    test('rejects relative locations', () {
      final route = AppRoute<NoParams, NoSearch, NoData>(path: '/about');

      expect(
        () => RouteMatcher(<AnyAppRoute>[route]).match(Uri.parse('about')),
        throwsArgumentError,
      );
    });

    test('retains typed parent and leaf matches', () async {
      final organization = AppRoute<_OrganizationParams, NoSearch, NoData>(
        path: '/organizations/[organizationId]',
        params: PathParams<_OrganizationParams>.codec(
          decode: (input) =>
              (organizationId: input.requiredString('organizationId')),
          encode: (value, output) =>
              output.string('organizationId', value.organizationId),
        ),
        terminal: false,
      );
      final project = AppRoute<_ProjectParams, NoSearch, String>(
        path: 'projects/[projectId]',
        params: PathParams<_ProjectParams>.codec(
          decode: (input) => (projectId: input.requiredInt('projectId')),
          encode: (value, output) =>
              output.integer('projectId', value.projectId),
        ),
        load: (context) =>
            '${context.match(organization)!.params.organizationId}:'
            '${context.params.projectId}',
      );
      final matcher = RouteMatcher(<AnyAppRoute>[
        organization.withChildren(<AnyAppRoute>[project]),
      ]);

      final matches = matcher.match(
        Uri.parse('/organizations/odroe/projects/7'),
      )!;

      expect(matches.match(organization)!.params.organizationId, 'odroe');
      expect(matches.leaf(project).params.projectId, 7);
      expect(await matches.leaf(project).load(), 'odroe:7');
    });

    test('falls back to canonical search state and retains the error', () {
      final route = AppRoute<_PostParams, _PostSearch, NoData>(
        path: '/posts/[postId]',
        params: _postParams,
        search: _postSearch,
      );

      final match = RouteMatcher(<AnyAppRoute>[
        route,
      ]).match(Uri.parse('/posts/42?page=invalid'))!.leaf(route);

      expect(match.search, (page: 1, query: null));
      expect(match.searchError, isA<ParameterFormatException>());
    });

    test(
      'normalizes params and owned search while preserving unknown keys',
      () {
        final route = AppRoute<_PostParams, _PostSearch, NoData>(
          path: '/posts/[postId]',
          params: _postParams,
          search: _postSearch,
        );

        final matches = RouteMatcher(<AnyAppRoute>[route]).match(
          Uri.parse(
            '/posts/0042?page=1&query=flutter+router&utm_source=docs#install',
          ),
        )!;

        expect(
          matches.location.toString(),
          '/posts/42?utm_source=docs&query=flutter+router#install',
        );
        expect(
          matches.sourceLocation.toString(),
          '/posts/0042?page=1&query=flutter+router&utm_source=docs#install',
        );
      },
    );

    test('surfaces strict search errors', () {
      final route = AppRoute<_PostParams, _PostSearch, NoData>(
        path: '/posts/[postId]',
        params: _postParams,
        search: SearchParams<_PostSearch>.codec(
          keys: const <String>{'page', 'query'},
          defaults: (page: 1, query: null),
          invalid: InvalidSearchBehavior.error,
          decode: (input) =>
              (page: input.integer('page') ?? 1, query: input.string('query')),
          encode: (value, output) {},
        ),
      );

      expect(
        () => RouteMatcher(<AnyAppRoute>[
          route,
        ]).match(Uri.parse('/posts/42?page=invalid')),
        throwsA(isA<ParameterFormatException>()),
      );
    });

    test('rejects search keys owned by two active routes', () {
      SearchParams<({int page})> search() => SearchParams<({int page})>.codec(
        keys: const <String>{'page'},
        defaults: (page: 1),
        decode: (input) => (page: input.integer('page') ?? 1),
        encode: (value, output) =>
            output.integer('page', value.page, omitIf: 1),
      );

      final parent = AppRoute<NoParams, ({int page}), NoData>(
        path: '/posts',
        search: search(),
        terminal: false,
      );
      final child = AppRoute<NoParams, ({int page}), NoData>(
        path: 'popular',
        search: search(),
      );

      expect(
        () => RouteMatcher(<AnyAppRoute>[
          parent.withChildren(<AnyAppRoute>[child]),
        ]).match(Uri.parse('/posts/popular')),
        throwsStateError,
      );
    });

    test('keeps declared search ownership when fallback exits early', () {
      final parent = AppRoute<NoParams, ({int page, String sort}), NoData>(
        path: '/posts',
        search: SearchParams<({int page, String sort})>.codec(
          keys: const <String>{'page', 'sort'},
          defaults: (page: 1, sort: 'newest'),
          decode: (input) => (
            page: input.integer('page') ?? 1,
            sort: input.string('sort') ?? 'newest',
          ),
          encode: (value, output) {},
        ),
        terminal: false,
      );
      final child = AppRoute<NoParams, ({String sort}), NoData>(
        path: 'popular',
        search: SearchParams<({String sort})>.codec(
          keys: const <String>{'sort'},
          defaults: (sort: 'newest'),
          decode: (input) => (sort: input.string('sort') ?? 'newest'),
          encode: (value, output) {},
        ),
      );

      expect(
        () => RouteMatcher(<AnyAppRoute>[
          parent.withChildren(<AnyAppRoute>[child]),
        ]).match(Uri.parse('/posts/popular?page=invalid')),
        throwsStateError,
      );
    });

    test('rejects undeclared keys in custom search codecs', () {
      final search = SearchParams<({String value})>.codec(
        keys: const <String>{'declared'},
        defaults: (value: ''),
        decode: (input) => (value: input.string('undeclared') ?? ''),
        encode: (value, output) => output.string('undeclared', value.value),
      );

      expect(() => search.decode(const {}), throwsStateError);
      expect(() => search.encode((value: 'x')), throwsStateError);
    });

    test('runs a loader with typed route values', () async {
      final route = AppRoute<_PostParams, _PostSearch, String>(
        path: '/posts/[postId]',
        params: _postParams,
        search: _postSearch,
        load: (context) => '${context.params.postId}:${context.search.page}',
      );

      final match = RouteMatcher(<AnyAppRoute>[
        route,
      ]).match(Uri.parse('/posts/42?page=2'))!.leaf(route);

      expect(await match.load(), '42:2');
    });
  });
}
