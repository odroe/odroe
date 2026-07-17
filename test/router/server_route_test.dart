import 'package:odroe/start.dart';
import 'package:test/test.dart';

typedef _Params = ({int postId});

Future<StartResponse> _auth(StartRequestContext context, StartNext next) =>
    next();

void main() {
  test('server fragment preserves the shared typed route contract', () async {
    final definition = AppRoute<_Params, NoSearch, String>(
      path: '/posts/[postId]',
      params: PathParams<_Params>.codec(
        decode: (input) => (postId: input.requiredInt('postId')),
        encode: (value, output) => output.integer('postId', value.postId),
      ),
    );
    final fragment = definition.server(
      load: (context) => 'post-${context.params.postId}',
      middleware: <StartMiddleware>[_auth],
    );
    final scope = RouteLoadScope.from(
      <({AnyAppRoute route, Object? params, Object? search})>[
        (route: definition, params: (postId: 42), search: const NoSearch()),
      ],
    );

    expect(fragment.definition, same(definition));
    expect(
      await fragment.load!(
        RouteLoadContext<_Params, NoSearch>(
          params: (postId: 42),
          search: const NoSearch(),
          location: Uri.parse('/posts/42'),
          scope: scope,
        ),
      ),
      'post-42',
    );
    expect(fragment.serverMiddleware, <StartMiddleware>[_auth]);
    expect(() => fragment.serverMiddleware.add(_auth), throwsUnsupportedError);
  });
}
