import 'package:flutter/widgets.dart';
import 'package:odroe/query_flutter.dart';

import 'account.dart';
import 'definitions.dart';
import 'posts.dart';

// One UI for both definitions. Every build creates fresh options: no memoizing.
final class PostsApp extends StatelessWidget {
  const PostsApp({
    super.key,
    required this.client,
    required this.account,
    required this.api,
    required this.switchAccount,
    required this.switchBackend,
  });
  final QueryClient client;
  final ValueNotifier<Account> account;
  final PostsQueries Function(Account) api;
  final VoidCallback switchAccount;
  final VoidCallback switchBackend;

  @override
  Widget build(BuildContext context) => QueryClientProvider.value(
    client: client,
    child: _AccountScope(
      notifier: account,
      child: WidgetsApp(
        color: const Color(0xff245fda),
        builder: (context, child) => ColoredBox(
          color: const Color(0xffffffff),
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xff111111), fontSize: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Action('Switch account', switchAccount),
                    Action('Switch backend', switchBackend),
                    Text(_AccountScope.of(context).scope.join('/')),
                  ],
                ),
                Expanded(child: child!),
              ],
            ),
          ),
        ),
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          maintainState: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => settings.name == '/post'
              ? PostEditor(api: api, id: settings.arguments! as int)
              : PostList(api: api),
        ),
      ),
    ),
  );
}

final class _AccountScope extends InheritedNotifier<ValueNotifier<Account>> {
  const _AccountScope({required super.notifier, required super.child});
  static Account of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AccountScope>()!
      .notifier!
      .value;
}

final class PostList extends StatelessWidget {
  const PostList({super.key, required this.api});
  final PostsQueries Function(Account) api;

  @override
  Widget build(BuildContext context) {
    final posts = api(_AccountScope.of(context));
    final options = posts.list(2); // Fresh bridge invocation on every build.
    return InfiniteQueryBuilder<PostPage, PageInput>(
      options: options,
      builder: (context, result, next, previous) {
        final query = result.query;
        return Column(
          children: [
            const Text('Posts'),
            if (!query.hasData && query.isPending) const Text('Loading posts…'),
            if (query.error != null)
              Text('Could not load posts: ${query.error}'),
            if (query.isRefetching)
              const Text('Refreshing; showing saved posts…'),
            if (query.hasData) ...[
              if (query.isStale) const Text('Saved posts may be out of date'),
              for (final page in query.data!.pages)
                for (final post in page.items)
                  Action(
                    post.title,
                    () => Navigator.of(
                      context,
                    ).pushNamed('/post', arguments: post.id),
                  ),
            ],
            Action(
              'Refresh posts',
              () => QueryClientProvider.of(
                context,
              ).invalidateQueries(QueryFilter(key: options.key, exact: true)),
            ),
            if (result.hasNextPage)
              Action(
                result.isFetchingNextPage ? 'Loading more…' : 'More posts',
                result.isFetchingNextPage ? null : () => next(),
              ),
          ],
        );
      },
    );
  }
}

final class PostEditor extends StatelessWidget {
  const PostEditor({super.key, required this.api, required this.id});
  final PostsQueries Function(Account) api;
  final int id;

  @override
  Widget build(BuildContext context) {
    final session = _AccountScope.of(context);
    final posts = api(session);
    final detail = posts.detail(id); // Fresh ordinary options, too.
    return QueryBuilder<Post>(
      options: detail,
      builder: (context, result) => Column(
        children: [
          Action('Back to posts', () => Navigator.of(context).pop()),
          if (!result.hasData && result.isPending) const Text('Loading post…'),
          if (result.error != null)
            Text('Could not load post: ${result.error}'),
          if (result.hasData) ...[
            if (result.isFetching) const Text('Refreshing post…'),
            if (result.isStale) const Text('Saved post may be out of date'),
            Text('Server title: ${result.data!.title}'),
            DraftEditor(
              key: ValueKey(detail.key.canonical),
              post: result.data!,
              options: posts.save(),
            ),
          ],
          Action(
            'Refresh post',
            () => QueryClientProvider.of(
              context,
            ).invalidateQueries(QueryFilter(key: detail.key, exact: true)),
          ),
        ],
      ),
    );
  }
}

final class DraftEditor extends StatefulWidget {
  const DraftEditor({super.key, required this.post, required this.options});
  final Post post;
  final MutationOptions<Post, SaveInput, void> options;
  @override
  State<DraftEditor> createState() => _DraftEditorState();
}

final class _DraftEditorState extends State<DraftEditor> {
  late final text = TextEditingController(text: widget.post.title);
  final focus = FocusNode();
  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MutationBuilder<Post, SaveInput, void>(
    options: widget.options,
    builder: (context, state, save, reset) => Column(
      children: [
        EditableText(
          controller: text,
          focusNode: focus,
          style: const TextStyle(color: Color(0xff111111), fontSize: 16),
          cursorColor: const Color(0xff245fda),
          backgroundCursorColor: const Color(0xffaaaaaa),
        ),
        Action(
          state.isPending ? 'Saving…' : 'Save',
          state.isPending
              ? null
              : () async {
                  try {
                    await save((id: widget.post.id, title: text.text));
                  } on Object {
                    /* Mutation state displays failure; draft remains editable. */
                  }
                },
        ),
        if (state.isError) Text('Save failed: ${state.error}'),
        if (state.isSuccess) const Text('Saved'),
      ],
    ),
  );
}

final class Action extends StatelessWidget {
  const Action(this.label, this.onTap, {super.key});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          label,
          style: TextStyle(
            color: onTap == null
                ? const Color(0xff999999)
                : const Color(0xff245fda),
          ),
        ),
      ),
    ),
  );
}
