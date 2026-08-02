import 'package:flutter/material.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import '../../../posts.dart';
import '../../../routes.dart' as generated;
import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => _PostPage(
    rpc: context.read(rpcClientKey),
    queryClient: context.read(queryClientKey),
    postId: context.params.postId,
    preview: context.search.preview,
    tags: context.search.tags.join(','),
  ),
);

final class _PostPage extends StatefulWidget {
  const _PostPage({
    required this.rpc,
    required this.queryClient,
    required this.postId,
    required this.preview,
    required this.tags,
  });

  final RpcClient rpc;
  final QueryClient queryClient;
  final int postId;
  final bool preview;
  final String tags;

  @override
  State<_PostPage> createState() => _PostPageState();
}

final class _PostPageState extends State<_PostPage> {
  late QueryKey<Post> _queryKey;
  late QueryOptions<Post> _queryOptions;

  @override
  void initState() {
    super.initState();
    _configureQuery();
  }

  @override
  void didUpdateWidget(_PostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rpc, widget.rpc) ||
        oldWidget.postId != widget.postId) {
      _configureQuery();
    }
  }

  void _configureQuery() {
    _queryKey = QueryKey<Post>('posts.detail', <Object?>[widget.postId]);
    _queryOptions = QueryOptions<Post>(
      key: _queryKey,
      query: (query) => generated.routes.posts.postId.readPost(
        widget.rpc,
        widget.postId,
        cancelled: query.cancelToken.whenCancelled.then<void>((_) {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: QueryBuilder<Post>(
      client: widget.queryClient,
      options: _queryOptions,
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
                onPressed: () => widget.queryClient.invalidateQueries(
                  QueryFilter(key: _queryKey, exact: true),
                ),
                child: const Text('Retry'),
              ),
            ],
          );
        }
        if (!result.hasData) return const CircularProgressIndicator();
        final post = result.requireData;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (result.isError) ...<Widget>[
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('Post may be out of date.'),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => widget.queryClient.invalidateQueries(
                          QueryFilter(key: _queryKey, exact: true),
                        ),
                        child: const Text('Retry refresh'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '${post.title}; preview=${widget.preview}; tags=${widget.tags}',
            ),
          ],
        );
      },
    ),
  );
}
