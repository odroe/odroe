/// Adds the starter-specific route to Odroe's verified full-stack sources.
Map<String, String> fullStackStarterSources({
  required String packageName,
  required Map<String, String> sharedSources,
}) {
  final deploymentName = _deploymentName(packageName);
  return <String, String>{
    ...sharedSources,
    'lib/routes/route.dart': _routeSource,
    'lib/routes/page.dart': _pageSource,
    'lib/routes/server.dart': _routeServerSource,
    'package.json': sharedSources['package.json']!.replaceAll(
      'odroe-example',
      deploymentName,
    ),
    'package-lock.json': sharedSources['package-lock.json']!.replaceAll(
      'odroe-example',
      deploymentName,
    ),
    'wrangler.jsonc': sharedSources['wrangler.jsonc']!.replaceAll(
      'odroe-example',
      deploymentName,
    ),
  };
}

String _deploymentName(String packageName) {
  final value = packageName.toLowerCase().replaceAll('_', '-');
  return value.startsWith('-') ? 'odroe$value' : value;
}

const _routeSource = '''
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

final route =
    AppRoute<NoParams, NoSearch, NoData>(
      metadata: const RouteMetadata(
        title: 'Odroe App',
        description: 'A full-stack product built with Odroe.',
      ),
    ).document(
      (_) => const RouteDocument(
        language: 'en',
        body: HtmlElement(
          'main',
          children: <HtmlNode>[
            HtmlElement(
              'h1',
              children: <HtmlNode>[HtmlText('Full-stack Odroe')],
            ),
            HtmlElement(
              'p',
              children: <HtmlNode>[
                HtmlText('Flutter, RPC, typed SQL, SQLite, and D1.'),
              ],
            ),
          ],
        ),
      ),
    );
''';

const _pageSource = '''
import 'package:flutter/material.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import '../routes.dart' as generated;
import 'route.dart' as definition;

final route = definition.route.page(
  build: (routeContext) {
    const postId = 42;
    final queryKey = QueryKey('post-title', <Object?>[postId]);

    return Scaffold(
      body: Center(
        child: QueryBuilder<String>(
          options: QueryOptions<String>(
            key: queryKey,
            query: (query) => generated.routes.readTitle(
              routeContext.read(rpcClientKey),
              postId,
              cancelled: query.cancelToken.whenCancelled.then<void>((_) {}),
            ),
          ),
          builder: (_, result) {
            if (!result.hasData && result.isFetching) {
              return const CircularProgressIndicator();
            }
            if (result.isError && !result.hasData) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('Unable to load post.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await routeContext
                          .read(queryClientKey)
                          .invalidateQueries(
                            QueryFilter(key: queryKey, exact: true),
                          );
                    },
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            if (!result.hasData) {
              return const CircularProgressIndicator();
            }
            return Text(result.requireData);
          },
        ),
      ),
    );
  },
);
''';

const _routeServerSource = '''
import 'package:odroe/database.dart';
import 'package:odroe/server.dart';

import '../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server();

final readTitle = ServerFunction<int, String>(
  id: 'posts.read-title',
  method: HttpMethod.get,
  handler: (context) async {
    final titles = await postQueries
        .selectTable(
          posts,
          where: posts.id.equals(context.data),
          limit: 1,
        )
        .all(context.request.read(databaseKey));
    if (titles.isEmpty) throw const NotFound('Post not found.');
    return titles.single;
  },
);
''';
