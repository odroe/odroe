import 'package:flutter/material.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import '../../posts.dart';
import '../../routes.dart' as generated;
import 'route.dart' as definition;

final _postListsKey = QueryKey('posts.list');

final route = definition.route.page(
  build: (context) => _PostsPage(
    rpc: context.read(rpcClientKey),
    sort: context.search.sort,
    openPost: (postId) => context.router.go(
      generated.routes.posts.postId.to(params: (postId: postId)),
    ),
  ),
);

final class _PostsPage extends StatefulWidget {
  const _PostsPage({
    required this.rpc,
    required this.sort,
    required this.openPost,
  });

  final RpcClient rpc;
  final String sort;
  final void Function(int postId) openPost;

  @override
  State<_PostsPage> createState() => _PostsPageState();
}

final class _PostsPageState extends State<_PostsPage> {
  final _title = TextEditingController();
  late MutationOptions<Post, CreatePost, void> _createOptions;
  late QueryKey _listKey;
  late QueryOptions<List<Post>> _listOptions;

  @override
  void initState() {
    super.initState();
    _configureCreate();
    _configureList();
  }

  void _configureCreate() {
    _createOptions = MutationOptions<Post, CreatePost, void>(
      key: QueryKey('posts.create'),
      mutation: (input, _) =>
          generated.routes.posts.createPost(widget.rpc, input),
      onSuccess: (_, _, _, mutation) =>
          mutation.client.invalidateQueries(QueryFilter(key: _postListsKey)),
    );
  }

  @override
  void didUpdateWidget(_PostsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rpc, widget.rpc)) {
      _configureCreate();
      _configureList();
    } else if (oldWidget.sort != widget.sort) {
      _configureList();
    }
  }

  void _configureList() {
    _listKey = QueryKey('posts.list', <Object?>[widget.sort]);
    _listOptions = QueryOptions<List<Post>>(
      key: _listKey,
      query: (query) => generated.routes.posts.listPosts(
        widget.rpc,
        widget.sort,
        cancelled: query.cancelToken.whenCancelled.then<void>((_) {}),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('Posts', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 20),
                MutationBuilder<Post, CreatePost, void>(
                  options: _createOptions,
                  builder: (context, mutation, mutate, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _title,
                          builder: (context, value, _) {
                            final canSubmit =
                                !mutation.isPending &&
                                value.text.trim().isNotEmpty;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: _title,
                                    enabled: !mutation.isPending,
                                    onSubmitted: canSubmit
                                        ? (_) => _createPost(mutate)
                                        : null,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      hintText: 'Write a post title',
                                      labelText: 'Title',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: canSubmit
                                      ? () => _createPost(mutate)
                                      : null,
                                  child: mutation.isPending
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Create'),
                                ),
                              ],
                            );
                          },
                        ),
                        if (mutation.isError) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            'Unable to create post.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: QueryBuilder<List<Post>>(
                    options: _listOptions,
                    builder: (context, result) {
                      if (!result.hasData && result.isFetching) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (result.isError && !result.hasData) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('Unable to load posts.'),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => QueryClientProvider.of(context)
                                    .invalidateQueries(
                                      QueryFilter(key: _listKey, exact: true),
                                    ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!result.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final posts = result.requireData;
                      return Column(
                        children: <Widget>[
                          if (result.isError)
                            Material(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Expanded(
                                      child: Text('Posts may be out of date.'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          QueryClientProvider.of(
                                            context,
                                          ).invalidateQueries(
                                            QueryFilter(
                                              key: _listKey,
                                              exact: true,
                                            ),
                                          ),
                                      child: const Text('Retry refresh'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Expanded(
                            child: posts.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No posts yet. Create the first one.',
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: posts.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final post = posts[index];
                                      return ListTile(
                                        title: Text(post.title),
                                        subtitle: Text('Post ${post.id}'),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: () => widget.openPost(post.id),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createPost(
    Future<Post> Function(CreatePost input) mutate,
  ) async {
    try {
      await mutate((title: _title.text));
      if (!mounted) return;
      _title.clear();
    } on Object {
      // Mutation state renders the failure inline.
    }
  }
}
