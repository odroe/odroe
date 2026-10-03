import 'package:flutter/material.dart';
import 'package:odroe/router_flutter.dart';

final home = AppRoute<NoParams, NoSearch, NoData>(path: '/');
final about = AppRoute<NoParams, NoSearch, NoData>(path: '/about');
final post = AppRoute<int, NoSearch, NoData>(
  path: '/posts/:postId',
  params: PathParams.integer('postId'),
);
final posts = AppRoute<NoParams, int?, NoData>(
  path: '/posts',
  search: SearchParams.optionalInteger('authorId'),
);

const entries = [
  (id: 1, authorId: 7, title: 'Shipping the first post'),
  (id: 2, authorId: 8, title: 'Working with routes'),
  (id: 3, authorId: 7, title: 'A small release'),
];

void main() => runApp(const PostsDemo());

class PostsDemo extends StatefulWidget {
  const PostsDemo({this.initialLocation = '/', super.key});
  final String initialLocation;

  @override
  State<PostsDemo> createState() => _PostsDemoState();
}

class _PostsDemoState extends State<PostsDemo> {
  late final AppRouter router = AppRouter(
    initialLocation: Uri.parse(widget.initialLocation),
    routes: [
      home.page(
        build: (context) => screen('Home', [
          TextButton(
            onPressed: () => context.router.go(about.to()),
            child: const Text('About'),
          ),
          TextButton(
            onPressed: () => context.router.go(posts.to()),
            child: const Text('Browse posts'),
          ),
        ]),
      ),
      about.page(
        build: (context) => screen('About', [
          const Text('A small publishing app.'),
          TextButton(
            onPressed: () => context.router.go(home.to()),
            child: const Text('Home'),
          ),
        ]),
      ),
      posts.page(
        build: (context) {
          final int? authorId = context.search;
          return screen('Posts', [
            Text(authorId == null ? 'All authors' : 'Author $authorId'),
            if (context.match(posts)!.searchError != null)
              const Text('Invalid author filter; showing all posts.'),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => context.router.replace(posts.to()),
                  child: const Text('All authors'),
                ),
                TextButton(
                  onPressed: () => context.router.replace(posts.to(search: 7)),
                  child: const Text('Alice'),
                ),
                TextButton(
                  onPressed: () => context.router.replace(posts.to(search: 8)),
                  child: const Text('Bob'),
                ),
              ],
            ),
            for (final entry in entries)
              if (authorId == null || entry.authorId == authorId)
                TextButton(
                  onPressed: () =>
                      context.router.push<void>(post.to(params: entry.id)),
                  child: Text(entry.title),
                ),
            TextButton(
              onPressed: () => context.router.go(home.to()),
              child: const Text('Home'),
            ),
          ]);
        },
      ),
      post.page(
        build: (context) {
          final int postId = context.params;
          final found = entries.where((entry) => entry.id == postId).toList();
          return screen('Post $postId', [
            Text(
              found.isEmpty
                  ? 'Post $postId does not exist.'
                  : found.single.title,
            ),
            TextButton(
              onPressed: () => context.router.replace(post.to(params: 2)),
              child: const Text('Next post'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context.buildContext).pop(),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () => context.router.go(posts.to()),
              child: const Text('All posts'),
            ),
          ]);
        },
      ),
    ],
    notFound: (_) => screen('Page not found', [
      TextButton(
        onPressed: () => router.go(home.to()),
        child: const Text('Home'),
      ),
    ]),
    error: (_, error, _) => screen('Invalid URL', [Text('$error')]),
  );

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }
}

Widget screen(String title, List<Widget> children) => Scaffold(
  appBar: AppBar(title: Text(title)),
  body: ListView(children: children),
);
