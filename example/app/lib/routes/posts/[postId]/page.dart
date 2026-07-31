import 'package:flutter/material.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import '../../../routes.dart' as generated;
import 'route.dart' as definition;

final route = definition.route.page(
  build: (routeContext) {
    final postId = routeContext.params.postId;
    final queryKey = QueryKey('post-title', <Object?>[postId]);
    return Center(
      child: QueryBuilder<String>(
        options: QueryOptions<String>(
          key: queryKey,
          query: (query) => generated.routes.posts.postId.readTitle(
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
          return Text(
            '${result.requireData}; '
            'preview=${routeContext.search.preview}; '
            'tags=${routeContext.search.tags.join(',')}',
          );
        },
      ),
    );
  },
);
