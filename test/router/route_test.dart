import 'package:odroe/router.dart';
import 'package:test/test.dart';

typedef _OrganizationParams = ({String organizationId});
typedef _OrganizationSearch = ({String tab});
typedef _ProjectParams = ({int projectId});

void main() {
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
}
