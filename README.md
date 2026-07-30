# Odroe

Odroe 是单包、可组合的 Flutter 全栈元框架。Flutter 构建 Android、iOS、Web、桌面或其他目标；只有应用选择 Web 时，Document 的 SSR/SSG 与 Flutter 首屏交接才参与构建。

Odroe 不提供一个暗中装配全部能力的全局对象。应用显式选择 modules；Router、Query、Document、RPC 与 Server 也都能独立导入。

## 入口

| 入口 | 能力 |
| --- | --- |
| `odroe.dart` | 平台中立的 `Module`、binding、`AppContext` 与生命周期 |
| `odroe_flutter.dart` | Flutter `App` 组合根与 Flutter binding |
| `query.dart` | 平台中立的 Query、Mutation、cache、hydration 与 persistence |
| `query_flutter.dart` | Query Flutter provider、builders 与 `QueryModule` |
| `router.dart` | 基于 Roux 的中立强类型 route、params/search、matching 与 URL 生成 |
| `router_flutter.dart` | `PageRoute`、`ShellRoute`、`AppRouter` 与 `RouterModule` |
| `document.dart` | 语义 HTML、metadata、SEO/GEO、SSR/SSG renderer |
| `document_flutter.dart` | Flutter Web 首屏 handoff 与 `DocumentModule` |
| `mdc.dart` | renderer-neutral MDC AST、parser、组件与安全 HTML renderer |
| `mdc_flutter.dart` | MDC Flutter renderer、controller 与样式入口 |
| `press.dart` | 平台中立的不可变内容集合与 `PressPage` |
| `press_io.dart` | 文件系统 MDC discovery、原子 snapshot 与缓存 |
| `database.dart` | typed SQL transport、`SqlQueries`、row codec 与 transaction capability |
| `database_sqlite.dart` | 已验证的 native SQLite driver |
| `database_postgres.dart` | 已验证的 PostgreSQL driver |
| `database_mysql.dart` | Preview MySQL/MariaDB driver |
| `database_d1.dart` | Preview Cloudflare D1 binding adapter |
| `rpc.dart` | 强类型 server functions、client、transport 与 `RpcModule` |
| `server.dart` | adapter-neutral HTTP、middleware、route 与 `Server` |
| `server_io.dart` | Dart IO host 与 prerenderer |
| `server_fetch.dart` | Preview Fetch/JavaScript host adapter |

无后缀入口保持平台中立。平台实现放在明确入口中：`*_flutter.dart`、
`*_io.dart`、`server_fetch.dart` 与各 `database_<driver>.dart`。

## 创建应用

```sh
flutter create my_app
cd my_app
```

当前重构版先通过源码使用：

```yaml
dependencies:
  odroe:
    path: ../odroe
```

```sh
flutter pub get
```

```text
lib/
├── main.dart
├── routes/
│   ├── route.dart
│   ├── shell.dart
│   ├── page.dart
│   └── posts/
│       └── [postId]/
│           ├── route.dart
│           ├── page.dart
│           └── server.dart
├── routes.dart          # generated client tree
└── routes.server.dart   # generated server tree
```

每个包含 `page.dart`、`shell.dart` 或 `server.dart` 的目录必须包含自己的中立 `route.dart`。没有 flat-route 语法、annotation、`part`、build_runner、registry 或 hash 清单。

## 组合应用

```dart
import 'package:flutter/material.dart';
import 'package:odroe/document_flutter.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';

import 'routes.dart';

void main() {
  runApp(
    App(
      modules: <Module>[
        QueryModule(),
        RpcModule.http(),
        DocumentModule(),
        RouterModule(routes: routeTree),
      ],
      builder: (app) => MaterialApp.router(
        routerConfig: app.read(routerKey),
      ),
    ),
  );
}
```

删掉任意 module 就会删掉对应集成；`odroe.dart` 本身不创建 Query、Router、RPC、Provider 或 transport。独立使用 Router 时也可以直接创建 `AppRouter(routes: ...)`。

Web 可让 `RpcModule.http()` 使用当前 origin；Android、iOS 与桌面应用应传入明确的服务端地址，例如 `RpcModule.http(baseUri: Uri.parse('https://api.example.com'))`。

## 文件路由

`route.dart` 承载跨平台的强类型合同，以及可选的 Document 中立绑定。
Document 由 `document.dart` 提供，不是 `AppRoute` 核心参数，也不属于
`page.dart` 或 `server.dart`。

```dart
import 'package:odroe/document.dart';
import 'package:odroe/router.dart';

typedef Params = ({int postId});
typedef Search = ({bool preview});

final route =
    AppRoute<Params, Search, NoData>(
      metadata: const RouteMetadata(description: 'Readable post content.'),
      params: const PathParams<Params>.schema(),
      search: const SearchParams<Search>.schema(
        defaults: (preview: false),
      ),
    ).document(
      (context) => RouteDocument(
        title: 'Post ${context.params.postId}',
        body: HtmlElement(
          'h1',
          children: <HtmlNode>[
            HtmlText('Post ${context.params.postId}'),
          ],
        ),
      ),
    );
```

`page.dart` 只绑定 Flutter 客户端行为：

```dart
import 'package:flutter/widgets.dart';
import 'package:odroe/router_flutter.dart';

import 'route.dart' as definition;

final route = definition.route.page(
  build: (context) => Text('Post ${context.params.postId}'),
);
```

`server.dart` 只绑定服务端 loader、HTTP handler 与 server functions：

```dart
import 'package:odroe/router.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server.dart';

import 'route.dart' as definition;

final route = definition.route.server(
  load: (_) => const NoData(),
  handlers: <HttpMethod, ServerRouteHandler<definition.Params, definition.Search>>{
    HttpMethod.get: (context) => ServerResponse.json(
      <String, Object?>{'postId': context.params.postId},
    ),
  },
);

final updatePost = ServerFunction<int, bool>(
  handler: (context) async => repository.update(context.data),
);
```

文件名只有一种心智：`definition.route.page(...)`、`definition.route.shell(...)`、`definition.route.server(...)`、`definition.route.document(...)`。

## 服务端组合

生成的 `routes.server.dart` 暴露 `createServer(modules: ...)`。需要全局 middleware、request-scoped Query 或自定义 renderer 时，创建应用级 `lib/server.dart`；CLI 会自动把它作为 server 入口：

```dart
import 'package:odroe/query.dart';
import 'package:odroe/server.dart';

import 'routes.server.dart' as generated;

Server createServer() => generated.createServer(
  modules: () => <QueryClientModule>[QueryClientModule.server()],
);
```

loader、middleware 与 server function 都可以通过 `context.read(queryClientKey)` 读取该请求显式安装的 Query client。没有 `lib/server.dart` 时，CLI 直接使用生成的默认 server。

## 内容与静态页面

Press 将 MDC 目录读取为一个不可变、排序且原子发布的 snapshot。平台中立的 route 只导入 `press.dart`；文件系统 discovery 留在 server 或 prerender 入口。

```dart
import 'package:odroe/press_io.dart';

final docs = PressDirectory('content/docs', mount: '/docs');
final snapshot = await docs.snapshot();
final page = snapshot.page(const <String>['getting-started']);
```

应用可用 `lib/prerender.dart` 返回动态静态地址。CLI 会与文件路由的静态地址
合并、规范化、去重并排序，再通过真实 server 构建页面。默认只构建这份显式
清单；需要从页面发现额外同源 HTML 时使用 `--prerender-crawl`。

```dart
import 'content.dart';

Future<Iterable<Uri>> prerenderLocations() => docs.locations();
```

## 数据库

`database.dart` 提供小而明确的 typed SQL transport 与单表查询层。
方言必须显式选择；column receiver 固定赋值和谓词类型。

```dart
final class Posts extends SqlTable<String> {
  Posts() : super('posts');

  late final id = column<int>('id', sqlInt);
  late final title = column<String>('title', sqlText);

  @override
  late final projection = SqlProjection.column(title);
}

final posts = Posts();
const sql = SqlQueries(SqlDialect.sqlite);

final titles = await sql
    .selectTable(posts, where: posts.id.equals(42))
    .all(database);

await sql.insert(
  posts,
  <SqlAssignment>[posts.title.set('Hello')],
).execute(database);

await sql.updateAll(
  posts,
  <SqlAssignment>[posts.title.set('Archived')],
  confirm: allRows,
).execute(database);
```

`posts.title.set(42)` 会在分析期失败。`updateAll`/`deleteAll` 同时要求方法名
与 `allRows` 两次确认。`BoundSql` 保留为手写 SQL 逃生口：

```dart
final statement = BoundSql.parts(
  <String>['SELECT "title" FROM "posts" WHERE "id" = ', ''],
  <SqlValue>[sqlInt.encode(42)],
  kind: SqlStatementKind.rowReturning,
);
final manualTitles = await database.query(
  statement,
  (row) => row.read(0, sqlText),
);
```

driver 只在 fragments 之间插入 native placeholder，不解析或重写 SQL。SQLite 与
PostgreSQL 已通过真实合同测试。D1 是 Preview，已通过本地
Wrangler/Workerd；它提供原子 batch，不提供交互式 transaction。
MySQL/MariaDB 是 Preview，已通过真实 MySQL 8.4 与 MariaDB 11.8；当前为
单连接串行 driver，不支持 nested transaction、multiple result sets、portable
`TIME` 解码或 `SqlDialect.mysql` 的 `RETURNING`。

MySQL 的无绑定值语句会在 I/O 前拒绝 `;`，以阻止 text protocol 执行多条
语句；不要给手写 MySQL SQL 添加尾分号。带绑定值的语句使用 prepared
protocol。

顶层调用可把手写 SQL 保持为默认的 `unknown`，但错误 terminal 可能要在
数据库执行后才能识别；已知形态时应显式标记。`atomicWrite` 与 transaction
callback 必须声明 `write` 或 `rowReturning`，因此 transaction control
与会隐式提交的 DDL 不会被误放进框架管理的事务。
由于 D1 raw result 无法区分空查询与写入，D1 的 `query` 还会在发送前要求
`rowReturning`；`SqlQueries` 已自动提供该标记。

## CLI

```sh
dart run odroe generate
dart run odroe dev
dart run odroe dev --server-only
dart run odroe dev -- -d ios
dart run odroe dev -- -d chrome
dart run odroe build apk
dart run odroe build web
dart run odroe build --server-only --server-target cloudflare
```

`dev` 不默认 Web；`--` 后参数原样交给 Flutter CLI。`build web` 会构建 Flutter Web 与 server artifact，再通过真实 server prerender 静态 route。纯 Document route 输出纯 HTML；带 Flutter page 的 route 输出可读语义 HTML、handoff state 与原样 `/flutter_bootstrap.js`，随后由已加载的 Flutter app 承接导航。

prerender 默认使用 4 个并发请求，最多处理 1000 个 route，每个 HTML 响应
最多 1 MiB。`--prerender-concurrency`、`--prerender-max-routes` 与
`--prerender-max-response-bytes` 可显式调整预算。Cloudflare 构建复用生成的
Dart server 源码完成 prerender，不再额外编译临时 native executable。
纯文档构建会先写入同级 staging 目录，全部成功后才替换既有静态产物。

`build --server-only` 生成的 native executable 与构建 OS/architecture 绑定。
请在目标平台或兼容 builder 中构建。

Cloudflare target 生成 `build/odroe/cloudflare/server.js` 与薄
`worker.mjs`。平台配置仍由应用持有；Odroe 不覆盖已有
`wrangler.jsonc`。当前只验证了本地 Wrangler/Workerd，尚未验证远端
Cloudflare 部署。

可运行应用见 [`example/app`](example/app)。官网源码与正式文档位于
[`sites/odroe.dev`](sites/odroe.dev)，由 Odroe 的 Document、Press 与 SSG
构建。当前 `odroe.dev` 外部访问受 Cloudflare 526 SSL 错误阻塞，不宣称已
线上可用。
