# Query

Odroe Query 管理异步 server state。它可独立用于 Dart，也与 Flutter、Router 和 Start 使用同一份状态机。

## 入口

- `package:odroe/query_core.dart`：纯 Dart client、cache、observer、mutation、infinite query、hydration 和 persistence。
- `package:odroe/query.dart`：在 core 之上增加 Flutter provider、builder 和 selector。

## 定义与读取

Query 定义是普通、可复用的强类型对象。key 的 Map 顺序不影响 identity，List 顺序会影响 identity。

```dart
import 'package:odroe/query_core.dart';

final postQuery = (int postId) => QueryOptions<Post>(
  key: QueryKey('post', [postId]),
  policy: const QueryPolicy(
    freshness: QueryFreshness.staleAfter(Duration(minutes: 1)),
  ),
  query: (context) => api.post(
    postId,
    cancelToken: context.cancelToken,
  ),
);

final client = QueryClient();
final post = await client.ensureQueryData(postQuery(42));
```

同 key 的并发请求只执行一次。`fetchQuery` 在数据 fresh 时直接返回缓存；`ensureQueryData` 在没有数据时 fetch；`prefetchQuery` 只填充状态，不把错误作为调用错误抛出。

## Flutter

```dart
final client = QueryClient();

void main() => runApp(
  QueryClientProvider(
    client: client,
    child: const App(),
  ),
);

QueryBuilder<Post>(
  options: postQuery(42),
  builder: (context, result) {
    if (result.isLoading) return const Loading();
    if (result.isLoadingError) return ErrorView(result.error!);
    return PostView(result.requireData);
  },
);
```

`status` 与 `fetchStatus` 是两个维度。已有内容后台刷新时，`isRefetching` 为真但 `requireData` 仍可用；首次离线等待是 `isPending && isPaused`，不是正在加载。

只关心结果的一部分时使用 selector，未选中的变化不会 rebuild：

```dart
QuerySelector<User, String>(
  options: currentUser,
  select: (result) => result.requireData.displayName,
  builder: (context, name) => Text(name),
);
```

## Freshness 与生命周期

```dart
const QueryPolicy(
  freshness: QueryFreshness.staleAfter(Duration(seconds: 30)),
  gcTime: Duration(minutes: 5),
  refetchOnFocus: QueryRefetchPolicy.stale,
  refetchOnReconnect: QueryRefetchPolicy.stale,
)
```

- `staleAfter(Duration.zero)`：默认，结果可立即用于 UI，也允许生命周期事件后台刷新。
- `never()`：时间不会使数据 stale，显式 invalidate 仍生效。
- `static()`：应用运行期间不可变，自动 refetch 和 invalidate 都不触发请求。
- 最后一个 observer 离开后，inactive query 默认五分钟 GC。

`QueryClientProvider` 把 Flutter app lifecycle 接到 focus manager。online manager 默认认为在线；使用 connectivity 插件或平台事件的应用只需设置：

```dart
client.onlineManager.isOnline = online;
```

## 取消、重试与离线

Query function 读取 `context.cancelToken` 就表示底层传输可取消。最后一个 observer 离开或显式 `cancelQueries` 时，状态会回滚到 fetch 前快照。

```dart
QueryPolicy(
  retry: QueryRetry.times(3),
  retryDelay: (failure, error) => Duration(seconds: 1 << failure),
  networkMode: QueryNetworkMode.online,
)
```

- `online`：离线时首次执行和 retry 都暂停。
- `always`：忽略网络状态，适合本地数据库、文件或纯计算。
- `offlineFirst`：先执行一次以允许命中本地/HTTP cache，失败后的 retry 等待联网。

## Mutation 与 optimistic update

```dart
final addTodo = MutationOptions<Todo, String, List<Todo>>(
  key: QueryKey('addTodo'),
  mutation: (title, context) => api.addTodo(title),
  onMutate: (title, context) async {
    await context.client.cancelQueries(QueryFilter(key: QueryKey('todos')));
    final previous = context.client.getQueryData<List<Todo>>(QueryKey('todos'))!;
    context.client.setQueryData<List<Todo>>(
      QueryKey('todos'),
      (current) => [...current!, Todo.optimistic(title)],
    );
    return previous;
  },
  onError: (error, stack, title, previous, context) {
    context.client.setQueryData<List<Todo>>(
      QueryKey('todos'),
      (_) => previous!,
    );
  },
  onSettled: (_, _, _, _, context) =>
      context.client.invalidateQueries(QueryFilter(key: QueryKey('todos'))),
);
```

相同非空 `scope` 的 mutation 串行执行。离线暂停的 keyed mutation 可以持久化并在恢复后继续。

Flutter 使用 `MutationBuilder`，builder 直接获得 state、`mutate` 和 `reset`。

## Infinite Query

Infinite query 仍是普通 Query cache entry，不存在第二套缓存：

```dart
final feed = InfiniteQueryOptions<FeedPage, String>(
  key: QueryKey('feed'),
  initialPageParam: '',
  maxPages: 3,
  query: (context) => api.feed(cursor: context.pageParam),
  getNextPageParam: (last, pages, cursor, cursors) => last.nextCursor,
);
```

`InfiniteQueryObserver` 和 `InfiniteQueryBuilder` 提供 next/previous controls。后台 refetch 从当前最早页开始顺序刷新；`maxPages` 同时限制内存和之后的 refetch 成本。

## Router 与 Start

每个 matched branch 的 loader 共享同一个 QueryClient，因此父子 loader 请求相同 key 时只访问一次数据源：

```dart
final route = AppRoute<Params, Search, Post>(
  load: (context) => context.query.ensureQueryData(postQuery(context.params.id)),
);
```

`OdroeRouter.query` 是 Flutter Router 使用的 client。Start 为每个 HTTP request 创建独立 client，执行 loaders 后 `dehydrate`，Flutter 通过同一格式 `hydrate`，不会泄漏其他请求的数据。

## Persistence

存储只需实现 `QueryPersister`：

```dart
final persistence = QueryPersistence(
  client: client,
  persister: appStorage,
  buster: 'schema-v2',
  maxAge: const Duration(hours: 24),
);

await persistence.restoreAndListen();
```

写入会合并短时间内的 cache 更新。恢复时先检查 max age 和 buster；损坏载荷应由 adapter 抛出，Query 会删除它并阻止继续使用。

