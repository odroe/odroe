# Odroe Router

## 心智模型

Router 只有一套 runtime：`AppRoute`。

- 手动模式直接组装 `AppRoute` tree；
- 文件模式把 `lib/routes/` 编译为同一种 tree；
- `page.dart`、`shell.dart`、`server.dart` 是同一个 route contract 的不同运行边界，不是不同路由类型；
- 生成的 `routes` 只提供强类型绝对引用，不参与匹配和渲染。

因此用户可以完全不使用文件路由，也可以用文件路由获得更好的默认体验。

## 目录规范

每一级目录对应一个 route node，不支持 flat route 文件名语法。

```text
lib/routes/
├── page.dart                    /
├── posts/
│   ├── page.dart                /posts
│   └── [postId]/
│       ├── route.dart           /posts/:postId 的契约
│       ├── page.dart            /posts/:postId 的 Flutter 页面
│       └── server.dart          服务端 route
├── docs/
│   └── [...slug]/               /docs/*slug
└── (account)/                   不进入 URL 的分组
    └── settings/
        └── page.dart            /settings
```

目录段只有四种：

| 目录 | URL | params |
| --- | --- | --- |
| `posts` | `/posts` | 无 |
| `[postId]` | `/:postId` | 一个 scalar |
| `[...slug]` | `/*slug` | `List<String>`，且必须是叶子 |
| `(account)` | 无 | 无，仅组织代码与引用 |

多个非终止 route group 可以位于同一级。会造成相同终止 URL 的 group 会被诊断为冲突。

## 四类 route 文件

### `route.dart`

声明 page 与 server 共同使用的类型、params/search codec、data 类型与可在当前 runtime 执行的 loader。它不得导入服务端实现。

每个 `route.dart` 必须导出顶层 `route`，并直接初始化 `AppRoute<Params, Search, Data>`。动态目录必须声明命名 record `Params`；拥有 search 的 route 必须声明命名 record `Search`。

共享契约从 `package:odroe/route.dart` 导入。该入口不依赖 Flutter UI，因此同一个 `route.dart` 可被客户端 page 和 Dart VM server 同时引用。

### `page.dart`

声明 Flutter 页面，也必须导出顶层 `route`：

```dart
final route = definition.route.page(
  build: (context) => PostPage(
    postId: context.params.postId,
    preview: context.search.preview,
    data: context.data,
  ),
  pending: (context) => const LoadingView(),
  error: (context, error) => ErrorView(error),
  notFound: (context) => const NotFoundView(),
);
```

没有独立契约的静态页面可直接使用 `pageRoute(build: ...)`。

需要自定义 `Page` 与转场时使用 `page:`。该 API 不伪造页面内部的 `BuildContext`，而是传入不依赖 context 的强类型 state，以及 Navigator 必须持有的 settings：

```dart
final route = definition.route.page(
  page: (state, settings) => MaterialPage<Object?>(
    key: settings.key,
    name: settings.name,
    onPopInvoked: settings.onPopInvoked,
    child: PostPage(data: state.data),
  ),
);
```

自定义 Page 必须使用 `settings.key` 与 `settings.onPopInvoked`，从而保持 `Navigator.pages` 身份和 `push<T>` 返回值正确。

### `shell.dart`

声明持久布局和真实的嵌套 `Navigator`：

```dart
final route = shellRoute(
  build: (context, navigator) => AppScaffold(body: navigator),
);
```

同一目录可以同时存在 `shell.dart` 与 `page.dart`。此时 page 是 shell 自己 URL 的 index page，后代 page 进入 shell 的嵌套 Navigator。

### `server.dart`

声明服务端实现，且必须复用同目录的 `route.dart`：

```dart
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server(
  load: (context) => loadPost(context.params.postId),
);
```

`server.dart` 不会进入客户端 `lib/routes.dart`。编译器把它写入独立的 `lib/routes.server.dart`，并把其中的 Server Function 转成 client-safe typed ref。loader、middleware、公开 HTTP handler 和 RPC 都复用同一个 route identity；完整协议见 [Server、RPC、SSR/SSG](server.md)。

Loader 可以强类型读取 active ancestor 的 params/search，父子 loader 仍然并行：

```dart
load: (context) {
  final organizationId = context
      .match(organizationRoute)!
      .params
      .organizationId;
  return loadProject(organizationId, context.params.projectId);
},
```

## 强类型 params

自动 schema 支持：

- `[name]`：`String`、`int`、`double`、`bool`；
- `[...name]`：`List<String>`。

字段名必须与当前动态目录完全一致。生成引用会把所有祖先 path params 合并为一个命名 record：

```dart
routes.organizations.organizationId.projects.projectId.to(
  params: (organizationId: 'odroe', projectId: 7),
);
```

自定义类型使用双向 codec，编码与解码必须同时声明：

```dart
final route = AppRoute<Params, NoSearch, NoData>(
  params: PathParams<Params>.codec(
    decode: (input) => (postId: PostId(input.requiredString('postId'))),
    encode: (value, output) =>
        output.string('postId', value.postId.value),
  ),
);
```

供生成的公开引用使用的自定义字段类型，应由 `route.dart` 自己声明或 export。

## 强类型 search

Search 是 route-owned state，不是无类型的 `Map<String, String>`。每个 search contract 必须提供完整 defaults；编码时会自动省略等于 defaults 的值，形成稳定 canonical URL。

```dart
typedef Search = ({int page, String? query});

final route = AppRoute<NoParams, Search, NoData>(
  search: const SearchParams<Search>.schema(
    defaults: (page: 1, query: null),
  ),
);
```

一个目标同时拥有祖先与叶子 search 时，生成 API 保留 ownership：叶子使用 `search`，祖先使用按 route 命名的参数，例如 `postsSearch`。编码和匹配都会拒绝两个 active route 占用同一个 query key。

无效 search 默认回退到 defaults，并把错误保存在 `RouteMatch.searchError`；需要严格失败时设置 `invalid: InvalidSearchBehavior.error`。

匹配成功后，`RouteMatches.location` 会用解码后的 typed state 重新编码 canonical URL：path 值被规范化、等于 defaults 的 owned search 被移除；未被任何 route 声明的 query key 与 fragment 保留。原始输入仍可通过 `RouteMatches.sourceLocation` 读取。Flutter Router 会使用 canonical location 更新当前路由。

自定义 codec 必须通过 `keys` 完整声明它拥有的 query key。该集合既用于父子 ownership 冲突检查，也保证 decode 提前 fallback 时不会漏掉尚未读取的 key；读写未声明 key 会立即报错：

```dart
SearchParams<Search>.codec(
  keys: const {'page', 'query'},
  defaults: (page: 1, query: null),
  decode: (input) => (
    page: input.integer('page') ?? 1,
    query: input.string('query'),
  ),
  encode: (value, output) {
    output.integer('page', value.page, omitIf: 1);
    output.string('query', value.query);
  },
);
```

## 生成结果

运行：

```sh
dart run odroe generate
dart run odroe dev
```

默认读取 `lib/routes/`，输出格式化后的 `lib/routes.dart` 和 `lib/routes.server.dart`。也可设置 `--project`、`--routes`、`--output`、`--server-output`；持续监听时使用 `generate --watch`。

生成文件只包含：

- 一个普通 `List<RouteNode> routeTree`；
- 一个分层、强类型、绝对地址的 `routes` facade；
- `PathParams.schema()` / `SearchParams.schema()` 对应的双向 codec。

没有 annotation、`part`、`build_runner`、manifest、hash gate 或另一套 `FileRoute` runtime。

## Flutter 集成

```dart
final router = OdroeRouter(
  routes: routeTree,
  initialLocation: Uri.parse('/'),
  loading: (context) => const LoadingView(),
  notFound: (context) => const NotFoundView(),
  error: (context, error, stackTrace) => ErrorView(error),
);

MaterialApp.router(routerConfig: router);
```

页面内使用 `RoutePageContext.router`：

```dart
context.router.go(routes.home.to());
final result = await context.router.push<bool>(routes.editor.to());
context.router.replace(routes.login.to());
```

- `go`：替换当前匹配分支；
- `push<T>`：增加一个可返回 `T?` 的导航记录；
- `replace`：替换栈顶记录；
- Flutter/browser restoration 只持久化 URI，内部 completer 不跨平台 JSON 边界；
- loader 以 route 为粒度并行运行，旧导航的迟到结果不会覆盖新页面。

## 手动模式

单段绝对 route 可直接 `to()`：

```dart
final about = AppRoute<NoParams, NoSearch, NoData>(path: '/about');
router.go(about.to());
```

嵌套 route 使用 `RouteRef` 逐段绑定各自强类型状态：

```dart
final destination = organization
    .ref(
      params: (organizationId: 'odroe'),
      search: (tab: 'activity'),
    )
    .then(project.ref(params: (projectId: 7)))
    .destination;
```

`RouteRefPath` 使用与文件路由完全相同的双向 codec，并在合并 search 时检查 ownership 冲突。

`package:odroe/route.dart` 公开平台中立的 params、search、matcher、loader contract、`RouteRef` 与 `Destination`；`package:odroe/router.dart` 导出 `route.dart`，并增加 Flutter page、shell 与 `OdroeRouter`。route `server.dart` 使用 `package:odroe/server.dart`，需要共享 route 类型时同时导入 `package:odroe/route.dart`，不会把 Flutter UI 带入服务端。
