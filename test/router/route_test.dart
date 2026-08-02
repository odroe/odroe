import 'package:odroe/router.dart';
import 'package:test/test.dart';

typedef _OrganizationParams = ({String organizationId});
typedef _OrganizationSearch = ({String tab});
typedef _ProjectParams = ({int projectId});
typedef _PageSearch = ({int page});

void main() {
  test('same-name route capabilities keep independent values', () {
    final first = RouteCapability<String>('document');
    final second = RouteCapability<String>('document');
    final firstRoute = first.attach(
      AppRoute<NoParams, NoSearch, NoData>(),
      'first',
    );
    final route = second.attach(firstRoute, 'second');

    expect(first, isNot(same(second)));
    expect(route.capability(first), 'first');
    expect(route.capability(second), 'second');
  });

  test('widened route capabilities enforce their runtime value type', () {
    final capability = RouteCapability<String>('document');
    final RouteCapability<Object> widened = capability;

    expect(
      () => widened.attach(AppRoute<NoParams, NoSearch, NoData>(), 42),
      throwsA(isA<TypeError>()),
    );
  });

  test('RouteRef composes typed nested params and search', () {
    final organization =
        AppRoute<_OrganizationParams, _OrganizationSearch, NoData>(
          path: '/organizations/:organizationId',
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
      path: 'projects/:projectId',
      params: PathParams<_ProjectParams>.codec(
        decode: (input) => (projectId: input.requiredInt('projectId')),
        encode: (value, output) => output.integer('projectId', value.projectId),
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

  test('nested matching retains typed params', () {
    final organization = AppRoute<_OrganizationParams, NoSearch, NoData>(
      path: '/organizations/:organizationId',
      params: PathParams<_OrganizationParams>.codec(
        decode: (input) =>
            (organizationId: input.requiredString('organizationId')),
        encode: (value, output) =>
            output.string('organizationId', value.organizationId),
      ),
      terminal: false,
    );
    final project = AppRoute<_ProjectParams, NoSearch, NoData>(
      path: 'projects/:projectId',
      params: PathParams<_ProjectParams>.codec(
        decode: (input) => (projectId: input.requiredInt('projectId')),
        encode: (value, output) => output.integer('projectId', value.projectId),
      ),
    );
    final matches = RouteMatcher(<RouteNode>[
      organization.withChildren(<RouteNode>[project]),
    ]).match(Uri.parse('/organizations/odroe/projects/7'))!;

    expect(matches.match(organization)!.params.organizationId, 'odroe');
    expect(matches.leaf(project).params.projectId, 7);
  });

  test('search invalid policy distinguishes fallback from error', () {
    SearchParams<_PageSearch> search(InvalidSearchBehavior invalid) =>
        SearchParams<_PageSearch>.codec(
          keys: const <String>{'page'},
          defaults: (page: 1),
          invalid: invalid,
          decode: (input) => (page: input.integer('page') ?? 1),
          encode: (value, output) =>
              output.integer('page', value.page, omitIf: 1),
        );

    final fallback = AppRoute<NoParams, _PageSearch, NoData>(
      path: '/',
      search: search(InvalidSearchBehavior.fallback),
    );
    final fallbackMatch = RouteMatcher(<RouteNode>[
      fallback,
    ]).match(Uri.parse('/?page=invalid'))!;

    expect(fallbackMatch.leaf(fallback).search.page, 1);
    expect(
      fallbackMatch.leaf(fallback).searchError,
      isA<ParameterFormatException>(),
    );
    expect(fallbackMatch.location, Uri.parse('/'));

    final strict = AppRoute<NoParams, _PageSearch, NoData>(
      path: '/',
      search: search(InvalidSearchBehavior.error),
    );
    expect(
      () =>
          RouteMatcher(<RouteNode>[strict]).match(Uri.parse('/?page=invalid')),
      throwsA(
        isA<SearchParameterFormatException>().having(
          (error) => error.source,
          'source',
          'invalid',
        ),
      ),
    );
  });
}
