import 'package:odroe/query_rpc.dart';

import 'account.dart';
import 'posts.dart';

const postPolicy = QueryPolicy(
  freshness: QueryFreshness.staleAfter(Duration(minutes: 5)),
  retry: QueryRetry.never(),
);

abstract interface class PostsQueries {
  InfiniteQueryOptions<PostPage, PageInput> list(int limit);
  QueryOptions<Post> detail(int id);
  QueryFilter detailFilter(int id);
  QueryFilter details();
  MutationOptions<Post, SaveInput, void> save();
}

// Native Query definitions with immutable scalar page parameters.
// Pagination declares its own identity independently of ordinary RPC reads.
class ManualPosts implements PostsQueries {
  ManualPosts(this.account);
  final Account account;

  List<Object?> prefix<I, O>(ServerFunctionRef<I, O> ref, String shape) => [
    account.rpc.baseUri
        .resolve('${account.rpc.functionPath}/${Uri.encodeComponent(ref.id)}')
        .toString(),
    account.scope,
    ref.id,
    ref.method.name,
    shape,
  ];
  QueryKey<T> key<T, I, O>(
    ServerFunctionRef<I, O> ref,
    String shape,
    I input,
  ) => QueryKey<T>('rpc', [
    ...prefix(ref, shape),
    account.rpc.serializer.encode({
      'data': ref.encodeInput == null ? input : ref.encodeInput!(input),
    }),
  ]);

  QueryFilter lists() =>
      QueryFilter(key: QueryKey<Object?>('rpc', prefix(listPosts, 'infinite')));

  @override
  InfiniteQueryOptions<PostPage, PageInput> list(int limit) {
    final input = (cursor: 0, limit: limit);
    return InfiniteQueryOptions(
      key: key(listPosts, 'infinite', input),
      initialPageParam: input,
      policy: postPolicy,
      query: (context) => listPosts(
        account.rpc,
        context.pageParam,
        cancelled: context.query.cancelToken.whenCancelled.then<void>((_) {}),
      ),
      getNextPageParam: (page, _, _, _) => page.nextCursor == null
          ? null
          : (cursor: page.nextCursor!, limit: limit),
    );
  }

  @override
  QueryOptions<Post> detail(int id) {
    final input = (id: id);
    return QueryOptions(
      key: key(getPost, 'query', input),
      policy: postPolicy,
      query: (context) => getPost(
        account.rpc,
        input,
        cancelled: context.cancelToken.whenCancelled.then<void>((_) {}),
      ),
    );
  }

  @override
  QueryFilter detailFilter(int id) =>
      QueryFilter(key: detail(id).key, exact: true);

  @override
  QueryFilter details() =>
      QueryFilter(key: QueryKey<Object?>('rpc', prefix(getPost, 'query')));

  @override
  MutationOptions<Post, SaveInput, void> save() => MutationOptions(
    mutation: (input, _) => savePost(account.rpc, input),
    onSuccess: (saved, _, _, context) async {
      await context.client.invalidateQueries(lists());
      await context.client.invalidateQueries(detailFilter(saved.id));
    },
  );
}

// Ordinary RPC reads compose with the native pagination and save definitions.
final class RpcReadPosts extends ManualPosts {
  RpcReadPosts(super.account);

  @override
  QueryOptions<Post> detail(int id) => getPost.read(
    account.rpc,
    (id: id),
    scope: account.scope,
    policy: postPolicy,
  );

  @override
  QueryFilter detailFilter(int id) =>
      getPost.readAt(account.rpc, (id: id), scope: account.scope);

  @override
  QueryFilter details() => getPost.reads(account.rpc, scope: account.scope);
}
