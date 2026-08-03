/// Adds the starter-specific domain and route to verified full-stack sources.
Map<String, String> fullStackStarterSources({
  required String packageName,
  required Map<String, String> sharedSources,
}) {
  final deploymentName = _deploymentName(packageName);
  return <String, String>{
    ...sharedSources,
    'lib/posts.dart': _postsSource,
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

const _postsSource = '''
typedef Post = ({int id, String title});

typedef CreatePost = ({String title});

typedef PostPage = ({List<Post> items, int? nextCursor});

typedef ListPostsInput = ({int? cursor, int limit});
''';

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

import '../posts.dart';
import '../routes.dart' as generated;
import 'route.dart' as definition;

const _postPageSize = 20;
final QueryKey<Object?> _postListsKey = QueryKey('posts.list');

final route = definition.route.page(
  build: (context) => _PostsPage(rpc: context.read(rpcClientKey)),
);

final class _PostsPage extends StatefulWidget {
  const _PostsPage({required this.rpc});

  final RpcClient rpc;

  @override
  State<_PostsPage> createState() => _PostsPageState();
}

final class _PostsPageState extends State<_PostsPage> {
  final _title = TextEditingController();
  late MutationOptions<Post, CreatePost, void> _createOptions;
  late InfiniteQueryOptions<PostPage, int?> _listOptions;

  @override
  void initState() {
    super.initState();
    _configureCreate();
    _configureList();
  }

  void _configureCreate() {
    _createOptions = MutationOptions<Post, CreatePost, void>(
      key: QueryKey('posts.create'),
      mutation: (input, _) => generated.routes.createPost(widget.rpc, input),
      onSuccess: (_, _, _, mutation) => mutation.client.invalidateQueries(
        QueryFilter(key: _postListsKey),
      ),
    );
  }

  @override
  void didUpdateWidget(_PostsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rpc, widget.rpc)) {
      _configureCreate();
      _configureList();
    }
  }

  void _configureList() {
    _listOptions = InfiniteQueryOptions<PostPage, int?>(
      key: QueryKey<InfiniteData<PostPage, int?>>('posts.list'),
      initialPageParam: null,
      getNextPageParam: (lastPage, _, _, _) => lastPage.nextCursor,
      query: (page) => generated.routes.listPosts(
        widget.rpc,
        (cursor: page.pageParam, limit: _postPageSize),
        cancelled: page.query.cancelToken.whenCancelled.then<void>((_) {}),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Full-stack Odroe',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
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
                  child: InfiniteQueryBuilder<PostPage, int?>(
                    options: _listOptions,
                    builder: (context, result, fetchNextPage, _) {
                      final query = result.query;
                      if (!query.hasData && query.isFetching) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (query.isError && !query.hasData) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('Unable to load posts.'),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => QueryClientProvider.of(context)
                                    .invalidateQueries(
                                      QueryFilter(
                                        key: _postListsKey,
                                        exact: true,
                                      ),
                                    ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!query.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final posts = <Post>[
                        for (final page in query.requireData.pages)
                          ...page.items,
                      ];
                      return Column(
                        children: <Widget>[
                          if (query.isError)
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
                                      onPressed: () => QueryClientProvider.of(
                                        context,
                                      ).invalidateQueries(
                                        QueryFilter(
                                          key: _postListsKey,
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
                                    itemBuilder: (_, index) {
                                      final post = posts[index];
                                      return ListTile(
                                        title: Text(post.title),
                                        subtitle: Text('Post \${post.id}'),
                                      );
                                    },
                                  ),
                          ),
                          if (result.hasNextPage) ...<Widget>[
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: result.isFetchingNextPage
                                  ? null
                                  : fetchNextPage,
                              child: result.isFetchingNextPage
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Load more'),
                            ),
                          ],
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
    ),
  );

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
''';

const _routeServerSource = '''
import 'package:odroe/database.dart';
import 'package:odroe/server.dart';

import '../posts.dart' as models;
import '../posts_database.dart';
import 'route.dart' as definition;

final route = definition.route.server();

final listPosts = ServerFunction<models.ListPostsInput, models.PostPage>(
  id: 'posts.list',
  method: HttpMethod.get,
  handler: (context) async {
    final input = context.data;
    if (input.limit < 1 || input.limit > 50) {
      throw const HttpError(400, 'Post page limit must be between 1 and 50.');
    }
    final rows = await postQueries
        .selectTable(
          posts,
          where: input.cursor == null
              ? null
              : posts.id.lessThan(input.cursor!),
          orderBy: <SqlOrder>[posts.id.descending],
          limit: input.limit + 1,
        )
        .all(context.request.read(databaseKey));
    final hasNextPage = rows.length > input.limit;
    final items = rows.take(input.limit).toList(growable: false);
    return (
      items: items,
      nextCursor: hasNextPage ? items.last.id : null,
    );
  },
);

final createPost = ServerFunction<models.CreatePost, models.Post>(
  id: 'posts.create',
  method: HttpMethod.post,
  handler: (context) {
    final title = context.data.title.trim();
    if (title.isEmpty) {
      throw const HttpError(400, 'Post title is required.');
    }
    return postQueries
        .insert(posts, <SqlAssignment>[posts.title.set(title)])
        .returning(posts.projection)
        .one(context.request.read(databaseKey));
  },
);
''';
